import Foundation

/// A pull request that is currently waiting on the viewer's review.
public struct ReviewItem: Identifiable, Equatable, Sendable {
    public let repo: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let authorLogin: String
    public let authorAvatarURL: URL?
    /// Timestamp of the most recent review request aimed at the viewer (directly or via a team).
    public let pingedAt: Date

    public var id: String { "\(repo)#\(number)" }
    /// Short repo name without the owner prefix.
    public var repoShortName: String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }
    /// Key used to remember that we already notified about this particular ping.
    /// Includes the ping timestamp so a re-request notifies again.
    public var pingKey: String { "\(id)@\(ISO8601DateFormatter().string(from: pingedAt))" }

    public init(repo: String, number: Int, title: String, url: URL, isDraft: Bool,
                authorLogin: String, authorAvatarURL: URL?, pingedAt: Date) {
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.pingedAt = pingedAt
    }
}

/// How overdue a review request is.
public enum Staleness: Sendable {
    case fresh   // under a day
    case aging   // 1-3 days
    case stale   // over 3 days

    public static func of(_ pingedAt: Date, now: Date = Date()) -> Staleness {
        let age = now.timeIntervalSince(pingedAt)
        if age < 86_400 { return .fresh }
        if age < 3 * 86_400 { return .aging }
        return .stale
    }
}

/// The set of teams the viewer belongs to, as `org/slug` pairs.
public struct TeamRef: Hashable, Sendable {
    public let org: String
    public let slug: String
    public init(org: String, slug: String) {
        self.org = org
        self.slug = slug
    }
    public var qualified: String { "\(org)/\(slug)" }
}

/// Ordering for the drawer list.
public enum ReviewSortOrder: String, CaseIterable, Sendable {
    case oldestFirst
    case newestFirst
    case authorAZ

    public var label: String {
        switch self {
        case .oldestFirst: return "Oldest first"
        case .newestFirst: return "Newest first"
        case .authorAZ: return "Author A–Z"
        }
    }

    public var symbol: String {
        switch self {
        case .oldestFirst: return "arrow.down"
        case .newestFirst: return "arrow.up"
        case .authorAZ: return "textformat.abc"
        }
    }

    /// Applies this ordering. Oldest-first is the default because the most
    /// overdue review is the one worth seeing at the top.
    public func apply(to items: [ReviewItem]) -> [ReviewItem] {
        switch self {
        case .oldestFirst: return items.sorted { $0.pingedAt < $1.pingedAt }
        case .newestFirst: return items.sorted { $0.pingedAt > $1.pingedAt }
        case .authorAZ:
            return items.sorted {
                let left = $0.authorLogin.lowercased(), right = $1.authorLogin.lowercased()
                return left == right ? $0.pingedAt < $1.pingedAt : left < right
            }
        }
    }
}
