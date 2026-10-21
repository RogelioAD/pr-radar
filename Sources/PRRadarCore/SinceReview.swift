import Foundation

/// What has happened to a pull request since the last time you reviewed it.
///
/// A re-requested pull request is the most wasteful row in the queue: you
/// already read it, and the list hands it back with no indication of whether
/// twelve lines moved or the whole thing was rewritten. So you re-read nine
/// hundred lines to find the twelve.
///
/// Every row this appears on is a re-review by construction. The inbox rule
/// only keeps a pull request when the newest ping aimed at you is newer than
/// anything you did to it — so a row that carries a review of yours at all is
/// one somebody has asked you to look at again.
public struct SinceReview: Equatable, Sendable, Codable {
    /// When the review being measured from was submitted.
    public let reviewedAt: Date

    /// The commit that review was made against.
    ///
    /// Optional because GitHub's is: a review whose commit was force-pushed
    /// out of the branch comes back with none. The count below survives that —
    /// it is measured in dates — but the link does not, and a diff anchored to
    /// a commit that is no longer there is a 404 rather than an answer.
    public let reviewedOid: String?

    /// Where the branch is now.
    public let headOid: String?

    /// Commits pushed since the review. Counted locally from the commit page
    /// the row already fetches, against `reviewedAt`.
    public let commits: Int

    /// Whether `commits` filled the page it was counted from, so the real
    /// number is that or more. A saturated count says `20+` rather than
    /// quietly reporting the page size as though it were the total.
    public let isAtLeast: Bool

    public init(reviewedAt: Date, reviewedOid: String?, headOid: String?,
                commits: Int, isAtLeast: Bool) {
        self.reviewedAt = reviewedAt
        self.reviewedOid = reviewedOid
        self.headOid = headOid
        self.commits = commits
        self.isAtLeast = isAtLeast
    }

    /// Whether the branch has moved at all since the review.
    ///
    /// Asked of the commits where there are any and of the two oids otherwise.
    /// A force-push can rewrite committer dates so that nothing looks newer
    /// than the review while the head is plainly a different commit, and that
    /// is the case most worth not missing.
    public var hasMoved: Bool {
        if commits > 0 { return true }
        guard let reviewedOid, let headOid else { return false }
        return reviewedOid != headOid
    }

    /// What the chip says.
    ///
    /// "Nothing new" is said out loud rather than left as an absent chip. A
    /// re-request with no push behind it is a real thing that happens — the
    /// author wants a second look, or dismissed an approval — and knowing the
    /// diff is the one you already read is the most useful sentence available.
    public var label: String {
        guard hasMoved else { return "nothing new since your review" }
        guard commits > 0 else { return "head moved since your review" }
        let count = isAtLeast ? "\(commits)+" : "\(commits)"
        return "\(count) commit\(commits == 1 && !isAtLeast ? "" : "s") since your review"
    }

    public var health: Health { hasMoved ? .attention : .good }

    public var symbol: String { hasMoved ? "arrow.triangle.branch" : "equal.circle" }

    public func help(now: Date = Date()) -> String {
        let when = "You reviewed this \(TimeAgo.long(since: reviewedAt, now: now))"
        guard hasMoved else { return "\(when), and nothing has been pushed since" }
        guard incrementalDiff(of: URL(string: "https://example.com")) != nil else {
            return "\(when). GitHub no longer has the commit you reviewed, "
                 + "so the changes since cannot be linked"
        }
        return "\(when) — open just what has changed since"
    }

    /// GitHub's own two-commit view of this pull request, which shows the diff
    /// between the commit you reviewed and the head.
    ///
    /// Both oids or nothing. The range form silently falls back to the whole
    /// diff when an end of it is missing, which would hand back the nine
    /// hundred lines this exists to avoid while looking like it had worked.
    public func incrementalDiff(of pullRequest: URL?) -> URL? {
        guard let pullRequest,
              let reviewedOid, let headOid,
              reviewedOid != headOid
        else { return nil }
        return pullRequest
            .appendingPathComponent("files")
            .appendingPathComponent("\(reviewedOid)..\(headOid)")
    }

    /// Builds the record from a review timestamp and the commit page.
    ///
    /// `page` is the commits the query returned, newest last, and `total` is
    /// how many the pull request has — which is what decides whether a full
    /// page is a count or a floor.
    public static func make(reviewedAt: Date, reviewedOid: String?, headOid: String?,
                            commitDates page: [Date], total: Int) -> SinceReview {
        let newer = page.filter { $0 > reviewedAt }.count
        return SinceReview(reviewedAt: reviewedAt,
                           reviewedOid: reviewedOid,
                           headOid: headOid,
                           commits: newer,
                           isAtLeast: newer == page.count && total > page.count)
    }
}
