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
public struct ReviewInbox {
    public let viewerLogin: String
    public let teamSlugs: Set<String>
    public let includeDrafts: Bool

    public init(viewerLogin: String, teams: [TeamRef], includeDrafts: Bool = true) {
        self.viewerLogin = viewerLogin
        self.teamSlugs = Set(teams.map(\.slug))
        self.includeDrafts = includeDrafts
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
        if let activity = latestActivity(in: node), activity >= latestPing { return nil }

        return ReviewItem(
            repo: repo,
            number: number,
            title: title,
            url: url,
            isDraft: isDraft,
            authorLogin: author.login,
            authorAvatarURL: author.avatarUrl.flatMap(URL.init(string:)),
            pingedAt: latestPing
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

    /// Newest review or issue comment the viewer authored.
    func latestActivity(in node: PRNode) -> Date? {
        let mine = { (conn: TimelineConn?) -> [Date] in
            conn?.nodes.compactMap { entry in
                entry.author?.login == viewerLogin ? entry.createdAt : nil
            } ?? []
        }
        return (mine(node.myReviews) + mine(node.myComments)).max()
    }
}
