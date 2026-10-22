import Foundation

/// How much of your work one person is sitting on.
///
/// The waiting clock is per row, which is the right place for it and the wrong
/// place to notice the thing that matters: four of your six pull requests
/// waiting on the same reviewer is **one conversation, not four**, and nothing
/// on a list of rows ever says so. You read it four times and go on waiting.
///
/// Nothing is fetched for this. It is a group-by over the outstanding
/// reviewers the My PRs tab already has.
public struct ReviewerLoad: Equatable, Sendable, Identifiable {
    /// Login, or team slug for a team request.
    public let reviewer: String
    /// How many of your open pull requests are waiting on them.
    public let count: Int
    /// When the longest-outstanding of those was asked, if it is known.
    public let since: Date?

    public var id: String { reviewer }

    public init(reviewer: String, count: Int, since: Date?) {
        self.reviewer = reviewer
        self.count = count
        self.since = since
    }

    public var shortName: String { Leads.shortName(for: reviewer) }

    /// `alice has 4 of yours`.
    public var label: String {
        "\(shortName) has \(count) of yours"
    }

    public func ageLabel(now: Date = Date()) -> String? {
        since.map { "oldest \(TimeAgo.short(since: $0, now: now))" }
    }

    public func health(now: Date = Date()) -> Health {
        guard let since else { return .neutral }
        return Staleness.of(since, now: now).health
    }

    public func help(now: Date = Date()) -> String {
        let what = count == 1 ? "1 open pull request" : "\(count) open pull requests"
        guard let since else {
            return "\(shortName) is being waited on for \(what) of yours."
        }
        return "\(shortName) is being waited on for \(what) of yours. "
             + "The longest has been with them \(TimeAgo.long(since: since, now: now))."
    }

    // MARK: - Building

    /// The reviewers holding more than one of your pull requests, worst first.
    ///
    /// **More than one is the whole point.** A reviewer with exactly one of
    /// yours is already completely described by that row's own chip, and
    /// repeating it above the list would be the drawer saying the same thing
    /// twice in two sizes. This only speaks where the per-row view cannot.
    ///
    /// Sorted by how long they have had the oldest one rather than by how many
    /// they hold: two pull requests sat with somebody for a week is a worse
    /// state of affairs than four they were handed this morning. A reviewer
    /// whose ask times are unknown sorts last, for the reason an unmeasured
    /// row sorts last on the Reviews tab — not knowing is not a small number.
    public static func build(from items: [MyPullRequest],
                             minimum: Int = 2) -> [ReviewerLoad] {
        var counts: [String: Int] = [:]
        var oldest: [String: Date] = [:]

        for item in items {
            guard let awaiting = item.awaiting else { continue }
            for reviewer in awaiting.reviewers {
                counts[reviewer, default: 0] += 1
                // This reviewer's own ask on this pull request, not the row's
                // headline — the row reports whoever has had it longest, and
                // that is somebody else's clock.
                guard let asked = item.requestedAt[reviewer] else { continue }
                if let existing = oldest[reviewer], existing <= asked { continue }
                oldest[reviewer] = asked
            }
        }

        return counts
            .filter { $0.value >= minimum }
            .map { ReviewerLoad(reviewer: $0.key, count: $0.value,
                                since: oldest[$0.key]) }
            .sorted { left, right in
                switch (left.since, right.since) {
                case let (l?, r?):
                    return l == r ? left.reviewer < right.reviewer : l < r
                case (nil, nil): return left.reviewer < right.reviewer
                case (nil, _): return false
                case (_, nil): return true
                }
            }
    }
}
