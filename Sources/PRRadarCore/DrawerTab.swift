import Foundation

/// The drawer's two views: what's waiting on me, and how my own work is doing.
public enum DrawerTab: String, CaseIterable, Sendable {
    case reviews
    case mine

    public var title: String {
        switch self {
        case .reviews: return "Reviews"
        case .mine: return "My PRs"
        }
    }

    public var symbol: String {
        switch self {
        case .reviews: return "tray.and.arrow.down"
        case .mine: return "arrow.triangle.pull"
        }
    }
}
