import SwiftUI
import PRRadarCore

@MainActor
final class AppState: ObservableObject {

    // MARK: - Reviews tab

    /// Everything waiting on the viewer, unfiltered. The badge counts these.
    @Published var items: [ReviewItem] = []
    @Published var sortOrder: ReviewSortOrder = Prefs.sortOrder {
        didSet { Prefs.sortOrder = sortOrder }
    }
    /// nil means every author.
    @Published var authorFilter: String?

    // MARK: - My PRs tab

    @Published var myPRs: [MyPullRequest] = []
    @Published var myPRSortOrder: MyPRSortOrder = Prefs.myPRSortOrder {
        didSet { Prefs.myPRSortOrder = myPRSortOrder }
    }
    @Published var myPRFilter: MyPRFilter = Prefs.myPRFilter {
        didSet { Prefs.myPRFilter = myPRFilter }
    }
    // MARK: - Shared

    @Published var selectedTab: DrawerTab = Prefs.selectedTab {
        didSet { Prefs.selectedTab = selectedTab }
    }
    @Published var expanded = false
    @Published var authError: String?
    @Published var lastError: String?
    @Published var isRefreshing = false
    @Published var lastUpdated: Date?
    /// Ticks so relative timestamps re-render without a network round trip.
    @Published var clock = Date()

    /// Measured height of each row, keyed by a tab-namespaced row id.
    @Published var rowHeights: [String: CGFloat] = [:]
    /// Row-list height the user dragged to, per tab: My PR rows are far taller
    /// than review rows, so a single shared height would fight itself.
    @Published var userContentHeights: [DrawerTab: CGFloat] = AppState.loadHeights()

    static func loadHeights() -> [DrawerTab: CGFloat] {
        var result: [DrawerTab: CGFloat] = [:]
        for tab in DrawerTab.allCases {
            if let height = Prefs.drawerContentHeight(for: tab) { result[tab] = height }
        }
        return result
    }

    // MARK: - Displayed lists

    var displayedItems: [ReviewItem] {
        let filtered = authorFilter.map { author in
            items.filter { $0.authorLogin == author }
        } ?? items
        return sortOrder.apply(to: filtered)
    }

    var displayedMyPRs: [MyPullRequest] {
        myPRSortOrder.apply(to: myPRFilter.apply(to: myPRs))
    }

    var authors: [String] {
        Array(Set(items.map(\.authorLogin))).sorted { $0.lowercased() < $1.lowercased() }
    }

    var isFiltered: Bool { authorFilter != nil }
    var isMyPRFiltered: Bool { myPRFilter != .all }

    // MARK: - Active-tab geometry

    /// Row ids are namespaced by tab so the two lists cannot collide.
    func rowKey(_ tab: DrawerTab, _ id: String) -> String { "\(tab.rawValue):\(id)" }

    var activeRowCount: Int {
        switch selectedTab {
        case .reviews: return displayedItems.count
        case .mine: return displayedMyPRs.count
        }
    }

    /// Measured heights of the active tab's rows, in display order.
    var activeRowHeights: [CGFloat] {
        switch selectedTab {
        case .reviews:
            return displayedItems.compactMap { rowHeights[rowKey(.reviews, $0.id)] }
        case .mine:
            return displayedMyPRs.compactMap { rowHeights[rowKey(.mine, $0.id)] }
        }
    }

    var userContentHeight: CGFloat? {
        get { userContentHeights[selectedTab] }
        set {
            if let newValue {
                userContentHeights[selectedTab] = newValue
            } else {
                userContentHeights.removeValue(forKey: selectedTab)
            }
        }
    }

    /// Only expandable when rows are actually hidden. Showing a grab handle
    /// that cannot do anything is worse than showing none.
    var canResizeDrawer: Bool { activeRowCount > Layout.defaultVisibleRows }

    // MARK: - Badge

    /// The badge counts review requests only — the number you owe other people.
    /// Your own PRs are informational and must not inflate it.
    var count: Int { items.count }

    /// Lights the badge's secondary dot: PRs of mine that are ready to merge.
    var myPRsReadyToMerge: Int { myPRs.filter(\.isReadyToMerge).count }

    /// The badge reflects the most overdue request across everything waiting,
    /// independent of whatever filter the drawer is showing.
    var worstStaleness: Staleness {
        guard let oldest = items.map(\.pingedAt).min() else { return .fresh }
        return Staleness.of(oldest, now: clock)
    }

    var hasProblem: Bool { authError != nil }

    /// Hidden only when *both* tabs are empty. Keying this on review requests
    /// alone would make My PRs unreachable exactly when the review queue is
    /// clear, which is when you most want to look at your own work.
    var shouldHidePanel: Bool {
        items.isEmpty && myPRs.isEmpty && !hasProblem
    }
}

extension Staleness {
    var tint: Color { health.tint }

    var health: Health {
        switch self {
        case .fresh: return .running    // blue: nothing wrong, just waiting
        case .aging: return .attention
        case .stale: return .bad
        }
    }
}

extension Health {
    /// The single place colour is assigned, so checks, blockers, approvals and
    /// staleness cannot drift apart.
    var tint: Color {
        switch self {
        case .good: return Color(red: 0.20, green: 0.70, blue: 0.38)
        case .running: return Color(red: 0.29, green: 0.56, blue: 0.95)
        case .attention: return Color(red: 0.95, green: 0.62, blue: 0.18)
        case .bad: return Color(red: 0.88, green: 0.16, blue: 0.13)
        case .neutral: return Color(white: 0.55)
        }
    }
}
