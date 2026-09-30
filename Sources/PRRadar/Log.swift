import AppKit
import OSLog
import PRRadarCore

/// Debug tracing. Always recorded through unified logging, and additionally
/// echoed to stderr when PRRADAR_DEBUG=1.
///
/// The stderr half only reaches anyone running the binary from a terminal,
/// which an app started by a LaunchAgent never is — diagnosing it meant
/// rewriting the agent to capture a file. The unified log is readable after the
/// fact in Console.app, filtered on this subsystem, with no such surgery:
///
///     log stream --predicate 'subsystem == "com.rogelioacosta.prradar"'
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["PRRADAR_DEBUG"] == "1"

    private static let logger = Logger(subsystem: "com.rogelioacosta.prradar",
                                       category: "app")

    /// PRRADAR_EXPAND=1 opens the drawer on launch — lets the expanded state be
    /// inspected without a click.
    static let startExpanded = ProcessInfo.processInfo.environment["PRRADAR_EXPAND"] == "1"

    /// PRRADAR_APPEARANCE=light|dark forces the app's appearance, so the
    /// opposite colour scheme can be inspected without switching the system.
    static var forcedAppearance: NSAppearance? {
        switch ProcessInfo.processInfo.environment["PRRADAR_APPEARANCE"]?.lowercased() {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    /// PRRADAR_FAKE_DATE=YYYY-MM-DD stands the app up as though it were that
    /// day, for the seasonal cast and the banner that announces it.
    ///
    /// Same reason as the fakes below it, and more sharply: the one state this
    /// feature exists to produce happens on 31 days of the year, and the other
    /// 334 there is no way to look at it at all. Waiting for October to find
    /// out whether the banner clips is not a test strategy.
    ///
    /// Read once. A date that moved while the app was running would re-lay the
    /// drawer out underneath whoever was reading it.
    static let fakeDate: Date? = {
        guard let raw = ProcessInfo.processInfo.environment["PRRADAR_FAKE_DATE"] else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }()

    /// PRRADAR_FAKE_BEHIND=N forces every one of my PRs to look N commits
    /// behind, so the branch-state chip can be inspected. Both real PRs are
    /// level with their bases, so there is otherwise no way to see it.
    static var fakeBehind: Int? {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_BEHIND"].flatMap(Int.init)
    }

    /// PRRADAR_FAIL_ACCOUNT=login forces that account's fetch to fail, so the
    /// short-round badge and the strip's mark can be inspected. Every account
    /// on a working machine is healthy, which otherwise leaves the one state
    /// this feature exists for as the one state nobody has ever seen. Same
    /// reason the two fakes below exist.
    ///
    /// PRRADAR_FAIL_ACCOUNT=mine fails only the My PRs half, which is the
    /// quieter case: the account answers, and still returns half a round.
    static var failAccount: String? {
        ProcessInfo.processInfo.environment["PRRADAR_FAIL_ACCOUNT"]
    }

    /// PRRADAR_FAKE_ACCOUNTS=n stands the drawer up as though `gh` were logged
    /// in to n accounts, by repeating the real one under invented logins.
    ///
    /// The whole point of this feature is what happens above one account, and
    /// that is the one thing a machine with a single login cannot show — the
    /// strip does not appear, the merge never dedupes, and the scope has
    /// nothing to scope to. `PRRADAR_FAIL_ACCOUNT` exists for the same reason
    /// and covers the other half.
    ///
    /// The copies carry the real account's token, so every one of them returns
    /// the *same* rows. That is not a limitation of the fake, it is the case
    /// worth seeing: two identities that both belong to a reviewing team really
    /// do surface one pull request twice, and `AccountMerge` giving it to the
    /// first account is the behaviour the strip's counts have to reflect.
    static var fakeAccounts: Int? {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_ACCOUNTS"]
            .flatMap(Int.init)
            .map { min(max($0, 1), 6) }
    }

    /// PRRADAR_FAKE_REVIEW=running|ready|posted|failed|skipped stands an
    /// automatic-review record up on every review row.
    ///
    /// Same reason as the fakes around it, only more so: the one state this
    /// feature exists to produce — a row that has been reviewed and is waiting
    /// on a decision — is otherwise reachable only by spending real money on
    /// somebody's real pull request and then living with the comment.
    static var fakeReview: AutoReviewRecord? {
        guard let raw = ProcessInfo.processInfo.environment["PRRADAR_FAKE_REVIEW"],
              let status = AutoReviewStatus(rawValue: raw)
        else { return nil }
        var record = AutoReviewRecord(status: status)
        record.counts = ["priority": 2, "mild": 5, "nit": 4]
        record.reviewNodeID = "PRR_fake"
        record.reviewURLString = "https://github.com"
        record.finishedAt = Date()
        // A stopwatch with nothing on it cannot be looked at. A running review
        // starts from zero and climbs; a finished one carries a plausible run.
        if status == .running {
            record.startedAt = Date()
        } else {
            record.startedAt = Date().addingTimeInterval(-531)
            record.runSeconds = 531
        }
        // Two findings, one of which has nowhere to hang. The mix is the whole
        // point: a review where every finding anchors looks fine however the
        // summary is worded, and the row that says "summary only" is the one
        // nobody can conjure on demand — it needs a real pull request whose
        // diff happens not to contain a line the model wanted to talk about.
        if status == .ready || status == .posted {
            record.prepared = [
                PreparedFinding(
                    finding: Finding(tier: .mild, file: "Sources/Deep/Link.swift",
                                     line: 351, endLine: nil,
                                     summary: "The guard sits under the wrong comment.",
                                     detail: nil, recommendation: "Move it below.",
                                     suggestion: nil),
                    anchor: ReviewThread(path: "Sources/Deep/Link.swift", line: 351,
                                         startLine: nil, body: "…"),
                    isSelected: true,
                    // The other half of the same argument: the code under a
                    // finding cannot be conjured either. It is sliced from the
                    // worktree the review ran in, which is deleted when the run
                    // ends, so every row that already exists has none — and a
                    // view nobody can open is a view nobody can look at.
                    excerpt: DiffExcerpt(
                        path: "Sources/Deep/Link.swift",
                        lines: [
                            DiffLine(kind: .context, number: 349,
                                     text: "    let mut parts = path.split('/')"),
                            DiffLine(kind: .context, number: 350,
                                     text: "    let seg = parts.next()?"),
                            DiffLine(kind: .removed, number: nil,
                                     text: "    if seg.isEmpty { return nil }"),
                            DiffLine(kind: .added, number: 351,
                                     text: "    if reservedWebSegments.contains(seg) { return nil }"),
                            DiffLine(kind: .added, number: 352,
                                     text: "    if seg.isEmpty { return nil }"),
                            DiffLine(kind: .context, number: 353,
                                     text: "    return Route(fromSlug: seg)"),
                        ],
                        focus: 351)),
                PreparedFinding(
                    finding: Finding(tier: .mild, file: "docs/specs/home-view.md",
                                     line: 102, endLine: nil,
                                     summary: "The spec still documents the apex URL.",
                                     detail: nil, recommendation: "Update it.",
                                     suggestion: nil),
                    anchor: nil,
                    isSelected: true),
            ]
        }
        switch status {
        case .failed: record.failure = "unknown skill: /nope"
        case .skipped: record.failure = AutoReviewSkip.repoNotAllowed.reason
        default: break
        }
        return record
    }

    /// PRRADAR_FAKE_UPDATE=<version> stands the app up as though that release
    /// were published — the dot on the gear, the tooltip naming the version,
    /// and the Get button in Settings.
    ///
    /// The same reason as the banner fake, and the comment on the gear's dot
    /// says it outright: a release is announced a few days a year. Waiting for
    /// a real one in order to look at how the announcement reads is not a plan,
    /// and publishing one in order to see it is worse.
    ///
    /// The URL is built from whichever repository the update check is actually
    /// watching, so a fork looking at this sees its own releases page rather
    /// than somebody else's.
    static var fakeUpdate: UpdateStatus? {
        guard let raw = ProcessInfo.processInfo.environment["PRRADAR_FAKE_UPDATE"],
              let version = AppVersion(raw),
              let url = URL(string: "https://github.com/\(Prefs.updateRepo)/releases")
        else { return nil }
        return .available(version: version, url: url)
    }

    /// PRRADAR_FAKE_QUEUE=1 puts every review row in the waiting queue, so the
    /// "next for review" and "queued for review" chips can be looked at.
    ///
    /// One review runs at a time, so seeing these honestly means two eligible
    /// pull requests arriving at once and catching the ten minutes while the
    /// first is still going — which is not something to sit and wait for.
    static var fakeQueue: Bool {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_QUEUE"] == "1"
    }

    /// PRRADAR_FAKE_READY=1 forces every one of my PRs to look mergeable, so
    /// the badge's green dot can be inspected. Both real PRs are BLOCKED on
    /// reviews, so there is otherwise no way to see it.
    static var fakeReady: Bool {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_READY"] == "1"
    }

    /// PRRADAR_FAKE_STACKS=1 cuts the longest stack in half, so the list shows
    /// two groups instead of one. How several groups sit together — their
    /// outlines, their spacing, the drawer's height across them — cannot be
    /// looked at with a single stack in the data, and a second real one is not
    /// something you can conjure on demand.
    static var fakeStacks: Bool {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_STACKS"] == "1"
    }

    /// PRRADAR_FAKE_BANNER=<id>[,<id>…] drops those trophies' banners on the
    /// first refresh.
    ///
    /// Earning one is the thing you cannot arrange: the banner is the payoff
    /// for a queue emptying or a hundredth merge, and neither is available on
    /// a Tuesday afternoon. Named rather than a bare flag because the banner
    /// is now sized around whatever it is drawing — a one-word title beside a
    /// 32-cell trophy is a different shape from a two-word one — so seeing
    /// *a* banner is not the same as seeing the banner.
    ///
    /// `1` is the old spelling and still means the original: inbox zero.
    /// `many` fires enough at once to trip the summary.
    static var fakeBanner: [String] {
        guard let raw = ProcessInfo.processInfo.environment["PRRADAR_FAKE_BANNER"],
              !raw.isEmpty
        else { return [] }
        if raw == "1" { return ["inboxZero"] }
        return raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// PRRADAR_FAKE_TROPHIES=all|none forces the shelf to one of its two ends.
    ///
    /// Both ends are hard to reach honestly and both are worth looking at.
    /// `all` is the finished set — thirty drawings only work as a set if they
    /// can be seen as one, and earning them to find out whether two of the
    /// greens fight is not a workflow. `none` is what a stranger sees, which
    /// is otherwise visible for about four seconds on one machine ever: the
    /// silent backfill fills the shelf on the very first refresh.
    ///
    /// `none` also suppresses evaluation, or the backfill would undo it
    /// between the window opening and anybody looking at it.
    ///
    /// In memory only: neither ever writes, so quitting puts the real shelf
    /// back. `1` is the old spelling of `all`.
    /// `empty` rather than `none`, which as a case on an enum used through
    /// an `Optional` is the same spelling as "no value" and reads as either.
    enum Shelf: String {
        case all, empty
    }

    static var fakeShelf: Shelf? {
        switch ProcessInfo.processInfo.environment["PRRADAR_FAKE_TROPHIES"] {
        case "1", "all": return .all
        case "none", "empty": return .empty
        default: return nil
        }
    }

    static func debug(_ message: @autoclosure () -> String) {
        let text = message()
        // Notice rather than debug: debug-level records live in memory and are
        // gone before anyone thinks to look, which is precisely the situation
        // this exists for. Notice is persisted and readable after the fact.
        //
        // Public: this is a developer tool logging its own state, and redacted
        // placeholders would make the log useless for the thing it exists for.
        logger.notice("\(text, privacy: .public)")
        guard enabled else { return }
        FileHandle.standardError.write(Data("[prradar] \(text)\n".utf8))
    }
}
