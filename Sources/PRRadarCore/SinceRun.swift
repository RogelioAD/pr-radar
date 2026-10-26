import Foundation

/// What has landed since PR Radar last reviewed this pull request.
///
/// The sibling of `SinceReview`, asking the same question about the other
/// reader. The findings on the strip below are a verdict on one commit, and
/// nothing on the row said which — so a review run on Monday and five pushes
/// later it still read as the current word on the code. This is how far behind
/// it has fallen.
///
/// No oids, unlike `SinceReview`: a run is not a review GitHub knows about, so
/// there is no commit recorded against it and no two-commit diff to link. The
/// count is the whole of it, which also means a force-push that rewrites
/// committer dates reads here as nothing new. That is the one case this cannot
/// see, and it is the price of not storing a sha per run.
public struct SinceRun: Equatable, Sendable, Codable {
    /// When that run finished.
    public let ranAt: Date

    /// Commits pushed since. Counted locally from the commit page the row
    /// already fetches, against `ranAt`, exactly as `SinceReview` counts.
    public let commits: Int

    /// Whether `commits` filled the page it was counted from, so the real
    /// number is that or more. See `SinceReview.isAtLeast`.
    public let isAtLeast: Bool

    public init(ranAt: Date, commits: Int, isAtLeast: Bool) {
        self.ranAt = ranAt
        self.commits = commits
        self.isAtLeast = isAtLeast
    }

    /// Whether the branch has moved since the run, as far as the dates can say.
    public var hasMoved: Bool { commits > 0 }

    /// What the chip says.
    ///
    /// It is never drawn without a count, so there is no "nothing new" wording
    /// here and `SinceReview` keeps its own. The two are not symmetrical on
    /// purpose: a re-review is rare and worth a sentence either way, while
    /// nearly every row in this queue carries a run — a chip on all of them
    /// saying the review is still current would be a chip nobody reads.
    public var label: String {
        let count = isAtLeast ? "\(commits)+" : "\(commits)"
        return "\(count) commit\(commits == 1 && !isAtLeast ? "" : "s") since PR Radar's review"
    }

    /// Attention, because it is the same warning `SinceReview` gives in the
    /// chip beside it: what you are about to read is a verdict on older code.
    public var health: Health { .attention }

    public var symbol: String { "arrow.triangle.branch" }

    public func help(now: Date = Date()) -> String {
        "PR Radar reviewed this \(TimeAgo.long(since: ranAt, now: now)) — "
            + "its findings are about the code as it stood then"
    }

    /// Builds the record from a run timestamp and the commit page.
    ///
    /// `page` is the commits the query returned and `total` is how many the
    /// pull request has, which is what decides whether a full page is a count
    /// or a floor. Both are the same inputs `SinceReview.make` takes, because
    /// both are answering the same question from the same payload.
    public static func make(ranAt: Date, commitDates page: [Date], total: Int) -> SinceRun {
        let newer = page.filter { $0 > ranAt }.count
        return SinceRun(ranAt: ranAt,
                        commits: newer,
                        isAtLeast: newer == page.count && total > page.count)
    }
}
