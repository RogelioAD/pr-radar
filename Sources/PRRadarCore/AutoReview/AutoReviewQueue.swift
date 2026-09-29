import Foundation

/// The knobs on automatic review.
///
/// Most are not worth a settings row each and stay at their defaults here.
/// `maxPerHour` is the exception: it is the one that stops the queue outright,
/// and a ceiling nobody can see or move is indistinguishable from the feature
/// being broken — the row says "hourly limit reached" and, until it was
/// settable, there was nothing on screen that could raise it.
public struct AutoReviewPolicy: Equatable, Sendable {
    public var isEnabled = false
    /// A draft is not asking yet.
    public var skipDrafts = true
    /// How many times one ping's review may be attempted before it stops. A
    /// broken setup should give up, not grind.
    public var maxAttempts = 2
    public var retryAfter: TimeInterval = 3_600
    /// A ceiling on how much this can cost while nobody is watching. Zero
    /// means no ceiling, which is a choice rather than a default.
    public var maxPerHour = 6

    public init(isEnabled: Bool = false, skipDrafts: Bool = true,
                maxAttempts: Int = 2, retryAfter: TimeInterval = 3_600,
                maxPerHour: Int = 6) {
        self.isEnabled = isEnabled
        self.skipDrafts = skipDrafts
        self.maxAttempts = maxAttempts
        self.retryAfter = retryAfter
        self.maxPerHour = maxPerHour
    }

    /// How many more reviews may start in this hour — `Int.max` when uncapped.
    ///
    /// A method rather than the subtraction written out at each call site,
    /// because both edges of it are sharp. Zero means no cap, so the plain
    /// `startedInLastHour < maxPerHour` comparison reads an uncapped setting as
    /// a cap of none and stops the queue outright. And the difference goes
    /// negative the moment the cap is lowered below what has already run —
    /// which a user can now do from Settings, mid-hour — where `prefix` traps
    /// rather than returning nothing.
    public func remainingThisHour(started: Int) -> Int {
        guard maxPerHour > 0 else { return .max }
        return max(0, maxPerHour - started)
    }
}

/// Why a pull request is not being reviewed.
///
/// A closed set rather than a free string, because every one of these is shown
/// on the row: a PR that is quietly not being reviewed looks identical to one
/// the feature is broken for, and the difference is the whole of whether
/// somebody trusts it.
public enum AutoReviewSkip: String, Equatable, Sendable {
    case disabled
    case repoNotAllowed
    case ownPullRequest
    case draft
    case notActionable
    case attemptsExhausted
    case backingOff
    case rateLimited
    case alreadyHandled

    /// What the row says. Short enough for a chip.
    public var reason: String {
        switch self {
        case .disabled: return "auto-review off"
        case .repoNotAllowed: return "auto-review off here"
        case .ownPullRequest: return "your own PR"
        case .draft: return "draft"
        case .notActionable: return "cannot be acted on"
        case .attemptsExhausted: return "review failed twice"
        case .backingOff: return "retrying later"
        case .rateLimited: return "hourly limit reached"
        case .alreadyHandled: return "already reviewed"
        }
    }

    /// Whether the row should say this out loud.
    ///
    /// The uninteresting ones are silent: a row does not need a chip saying the
    /// feature it never opted into is switched off, and "already reviewed" is
    /// what the posted state already says in more detail.
    public var isWorthShowing: Bool {
        switch self {
        case .disabled, .alreadyHandled: return false
        default: return true
        }
    }
}

/// Which pull requests should be reviewed next.
///
/// Pure, so every "why is nothing happening" answer is a test rather than an
/// afternoon with the debugger. Being offline is deliberately *not* modelled
/// here — the caller owns that, and putting it in would make the rule depend on
/// something no test can set.
public enum AutoReviewQueue {

