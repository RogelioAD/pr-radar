import SwiftUI
import PRRadarCore

/// One stable view type for the hosting view, switching between the two states,
/// so the panel's content view never has to be swapped out.
struct RootView: View {
    @ObservedObject var state: AppState
    let onOpen: (ReviewItem) -> Void
    let onOpenMyPR: (MyPullRequest) -> Void
    let onCollapse: () -> Void
    let onRefresh: () -> Void
    let onRowHeights: ([String: CGFloat]) -> Void
    let onSelectTab: (DrawerTab) -> Void
    let onToggleRoom: (DrawerRoom) -> Void
    let onResetBadgeSize: () -> Void
    let onHeaderControls: ([CGRect]) -> Void

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.clear
            if state.expanded {
                DrawerView(state: state,
                           onOpen: onOpen,
                           onOpenMyPR: onOpenMyPR,
                           onCollapse: onCollapse,
                           onRefresh: onRefresh,
                           onRowHeights: onRowHeights,
                           onSelectTab: onSelectTab,
                           onToggleRoom: onToggleRoom,
                           onResetBadgeSize: onResetBadgeSize,
                           onHeaderControls: onHeaderControls)
            } else {
                BadgeView(state: state)
            }
        }
    }
}
