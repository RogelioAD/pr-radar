import Foundation

/// A pull request that is currently waiting on the viewer's review.
/// Codable because a posted review has to be able to redraw its own row.
/// GitHub drops the viewer from `requested_reviewers` the moment any review is
/// submitted — a COMMENT one included — so the search stops returning the PR
/// and the row would vanish with the decision still outstanding. The record
/// keeps a copy to draw from. See `AutoReviewRecord.subject`.
public struct ReviewItem: Identifiable, Equatable, Sendable, Codable {
    public let repo: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let authorLogin: String
    public let authorAvatarURL: URL?
    /// Timestamp of the most recent review request aimed at the viewer (directly or via a team).
    public let pingedAt: Date

    /// Which account surfaced this row. Empty until a fetch tags it, and set
    /// after the inbox builds rather than threaded through it — the same
    /// post-build shape `behindBy` already uses, and it keeps every existing
    /// construction site and test compiling unchanged.
    public var account: String = ""

    /// The pull request's GraphQL node id, which every mutation needs as its
    /// subject. Optional, and defaulted, for the same reason `account` is: a
    /// required parameter here would break every existing construction site and
    /// test. nil means "this row cannot be acted on", which the UI says out loud
    /// rather than hiding the buttons.
    public var nodeID: String?

    /// The branch this pull request is into.
    ///
    /// Optional and defaulted like the two above, and for the same reason. nil
    /// means "not known", which the review falls back from rather than guessing
    /// at — guessing is what produced a diff of five hundred files for a pull
    /// request that touched thirty-nine.
    public var baseRef: String?

    /// What this review will cost and whether it is worth starting — size,
    /// the checks rollup, who else is on the hook. See `ReviewSignals`.
    ///
    /// Optional for the same reason as the three above, and one more: a row
    /// redrawn from a persisted auto-review record was encoded before this
    /// existed, so nil is the state a year-old record decodes into. A row with
    /// no signals simply wears no triage chips.
    public var signals: ReviewSignals?

    /// What has landed since the last time you reviewed this, when you have.
    ///
    /// nil on a pull request you have never reviewed, which is most of them,
    /// and optional for the same persistence reason as everything above it.
    /// See `SinceReview`.
    public var sinceReview: SinceReview?

    /// What has landed since PR Radar last reviewed this, when it has.
    ///
    /// nil where there has been no run to measure from, and optional for the
    /// same persistence reason as everything above it. See `SinceRun`.
    public var sinceRun: SinceRun?

    /// The one line of the description worth showing. See `PRSummary`.
    public var summary: String?

    public var id: String { "\(repo)#\(number)" }
    /// Short repo name without the owner prefix.
    public var repoShortName: String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }
    /// Key used to remember that we already notified about this particular ping.
    /// Includes the ping timestamp so a re-request notifies again.
    public var pingKey: String {
        ReviewItem.pingKey(repo: repo, number: number, pingedAt: pingedAt)
    }

    /// The same key, before there is an item to ask for it.
    ///
    /// `ReviewInbox` has to look a ping up in the auto-review log at the point
    /// it is deciding whether to build the item at all, so the key cannot be a
    /// property of the thing it decides the existence of.
    public static func pingKey(repo: String, number: Int, pingedAt: Date) -> String {
        "\(repo)#\(number)@\(iso8601.string(from: pingedAt))"
    }

    /// One formatter, because two of them are a way for a key written in one
    /// place to stop matching one read in another. The options are spelled out
    /// rather than left default so a future SDK cannot quietly change the shape
    /// of every key already persisted.
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    public init(repo: String, number: Int, title: String, url: URL, isDraft: Bool,
                authorLogin: String, authorAvatarURL: URL?, pingedAt: Date,
                account: String = "", nodeID: String? = nil, baseRef: String? = nil,
                signals: ReviewSignals? = nil, sinceReview: SinceReview? = nil,
                sinceRun: SinceRun? = nil, summary: String? = nil) {
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.authorLogin = authorLogin
        self.authorAvatarURL = authorAvatarURL
        self.pingedAt = pingedAt
        self.account = account
        self.nodeID = nodeID
        self.baseRef = baseRef
        self.signals = signals
        self.sinceReview = sinceReview
        self.sinceRun = sinceRun
        self.summary = summary
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
    case smallestFirst

    public var label: String {
        switch self {
        case .oldestFirst: return "Oldest first"
        case .newestFirst: return "Newest first"
        case .authorAZ: return "Author A–Z"
        case .smallestFirst: return "Smallest first"
        }
    }

    public var symbol: String {
        switch self {
        case .oldestFirst: return "arrow.down"
        case .newestFirst: return "arrow.up"
        case .authorAZ: return "textformat.abc"
        case .smallestFirst: return "ruler"
        }
    }

    /// Applies this ordering. Oldest-first is the default because the most
    /// overdue review is the one worth seeing at the top.
    ///
    /// Smallest-first is how a queue of six actually gets cleared, and it is
    /// the one ordering with an unknown in it: an item whose signals never
    /// arrived has no size, and sorting it as zero would put it at the very
    /// top claiming to be the quickest thing in the list. Unknowns go last,
    /// among themselves oldest first, which is where the default would have
    /// had them anyway.
    public func apply(to items: [ReviewItem]) -> [ReviewItem] {
        switch self {
        case .oldestFirst: return items.sorted { $0.pingedAt < $1.pingedAt }
        case .newestFirst: return items.sorted { $0.pingedAt > $1.pingedAt }
        case .authorAZ:
            return items.sorted {
                let left = $0.authorLogin.lowercased(), right = $1.authorLogin.lowercased()
                return left == right ? $0.pingedAt < $1.pingedAt : left < right
            }
        case .smallestFirst:
            return items.sorted {
                switch ($0.signals?.lines, $1.signals?.lines) {
                case let (left?, right?):
                    return left == right ? $0.pingedAt < $1.pingedAt : left < right
                case (nil, nil): return $0.pingedAt < $1.pingedAt
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        }
    }
}