    /// Everything eligible right now, oldest ping first — the same ordering the
    /// list itself defaults to, so the most overdue review is also the first
    /// one attempted.
    public static func pending(items: [ReviewItem],
                               log: AutoReviewLog,
                               viewerLogins: Set<String>,
                               allowlist: Set<String>,
                               policy: AutoReviewPolicy,
                               startedInLastHour: Int,
                               now: Date) -> [ReviewItem] {
        guard policy.isEnabled else { return [] }
        let room = policy.remainingThisHour(started: startedInLastHour)
        guard room > 0 else { return [] }

        return items
            .filter { skip(for: $0, log: log, viewerLogins: viewerLogins,
                           allowlist: allowlist, policy: policy,
                           startedInLastHour: startedInLastHour, now: now) == nil }
            .sorted { $0.pingedAt < $1.pingedAt }
            .prefix(room)
            .map { $0 }
    }

    /// Where a pull request stands while it waits its turn.
    ///
    /// A review runs on its own — one worker, one session at a time — so a
    /// second eligible pull request sits there until the first finishes. It had
    /// nothing to say about that: `recordSkips` only writes a record when there
    /// is a *reason* not to review something, and "eligible, just waiting" is
    /// not one, so the row showed no chip at all and read as untouched.
    public enum Waiting: Equatable, Sendable {
        /// First in line — the one that starts when the current review ends.
        case next
        /// Behind at least one other.
        case queued

        /// What the chip says.
        public var label: String {
            switch self {
            case .next: return "next for review"
            case .queued: return "queued for review"
            }
        }
    }

    /// The pull requests waiting their turn, in the order they will be taken.
    ///
    /// The one in flight is excluded: it is not waiting, it has arrived, and
    /// its own row already says "reviewing…" with a stopwatch running.
    public static func waiting(pending: [ReviewItem], inFlight: String?) -> [String] {
        pending.map(\.pingKey).filter { $0 != inFlight }
    }

    /// Where one row sits in that queue, or nil when it is not in it.
    public static func waiting(for pingKey: String, in queue: [String]) -> Waiting? {
        guard let index = queue.firstIndex(of: pingKey) else { return nil }
        return index == 0 ? .next : .queued
    }

    /// Why this one is not being reviewed, or nil if it should be.
    public static func skip(for item: ReviewItem,
                            log: AutoReviewLog,
                            viewerLogins: Set<String>,
                            allowlist: Set<String>,
                            policy: AutoReviewPolicy,
                            startedInLastHour: Int,
                            now: Date) -> AutoReviewSkip? {
        guard policy.isEnabled else { return .disabled }
        // Case-insensitively, because GitHub treats repo names that way and a
        // capital letter in a settings field is not a decision to exclude a repo.
        guard allowlist.contains(item.repo.lowercased()) else { return .repoNotAllowed }
        guard !viewerLogins.contains(item.authorLogin) else { return .ownPullRequest }
        if item.isDraft && policy.skipDrafts { return .draft }
        // Every mutation needs the PR's node id. Without one there is nothing to
        // post to, and a review nobody can read is only an expense.
        guard item.nodeID != nil else { return .notActionable }

        if let record = log[item.pingKey] {
            switch record.status {
            case .running, .ready, .posted, .dismissed:
                // Work that is in flight, or done. One ping gets one review.
                return .alreadyHandled
            case .queued:
                // Wanted but not started — which is a reason to run it, not a
                // reason to refuse. Counting it as handled was a deadlock with
                // no way out: Re-run sets exactly this status, so pressing it
                // parked the row in `queued` for good and the button that was
                // meant to retry became the one that made retrying impossible.
                break
            case .skipped:
                // Deliberately *not* `.alreadyHandled`. A skip is a condition,
                // not a verdict: the repo was not allowlisted yet, the skill was
                // not set yet, the PR was still a draft. Every one of those is
                // something the user then goes and fixes, and remembering the
                // old answer would leave the row insisting on a reason that had
                // stopped being true — with no way to argue with it, because the
                // record was also what stopped it being reconsidered.
                //
                // Falling through re-tests the conditions above, which either
                // name the reason again or let it run.
                break
            case .failed:
                guard record.attempts < policy.maxAttempts else { return .attemptsExhausted }
                if let finishedAt = record.finishedAt,
                   now.timeIntervalSince(finishedAt) < policy.retryAfter {
                    return .backingOff
                }
            }
        }

        guard policy.remainingThisHour(started: startedInLastHour) > 0 else {
            return .rateLimited
        }
        return nil
    }
}
