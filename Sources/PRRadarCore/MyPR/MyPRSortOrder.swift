import Foundation

/// Ordering for the My PRs list.
public enum MyPRSortOrder: String, CaseIterable, Sendable {
    case newestFirst
    case oldestFirst
    case recentlyUpdated
    case needsAttention

    public var label: String {
        switch self {
        case .newestFirst: return "Newest first"
        case .oldestFirst: return "Oldest first"
        case .recentlyUpdated: return "Recently updated"
        case .needsAttention: return "Needs attention"
        }
    }

    public var symbol: String {
        switch self {
        case .newestFirst: return "arrow.up"
        case .oldestFirst: return "arrow.down"
        case .recentlyUpdated: return "clock"
        case .needsAttention: return "exclamationmark.triangle"
        }
    }

    public func apply(to items: [MyPullRequest]) -> [MyPullRequest] {
        switch self {
        case .newestFirst:
            return items.sorted { $0.createdAt > $1.createdAt }
        case .oldestFirst:
            return items.sorted { $0.createdAt < $1.createdAt }
        case .recentlyUpdated:
            return items.sorted { $0.updatedAt > $1.updatedAt }
        case .needsAttention:
            // Worst health first; ties broken by oldest, since an old broken PR
            // is more urgent than a fresh one.
            return items.sorted {
                $0.health.severity == $1.health.severity
                    ? $0.createdAt < $1.createdAt
                    : $0.health.severity > $1.health.severity
            }
        }
    }
}

/// Narrows the My PRs list to a single concern.
public enum MyPRFilter: String, CaseIterable, Sendable {
    case all
    case needsLead
    case changesRequested
    case failingChecks
    case openThreads
    case readyToMerge

    public var label: String {
        switch self {
        case .all: return "All"
        case .needsLead: return "Needs lead"
        case .changesRequested: return "Changes requested"
        case .failingChecks: return "Failing checks"
        case .openThreads: return "Open threads"
        case .readyToMerge: return "Ready to merge"
        }
    }

    public func matches(_ item: MyPullRequest) -> Bool {
        switch self {
        case .all: return true
        case .needsLead: return item.needsLead
        case .changesRequested: return item.reviewDecision == .changesRequested
        case .failingChecks: return item.checks.failing > 0
        case .openThreads: return item.unresolvedThreadCount > 0
        case .readyToMerge: return item.mergeBlocker == .clean
        }
    }

    public func apply(to items: [MyPullRequest]) -> [MyPullRequest] {
        self == .all ? items : items.filter(matches)
    }
}
