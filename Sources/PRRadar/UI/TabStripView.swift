import SwiftUI
import PRRadarCore

/// Segmented control choosing between the two tabs, with live counts.
struct TabStripView: View {
    @ObservedObject var state: AppState
    let onSelect: (DrawerTab) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DrawerTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: Layout.tabStripHeight)
    }

    /// Scoped to the selected repo, matching the badge — otherwise the tab
    /// would claim a total the badge disagrees with.
    private func total(for tab: DrawerTab) -> Int {
        switch tab {
        case .reviews: return state.repoScopedItems.count
        case .mine: return state.repoScopedMyPRs.count
        }
    }

    /// Reads `shown/total` while a filter is hiding rows, so the tab never
    /// claims a count the list below it is not showing.
    private func countLabel(for tab: DrawerTab) -> String {
        let total = total(for: tab)
        let shown = state.rowCount(for: DrawerSurface(tab))
        return shown == total ? "\(total)" : "\(shown)/\(total)"
    }

    /// The My PRs tab carries a dot when one of those PRs is ready to merge,
    /// matching the badge so the two never disagree.
    private func readyDot(_ tab: DrawerTab) -> Bool {
        tab == .mine && state.myPRsReadyToMerge > 0
    }

    private func tabButton(_ tab: DrawerTab) -> some View {
        let selected = state.selectedTab == tab
        return Button { onSelect(tab) } label: {
            HStack(spacing: 5) {
                Image(systemName: tab.symbol).font(.system(size: 9.5, weight: .semibold))
                Text(tab.title).font(.system(size: 11, weight: selected ? .semibold : .regular))
                Text(countLabel(for: tab))
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .padding(.horizontal, 4)
                    .padding(.vertical, 0.5)
                    .background(Capsule().fill(Color.primary.opacity(selected ? 0.16 : 0.10)))
                if readyDot(tab) {
                    Circle().fill(Health.good.tint).frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.10) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
