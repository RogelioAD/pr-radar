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

    public init(viewerLogin: String, teams: [TeamRef], includeDrafts: Bool = true,
                pins: [String: String] = [:]) {
        self.viewerLogin = viewerLogin
        self.teamSlugs = Set(teams.map(\.slug))
        self.includeDrafts = includeDrafts
        self.pins = pins
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
            baseRef: node.baseRefName
        )
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
