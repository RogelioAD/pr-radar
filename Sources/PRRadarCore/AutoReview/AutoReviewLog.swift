import Foundation

/// Where one automatic review has got to.
///
/// A one-way walk: `queued → running → (ready | failed)`, `ready → posted`,
/// `posted → dismissed`. `skipped` is terminal for anything the queue declined.
///
/// Decoded leniently, because this is persisted and a build that adds a state
/// must not make an older app's whole log unreadable — `Codable` fails a value,
/// not a field, so one unknown string would otherwise cost every record.
public enum AutoReviewStatus: String, Codable, Sendable, CaseIterable {
    /// Chosen for review, not yet started.
    case queued
    /// The skill is running.
    case running
    /// Findings are in hand but nothing has been posted yet. Only reachable
    /// when the user has turned automatic posting off.
    case ready
    /// A review is on the PR. This is the only status that pins a row.
    case posted
    /// The user picked an action, so the row has served its purpose.
    case dismissed
    /// Something went wrong. `failure` says what.
    case failed
    /// The queue declined this one. `failure` carries the reason, in words a
    /// row can show.
    case skipped

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AutoReviewStatus(rawValue: raw) ?? .skipped
    }
}

/// What PR Radar remembers about one automatic review.
///
/// Keyed in the log by `pingKey`, not by PR id: a re-request is a new question
/// and deserves a new answer, and keying by ping is what makes that fall out
/// rather than needing to be handled.
public struct AutoReviewRecord: Codable, Equatable, Sendable {
    public var status: AutoReviewStatus = .queued
    public var startedAt: Date?
    public var finishedAt: Date?
    /// How many times the skill has been run for this ping. The queue stops
    /// retrying a failure past a limit rather than grinding at a broken setup.
    public var attempts: Int = 0

    /// Findings per tier, by `FindingTier.rawValue`.
    ///
    /// Counts rather than the findings themselves: the row only ever shows
    /// "2 priority · 5 mild", and putting whole review bodies in `UserDefaults`
    /// to render a number would be a lot of disk for a chip.
    public var counts: [String: Int] = [:]

    /// The review body, kept only between `ready` and `posted`, and reused as
    /// the Request-changes body afterwards. Truncated on write.
    public var body: String?

    /// Every finding the review turned up, with where it would be anchored and
    /// whether it is going out.
    ///
    /// The unit curated mode edits. Held rather than a finished review because
    /// unticking a finding has to change the summary too, and the diff it was
    /// anchored against is long gone by the time anyone ticks a box.
    public var prepared: [PreparedFinding] = []

    /// The inline threads the body goes out with.
    ///
    /// Persisted alongside it, and that is the whole point: with automatic
    /// posting off, the review is composed on one launch and posted on a button
    /// press that might come minutes later. Storing only the body meant the
    /// Post button had nothing to attach, so every manually-posted review went
    /// out as a bare summary with no inline comments at all — silently dropping
    /// the findings-at-`file:line` this feature exists for.
    public var threads: [ReviewThread] = []

    /// Our own review, so a re-run can supersede it and the pin can name it.
    public var reviewNodeID: String?
    public var reviewURLString: String?
    /// Threads we opened, so a re-run can resolve them.
    public var threadNodeIDs: [String] = []

    /// Why it failed or was skipped, in words a row can show. Never a stack
    /// trace and never a whole stderr dump — see `truncated(_:)`.
    public var failure: String?

    public init(status: AutoReviewStatus = .queued) {
        self.status = status
    }

    /// Decoded field by field, every one of them optional.
    ///
    /// Swift's synthesized decoder ignores default values: a property that is
    /// not optional throws when its key is missing, and `Codable` fails the
    /// whole *value* rather than the field — so one property added in a later
    /// build makes every record an older one wrote unreadable, and the log
    /// comes back empty. That is not hypothetical; adding `threads` did exactly
    /// that, and the two tests below are what caught it.
    ///
    /// This type is persisted and will gain fields again, so it reads leniently
    /// by construction rather than being patched each time.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Absent reads as skipped, which neither pins a row nor re-queues one —
        // the safe answer for a record this build cannot fully understand.
        status = try container.decodeIfPresent(AutoReviewStatus.self, forKey: .status) ?? .skipped
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        attempts = try container.decodeIfPresent(Int.self, forKey: .attempts) ?? 0
        counts = try container.decodeIfPresent([String: Int].self, forKey: .counts) ?? [:]
        body = try container.decodeIfPresent(String.self, forKey: .body)
        threads = try container.decodeIfPresent([ReviewThread].self, forKey: .threads) ?? []
        prepared = try container.decodeIfPresent([PreparedFinding].self, forKey: .prepared) ?? []
        reviewNodeID = try container.decodeIfPresent(String.self, forKey: .reviewNodeID)
        reviewURLString = try container.decodeIfPresent(String.self, forKey: .reviewURLString)
        threadNodeIDs = try container.decodeIfPresent([String].self, forKey: .threadNodeIDs) ?? []
        failure = try container.decodeIfPresent(String.self, forKey: .failure)
    }

    public var reviewURL: URL? { reviewURLString.flatMap(URL.init(string:)) }

    public func count(_ tier: FindingTier) -> Int { counts[tier.rawValue] ?? 0 }

    /// A failure message a row can carry. Long enough to name a cause, short
    /// enough that a runaway stderr cannot grow the stored blob without bound.
    public static func truncated(_ message: String, limit: Int = 300) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        return String(trimmed.prefix(limit)) + "…"
    }
}

