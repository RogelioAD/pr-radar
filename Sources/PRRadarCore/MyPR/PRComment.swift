import Foundation

/// Something somebody said on one of your own pull requests.
///
/// The My PRs row has always shown a *count* — `3 open` — which answers "is
/// there post" and not "has anything happened". A count that goes from two to
/// three while you are in another window is indistinguishable from one that has
/// been three all morning, so the thing worth interrupting for was the one
/// thing the app could not tell you.
///
/// Pared to what a notification needs: who, where, what, and a key that is the
/// same key on the next poll. Everything else a row already draws.
public struct PRComment: Equatable, Sendable, Identifiable {

    /// What kind of thing was said, which decides how the banner reads.
    ///
    /// A review submission is not a comment and must not be announced as one:
    /// "someone commented" over an approval buries the verdict, and the verdict
    /// is the whole message.
    public enum Kind: Equatable, Sendable {
        /// A comment on a line of code, in an unresolved thread.
        case thread
        /// A review verdict — approved, changes requested, or a plain comment
        /// review with no inline threads of its own.
        case review(ReviewState)
    }

    /// Stable across polls, which is the whole job. A thread comment uses
    /// GitHub's node id. A review submission has none fetched, so it is keyed
    /// by who submitted it and when — a second review by the same person at the
    /// same instant does not happen, and if it did, announcing it once is the
    /// harmless way to be wrong.
    public let id: String
    public let repo: String
    public let number: Int
    public let title: String
    public let url: URL
    public let author: String
    public let body: String
    public let kind: Kind
    public let createdAt: Date?

    /// Whether a machine said it.
    ///
    /// By the login's shape rather than a list of names, because the list is
    /// unbounded and grows per repository: this repo's Claude reviewer, Codex
    /// reviewer and golden-diff bot all post as `github-actions[bot]`, and a
    /// hardcoded roster would miss the fourth one.
    public var isBot: Bool { PRComment.isBotLogin(author) }

    public static func isBotLogin(_ login: String) -> Bool {
        login.hasSuffix("[bot]") || login == "github-actions"
    }

    public init(id: String, repo: String, number: Int, title: String, url: URL,
                author: String, body: String, kind: Kind, createdAt: Date? = nil) {
        self.id = id
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.author = author
        self.body = body
        self.kind = kind
        self.createdAt = createdAt
    }

    /// How the banner's title reads.
    public var headline: String {
        switch kind {
        case .thread: return "\(author) commented on #\(number)"
        case .review(.approved): return "\(author) approved #\(number)"
        case .review(.changesRequested): return "\(author) requested changes on #\(number)"
        case .review(.dismissed): return "A review on #\(number) was dismissed"
        case .review: return "\(author) reviewed #\(number)"
        }
    }

    // MARK: - Harvesting

    /// Everything said on these pull requests, newest last.
    ///
    /// Reads what the poll has already fetched rather than asking for more:
    /// the thread comments are on the row for the disclosure, and the review
    /// states are there for the approval chips. Nothing here costs a request.
    ///
    /// **Only threads that are still unresolved are walked**, because those are
    /// the only ones fetched. A comment on a thread somebody resolved between
    /// two polls is therefore never announced — which is the right way round:
    /// it has already been dealt with.
    ///
    /// A comment with no id is dropped rather than keyed on its text. A key
    /// made of a body that somebody later edits is a new key, and a new key is
    /// a second notification for a sentence that was only said once.
    public static func harvest(from pullRequests: [MyPullRequest],
                               includingBots: Bool = true) -> [PRComment] {
        var found: [PRComment] = []

        for pr in pullRequests {
            for thread in pr.unresolvedThreads {
                for comment in thread.comments {
                    guard let id = comment.id else { continue }
                    guard includingBots || !isBotLogin(comment.author) else { continue }
                    found.append(PRComment(
                        id: id, repo: pr.repo, number: pr.number, title: pr.title,
                        url: pr.url, author: comment.author, body: comment.body,
                        kind: .thread, createdAt: comment.createdAt))
                }
            }

            for approval in pr.approvals {
                guard includingBots || !isBotLogin(approval.login) else { continue }
                guard let submittedAt = approval.submittedAt else { continue }
                found.append(PRComment(
                    id: reviewKey(repo: pr.repo, number: pr.number,
                                  login: approval.login, at: submittedAt),
                    repo: pr.repo, number: pr.number, title: pr.title, url: pr.url,
                    author: approval.login, body: approval.state.spoken,
                    kind: .review(approval.state), createdAt: submittedAt))
            }
        }

        // Oldest first, so a burst reads in the order it happened and the one
        // the banner names is the latest thing anybody said.
        return found.sorted {
            ($0.createdAt ?? .distantPast, $0.id) < ($1.createdAt ?? .distantPast, $1.id)
        }
    }

    /// The key for a review submission. Pinned to a fixed ISO-8601 format for
    /// the reason `ReviewItem.pingKey` pins its own: the key is persisted, and
    /// a key whose spelling changes under an SDK update is every past review
    /// announcing itself again.
    public static func reviewKey(repo: String, number: Int,
                                 login: String, at date: Date) -> String {
        "\(repo)#\(number):review:\(login)@\(iso8601.string(from: date))"
    }

    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension ReviewState {
    /// The verdict in words, for a banner that has no room for a chip.
    public var spoken: String {
        switch self {
        case .approved: return "Approved"
        case .changesRequested: return "Changes requested"
        case .commented: return "Left a review"
        case .dismissed: return "Review dismissed"
        case .pending: return "Review in progress"
        }
    }
}
