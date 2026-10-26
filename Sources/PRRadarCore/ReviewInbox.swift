import Foundation

/// Turns raw search payloads into the list of PRs still waiting on the viewer.
///
/// The rule, stated once:
///
///   latestPing  = newest review request aimed at me (directly or via a team I'm in)
///   myActivity  = newest review or comment I authored on that PR
///   show        = latestPing exists AND (no activity OR myActivity < latestPing)
///
/// Approve and Request-changes need no handling here: GitHub clears the review
/// request server-side, so those PRs simply stop coming back from the search.
/// A Comment-type review does *not* clear it, which is the whole reason this
/// rule exists. Anchoring to the *latest* ping also makes re-requests work —
/// a PR I already commented on resurfaces the moment someone pings me again.
///
/// `pins` is the one exception, and it is deliberately narrow: it names review
/// nodes that do not count as *me* having dealt with the PR, because PR Radar
/// posted them on my behalf. The rule above then runs completely unchanged —
/// which is the point. Suppressing by node id rather than by "anything before
/// this timestamp" keeps a clock out of it: a Mac running a second ahead of
/// GitHub would otherwise read our own review as activity newer than the pin
/// and drop the row the instant it was posted, which is the exact thing the
/// auto-review feature exists to prevent.
public struct ReviewInbox {
    public let viewerLogin: String
    public let teamSlugs: Set<String>
    public let includeDrafts: Bool
    /// Node ids of reviews PR Radar left for me, keyed by the ping they answer.
    /// Empty by default, so the pin is inert everywhere that does not opt in.
    public let pins: [String: String]
    /// When PR Radar last reviewed each pull request, by `repo#number`.
    /// Empty by default, which simply means no row says anything about a run.
    /// See `AutoReviewLog.lastRuns`.
    public let runs: [String: Date]

    public init(viewerLogin: String, teams: [TeamRef], includeDrafts: Bool = true,
                pins: [String: String] = [:], runs: [String: Date] = [:]) {
        self.viewerLogin = viewerLogin
        self.teamSlugs = Set(teams.map(\.slug))
        self.includeDrafts = includeDrafts
        self.pins = pins
        self.runs = runs
    }

    public func build(from searches: [String: SearchResult]) -> [ReviewItem] {
        // A PR can match both the direct search and a team search, so dedupe
        // on repo#number before applying the rule.
        var unique: [String: PRNode] = [:]
        for result in searches.values {
            for node in result.nodes {
                guard let repo = node.repository?.nameWithOwner, let number = node.number
                else { continue }
                unique["\(repo)#\(number)"] = node
            }
        }

        let items = unique.values.compactMap(item(from:))
        // Oldest ping first, so the most overdue review sits at the top.
        return items.sorted { $0.pingedAt < $1.pingedAt }
    }

    func item(from node: PRNode) -> ReviewItem? {
        guard let repo = node.repository?.nameWithOwner,
              let number = node.number,
              let title = node.title,
              let urlString = node.url,
              let url = URL(string: urlString),
              let author = node.author
        else { return nil }

        let isDraft = node.isDraft ?? false
        if isDraft && !includeDrafts { return nil }

        guard let latestPing = latestPing(in: node) else { return nil }
        let pinned = pins[ReviewItem.pingKey(repo: repo, number: number, pingedAt: latestPing)]
        if let activity = latestActivity(in: node, ignoring: pinned), activity >= latestPing {
            return nil
        }

        return ReviewItem(
            repo: repo,
            number: number,
            title: title,
            url: url,
            isDraft: isDraft,
            authorLogin: author.login,
            authorAvatarURL: author.avatarUrl.flatMap(URL.init(string:)),
            pingedAt: latestPing,
            nodeID: node.id,
            baseRef: node.baseRefName,
            signals: signals(from: node),
            sinceReview: sinceReview(in: node, ignoring: pinned),
            sinceRun: sinceRun(in: node, ranAt: runs["\(repo)#\(number)"]),
            summary: PRSummary.firstLine(of: node.body)
        )
    }