/// Every automatic review the app remembers, as one blob.
///
/// One `UserDefaults` key rather than a key per PR, for the reason
/// `TrophyState` gives: the whole thing is rewritten whenever any part of it
/// changes, and a dozen writes to say nothing changed is eleven too many.
public struct AutoReviewLog: Codable, Equatable, Sendable {
    public var records: [String: AutoReviewRecord] = [:]

    public init() {}

    public subscript(pingKey: String) -> AutoReviewRecord? {
        get { records[pingKey] }
        set { records[pingKey] = newValue }
    }

    /// The bridge into `ReviewInbox`: the reviews that should not count as the
    /// viewer having dealt with their PR.
    ///
    /// Only `posted` records, and only those that actually know their node id.
    /// A `dismissed` record is deliberately absent — dropping the pin is the
    /// entire mechanism behind "Leave comment only", and the ordinary activity
    /// rule then hides the row with no further help.
    public var pins: [String: String] {
        records.compactMapValues { record in
            record.status == .posted ? record.reviewNodeID : nil
        }
    }

    /// Keeps anything still on screen, drops finished work that has aged out,
    /// then trims to a ceiling oldest-first.
    ///
    /// Live pings are kept *however old*, because a record missing for a PR
    /// still in the list would be read as "never reviewed" and queue the work
    /// again — pruning must never cause a second review of the same ping.
    public mutating func prune(liveKeys: Set<String>,
                               now: Date,
                               maxAge: TimeInterval = 14 * 86_400,
                               limit: Int = 200) {
        records = records.filter { key, record in
            if liveKeys.contains(key) { return true }
            guard let finishedAt = record.finishedAt else { return true }
            return now.timeIntervalSince(finishedAt) < maxAge
        }

        guard records.count > limit else { return }
        let expendable = records
            .filter { !liveKeys.contains($0.key) }
            .sorted { ($0.value.finishedAt ?? .distantFuture) < ($1.value.finishedAt ?? .distantFuture) }
        for (key, _) in expendable.prefix(records.count - limit) {
            records[key] = nil
        }
    }

    /// Puts every review that was in flight when the app last stopped back in
    /// the queue, and names the ones it moved.
    ///
    /// Called once, at launch, and it is the only thing that rescues them.
    /// `running` is persisted; the work behind it — a subprocess and a `Task` —
    /// is not. So a `running` record read back at startup belongs to a process
    /// that no longer exists, and nothing in the ordinary flow ever reconsiders
    /// it: `AutoReviewQueue.skip` reads it as `.alreadyHandled`, `recordSkips`
    /// declines to touch any record that is not `skipped`, and `prune` keeps
    /// anything without a `finishedAt` for good. The row sat at "reviewing…"
    /// for ever, with no button on it, and the only way out was deleting a
    /// defaults key.
    ///
    /// Reset to `queued` rather than `failed`, because being interrupted is not
    /// a verdict on the review: `failed` would park it in `backingOff` for an
    /// hour to punish it for the app having been restarted. The attempt is
    /// rolled back for the same reason — it produced no findings, so it should
    /// not count against `maxAttempts`, or two interrupted installs would
    /// exhaust a PR's budget without anyone having read a word.
    @discardableResult
    public mutating func reconcileInterrupted() -> [String] {
        let interrupted = records.compactMap { $0.value.status == .running ? $0.key : nil }
        for key in interrupted {
            // Through a local, because reading and writing `records` in one
            // expression is two overlapping accesses to the same storage and
            // Swift will not have it.
            guard var record = records[key] else { continue }
            record.status = .queued
            record.startedAt = nil
            record.attempts = max(0, record.attempts - 1)
            records[key] = record
        }
        // Sorted so a caller logging them gets a stable line rather than a
        // dictionary's order.
        return interrupted.sorted()
    }

    /// Round-trips through JSON, which is how `Prefs` stores it. Total: a
    /// corrupt or absent value reads as an empty log rather than throwing,
    /// because a review history is not worth failing a launch over.
    public static func decoded(from data: Data?) -> AutoReviewLog {
        guard let data, let log = try? JSONDecoder().decode(AutoReviewLog.self, from: data)
        else { return AutoReviewLog() }
        return log
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
