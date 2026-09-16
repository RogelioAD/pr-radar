import SwiftUI
import PRRadarCore

/// Reports each row's measured height, keyed by a tab-namespaced row id, so the
/// panel can size itself to a whole number of rows instead of guessing.
struct RowHeightsKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

struct DrawerView: View {
    @ObservedObject var state: AppState
    let onOpen: (ReviewItem) -> Void
    let onOpenMyPR: (MyPullRequest) -> Void
    let onCollapse: () -> Void
    let onRefresh: () -> Void
    let onRowHeights: ([String: CGFloat]) -> Void
    let onSelectTab: (DrawerTab) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top edge is the resize grab strip — see PanelController.zone(at:).
            grabber
            header
            Divider().opacity(0.6)
            TabStripView(state: state, onSelect: onSelectTab)
            Divider().opacity(0.6)
            filterBar
            Divider().opacity(0.6)
            content
            Divider().opacity(0.6)
            footer
        }
        .frame(width: Layout.drawerWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, y: 6)
    }

    /// The strip always reserves its height so the drawer's chrome stays a
    /// fixed size for the sizing math; only the visible capsule is
    /// conditional.
    private var grabber: some View {
        Group {
            if state.canResizeDrawer {
                Capsule()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(width: 36, height: 4)
                    .help("Drag to resize")
            }
        }
        .frame(height: Layout.resizeEdge)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
    }

    // The header also drags the window — see PanelController.zone(at:).
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.pull")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("PR Radar")
                .font(.system(size: 12.5, weight: .semibold))
            if state.myPRsReadyToMerge > 0 {
                Chip(text: "\(state.myPRsReadyToMerge) ready to merge",
                     symbol: "checkmark.seal", health: .good)
            }
            Spacer()
            if let version = state.updateStatus.newerVersion {
                Button {
                    if let url = state.updateStatus.url {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Chip(text: "update \(version)", symbol: "arrow.down.circle",
                         health: .running, filled: true)
                }
                .buttonStyle(.plain)
                .help("A newer PR Radar release is available")
            }
            Button(action: onCollapse) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Collapse")
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.headerHeight - Layout.resizeEdge)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var filterBar: some View {
        switch state.selectedTab {
        case .reviews: ReviewFilterBar(state: state)
        case .mine: MyPRFilterBar(state: state)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let authError = state.authError {
            problem(title: "Can't reach GitHub", detail: authError, symbol: "key.slash")
        } else {
            switch state.selectedTab {
            case .reviews: reviewsList
            case .mine: myPRList
            }
        }
    }

    @ViewBuilder
    private var reviewsList: some View {
        let items = state.displayedItems
        if state.items.isEmpty {
            problem(title: "Inbox zero", detail: "No reviews waiting on you.",
                    symbol: "checkmark.circle")
        } else if items.isEmpty {
            problem(title: "Nothing from \(state.authorFilter ?? "that author")",
                    detail: "Clear the filter to see the other \(state.count).",
                    symbol: "line.3.horizontal.decrease.circle")
        } else {
            ScrollView {
                VStack(spacing: Layout.rowSpacing) {
                    ForEach(items) { item in
                        RowView(item: item, now: state.clock) { onOpen(item) }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .onPreferenceChange(RowHeightsKey.self, perform: onRowHeights)
        }
    }

    @ViewBuilder
    private var myPRList: some View {
        let items = state.displayedMyPRs
        if state.myPRs.isEmpty {
            problem(title: "No open PRs", detail: "Nothing of yours is in flight.",
                    symbol: "tray")
        } else if items.isEmpty {
            problem(title: "Nothing matches \(state.myPRFilter.label)",
                    detail: "Clear the filter to see all \(state.myPRs.count).",
                    symbol: "line.3.horizontal.decrease.circle")
        } else {
            ScrollView {
                VStack(spacing: Layout.rowSpacing) {
                    ForEach(items) { item in
                        MyPRRowView(item: item, now: state.clock,
                                    onOpen: { onOpenMyPR(item) })
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
            }
            .onPreferenceChange(RowHeightsKey.self, perform: onRowHeights)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Button(action: onRefresh) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .bold))
                    Text("Refresh").font(.system(size: 10.5))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .disabled(state.isRefreshing)
            .help("Refresh now — also checks for a new PR Radar release")

            Spacer()

            if state.isRefreshing {
                Text("updating…").font(.system(size: 10)).foregroundStyle(.tertiary)
            } else if let lastUpdated = state.lastUpdated {
                Text("updated \(TimeAgo.short(since: lastUpdated, now: state.clock))")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.footerHeight)
    }

    private func problem(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.tertiary)
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
        .frame(height: Layout.singleRowHeight())
    }
}

/// The Reviews tab's sort + author filter, unchanged in behaviour.
struct ReviewFilterBar: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(ReviewSortOrder.allCases, id: \.self) { order in
                    Button {
                        state.sortOrder = order
                    } label: {
                        if state.sortOrder == order {
                            Label(order.label, systemImage: "checkmark")
                        } else {
                            Text(order.label)
                        }
                    }
                }
            } label: {
                FilterPill(symbol: state.sortOrder.symbol,
                           text: state.sortOrder.label, active: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                Button { state.authorFilter = nil } label: {
                    if state.authorFilter == nil {
                        Label("All authors", systemImage: "checkmark")
                    } else {
                        Text("All authors")
                    }
                }
                Divider()
                ForEach(state.authors, id: \.self) { author in
                    Button {
                        state.authorFilter = (state.authorFilter == author) ? nil : author
                    } label: {
                        let count = state.items.filter { $0.authorLogin == author }.count
                        if state.authorFilter == author {
                            Label("\(author) (\(count))", systemImage: "checkmark")
                        } else {
                            Text("\(author) (\(count))")
                        }
                    }
                }
            } label: {
                FilterPill(symbol: "person.crop.circle",
                           text: state.authorFilter ?? "All authors",
                           active: state.isFiltered)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            RepoFilterMenu(state: state)

            Spacer()

            if state.isFiltered || state.isRepoFiltered {
                Button {
                    state.authorFilter = nil
                    state.repoFilter = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear filters")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Layout.filterBarHeight)
    }
}