    /// What has landed since my last review of this pull request.
    ///
    /// nil when I have never reviewed it, which is the common case and the one
    /// where there is nothing to say. Every row this does appear on is a
    /// re-review by construction: the rule above only keeps a pull request
    /// whose newest ping is newer than anything I did to it, so a surviving
    /// row carrying a review of mine is one I have been asked to look at again.
    ///
    /// `ignoring` is the pin, and it is excluded here for a different reason
    /// than it is excluded above. There it stops PR Radar's own review from
    /// counting as me having dealt with the pull request; here it stops a
    /// review I did not read the code for from anchoring a diff labelled
    /// *since your review*. The review was posted under my name, but the
    /// sentence would not be true.
    func sinceReview(in node: PRNode, ignoring excluded: String? = nil) -> SinceReview? {
        let mine = (node.myReviews?.nodes ?? []).filter { review in
            review.author?.login == viewerLogin && review.id != excluded
        }
        guard let latest = mine.max(by: { ($0.createdAt ?? .distantPast)
                                          < ($1.createdAt ?? .distantPast) }),
              let reviewedAt = latest.createdAt
        else { return nil }

        let page = node.recent?.nodes.compactMap { $0.commit?.committedDate } ?? []
        return SinceReview.make(
            reviewedAt: reviewedAt,
            reviewedOid: latest.commit?.oid,
            headOid: node.head?.nodes.first?.commit?.oid,
            commitDates: page,
            total: node.recent?.totalCount ?? page.count)
    }

    /// What has landed since PR Radar last reviewed this pull request.
    ///
    /// nil when there has been no run to measure from. Counted off the same
    /// commit page `sinceReview` uses — the page is already in hand, so a
    /// second reader costs a filter and nothing else.
    func sinceRun(in node: PRNode, ranAt: Date?) -> SinceRun? {
        guard let ranAt else { return nil }
        let page = node.recent?.nodes.compactMap { $0.commit?.committedDate } ?? []
        return SinceRun.make(ranAt: ranAt,
                             commitDates: page,
                             total: node.recent?.totalCount ?? page.count)
    }

    /// What the row needs to triage this pull request, or nil when the payload
    /// did not carry it.
    ///
    /// nil rather than a zeroed struct. The three sizes arrive together or not
    /// at all, and a row saying `+0 −0 · 0f` about a pull request nobody
    /// measured is the same class of answer as a failed branch compare
    /// rendered as "up to date".
    func signals(from node: PRNode) -> ReviewSignals? {
        guard let additions = node.additions,
              let deletions = node.deletions,
              let changedFiles = node.changedFiles
        else { return nil }

        let rollup = node.head?.nodes.first?.commit?.statusCheckRollup?.state
        return ReviewSignals(
            additions: additions,
            deletions: deletions,
            changedFiles: changedFiles,
            checks: rollup.flatMap(RollupVerdict.init(rawValue:)),
            otherReviewers: otherReviewers(in: node),
            approvals: liveApprovals(in: node))
    }

    /// Reviewers still being waited on who are neither me nor a team of mine.
    ///
    /// Branching on `__typename` for the same reason `latestPing` does: a user
    /// whose login happens to match one of my team slugs is not my team, and
    /// counting them as me would make a ping aimed at six people look like one
    /// aimed at me alone.
    func otherReviewers(in node: PRNode) -> Int {
        (node.reviewRequests?.nodes ?? []).filter { request in
            guard let reviewer = request.requestedReviewer else { return false }
            switch reviewer.typename {
            case "User": return reviewer.login != viewerLogin
            case "Team": return !teamSlugs.contains(reviewer.slug ?? "")
            default: return false
            }
        }.count
    }

    /// Approvals that actually count, by the rule the lead chip already uses:
    /// a dismissed approval is not an approval, and a COMMENTED review is not
    /// an opinion. My own is excluded — a row saying somebody has approved
    /// this when the somebody is me would be the list answering itself.
    func liveApprovals(in node: PRNode) -> Int {
        (node.latestReviews?.nodes ?? []).filter { review in
            review.author?.login != viewerLogin && review.state == "APPROVED"
        }.count
    }

    /// Newest review request aimed at the viewer. `requestedReviewer` is a union,
    /// so this branches on `__typename` — a User whose login happens to match a
    /// team slug must not count as a team request.
    func latestPing(in node: PRNode) -> Date? {
        node.requests?.nodes.compactMap { event -> Date? in
            guard let createdAt = event.createdAt,
                  let reviewer = event.requestedReviewer
            else { return nil }
            switch reviewer.typename {
            case "User": return reviewer.login == viewerLogin ? createdAt : nil
            case "Team": return teamSlugs.contains(reviewer.slug ?? "") ? createdAt : nil
            default: return nil
            }
        }.max()
    }

    /// Newest review or issue comment the viewer authored, skipping one node.
    ///
    /// `ignoring` is how a pin works. It is a single node id rather than a set
    /// because there is only ever one PR Radar review per ping — a re-run
    /// supersedes its predecessor rather than adding to it.
    func latestActivity(in node: PRNode, ignoring excluded: String? = nil) -> Date? {
        let mine = { (conn: TimelineConn?) -> [Date] in
            conn?.nodes.compactMap { entry in
                guard entry.author?.login == self.viewerLogin else { return nil }
                if let excluded, entry.id == excluded { return nil }
                return entry.createdAt
            } ?? []
        }
        return (mine(node.myReviews) + mine(node.myComments)).max()
    }
}
