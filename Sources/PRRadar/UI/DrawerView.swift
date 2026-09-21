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

/// Frames of the controls the header carries, in the drawer's own coordinate
/// space. The header doubles as the window's drag handle, so the panel needs to
/// know where they are to leave their clicks to SwiftUI.
struct HeaderControlsKey: PreferenceKey {
    static var defaultValue: [CGRect] = []
    static func reduce(value: inout [CGRect], nextValue: () -> [CGRect]) {
        value.append(contentsOf: nextValue())
    }
}

struct DrawerView: View {
    /// Named so control frames are measured against the drawer's top-left,
    /// which is the frame of reference the zone rules already use.
    static let coordinateSpace = "drawer"

    @ObservedObject var state: AppState
    let onOpen: (ReviewItem) -> Void
    let onOpenMyPR: (MyPullRequest) -> Void
    let onCollapse: () -> Void
    let onRefresh: () -> Void
    let onRowHeights: ([String: CGFloat]) -> Void
    let onSelectTab: (DrawerTab) -> Void
    let onToggleTrophies: () -> Void
    let onHeaderControls: ([CGRect]) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top edge is the resize grab strip — see PanelController.zone(at:).
            grabber
            header
            Divider().opacity(0.6)
            // The room replaces everything below the header. Not hidden but
            // *absent*: a tab strip and a filter bar with nothing to act on
            // are two controls asking to be pressed and one band of chrome
            // the shelf then has to be shorter than.
            if state.showingTrophies {
                TrophyRoomView(state: state, onRowHeights: onRowHeights)
                Divider().opacity(0.6)
                trophyFooter
            } else {
                TabStripView(state: state, onSelect: onSelectTab)
                Divider().opacity(0.6)
                filterBar
                Divider().opacity(0.6)
                content
                Divider().opacity(0.6)
                footer
            }
        }
        .frame(width: Layout.drawerWidth)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.32), radius: 18, y: 6)
        .coordinateSpace(name: Self.coordinateSpace)
        .onPreferenceChange(HeaderControlsKey.self, perform: onHeaderControls)
    }

    /// Always shown: with the drawer defaulting to every row, dragging it
    /// *shorter* is the useful direction, so the handle is never inert.
    private var grabber: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 36, height: 4)
            .frame(height: Layout.resizeEdge)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .help("Drag to resize — snaps to whole rows")
    }

    /// True when the content area is showing its own, larger mascot.
    ///
    /// Both surfaces are live whenever the list is empty, and the same
    /// character twice in one 440pt panel is one too many — so the big one
    /// wins and the header falls back to the identity glyph.
    ///
    /// Never in the trophy room: there is no empty state down there to carry
    /// a character, so surrendering the header's would leave the drawer with
    /// no mascot at all and no way to reach the button that cycles it.
    private var contentShowsMascot: Bool {
        guard !state.showingTrophies else { return false }
        return state.selectedMascot != nil && (state.authError != nil || isListEmpty)
    }

    private var isListEmpty: Bool {
        switch state.selectedTab {
        case .reviews: return state.items.isEmpty || state.displayedItems.isEmpty
        case .mine: return state.myPRs.isEmpty || state.displayedMyPRs.isEmpty
        }
    }

    /// The character the header is showing, or nil when it is showing the
    /// plain identity glyph — either because the mascot is off, or because the
    /// content area below is already showing a bigger one.
    private var headerMascot: Mascot? {
        contentShowsMascot ? nil : state.selectedMascot
    }

    /// Always a button, whatever it happens to be drawing.
    ///
    /// The cast cycles pip → byte → widget → nimbus → off → pip, and "off" is a
    /// stop on that loop rather than the end of it. Drawing the glyph as inert
    /// art there is what strands somebody who cycles one past the last
    /// character: the only way back in would be the context menu.
    ///
    /// Clicking has to be published as a header control or the press is taken
    /// as a window drag and never arrives — the same machinery the update chip
    /// already uses.
    private var identity: some View {
        Button { state.cycleMascot() } label: {
            if let mascot = headerMascot {
                MascotView(mascot: mascot,
                           style: state.spriteStyle,
                           scale: Layout.headerMascotScale)
            } else {
                Image(systemName: "arrow.triangle.pull")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    // A 12pt glyph is a poor target; the row's full height is
                    // already reserved, so spend it.
                    .frame(width: 18, height: Layout.headerHeight - Layout.resizeEdge)
                    .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help(identityHelp)
        .headerControl()
    }

    private var identityHelp: String {
        guard let next = state.nextMascotName else { return "" }
        if let mascot = headerMascot { return "\(mascot.name) — click for \(next)" }
        if state.selectedMascot == nil { return "No mascot — click for \(next)" }
        return "Click for \(next)"
    }

    // The header also drags the window — see PanelController.zone(at:).
    private var header: some View {
        HStack(spacing: 8) {
            identity
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
                .headerControl()
            }
            trophyButton
            Button(action: onCollapse) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close")
            .headerControl()
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.headerHeight - Layout.resizeEdge)
        .contentShape(Rectangle())
    }

    /// The way into the shelf, and back out of it.
    ///
    /// A toggle rather than a one-way door: it is the only control that opens
    /// the room, so it has to be the one that closes it — the X beside it
    /// shuts the whole drawer, which is a different thing to want.
    ///
    /// The dot is the entire announcement for a silent backfill. Nothing
    /// banners on first run, so without it a shelf could fill up with nobody
    /// ever learning there was a shelf.
    private var trophyButton: some View {
        Button(action: onToggleTrophies) {
            Image(systemName: state.showingTrophies ? "trophy.fill" : "trophy")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(state.showingTrophies ? Color.accentColor : .secondary)
                .overlay(alignment: .topTrailing) {
                    if state.trophyState.hasUnseen && !state.showingTrophies {
                        Circle()
                            .fill(Health.good.tint)
                            .frame(width: 5, height: 5)
                            .offset(x: 3, y: -2)
                    }
                }
                .frame(width: 18, height: Layout.headerHeight - Layout.resizeEdge)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(trophyHelp)
        .headerControl()
    }

    private var trophyHelp: String {
        if state.showingTrophies { return "Back to your pull requests" }
        let unseen = state.trophyState.unseenCount
        guard unseen > 0 else { return "Trophy room" }
        return unseen == 1 ? "Trophy room — 1 new" : "Trophy room — \(unseen) new"
    }

    /// What the room has instead of a footer.
    ///
    /// The count, and nothing else: the refresh button below a list is about
    /// the list, and a shelf does not refresh — it is the same thirty
    /// drawings whatever GitHub says.
    private var trophyFooter: some View {
        HStack(spacing: 6) {
            Text(state.trophyProgress)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: Layout.footerHeight)
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
                        RowView(item: item, now: state.clock,
                                accountLabel: state.accountLabel(for: item.account)) {
                            onOpen(item)
                        }
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
            problem(title: state.myPRStackedOnly && state.myPRFilter == .all
                        ? "Nothing is stacked"
                        : "Nothing matches \(state.myPRFilter.label)",
                    detail: "Clear the filter to see all \(state.myPRs.count).",
                    symbol: "line.3.horizontal.decrease.circle")
        } else {
            ScrollView {
                VStack(spacing: Layout.rowSpacing) {
                    ForEach(state.displayedMyPRUnits) { unit in
                        switch unit {
                        case .single(let item):
                            MyPRRowView(item: item, now: state.clock,
                                        accountLabel: state.accountLabel(for: item.account),
                                        onOpen: { onOpenMyPR(item) })
                        case .stack(let stack):
                            MyPRStackView(stack: stack, now: state.clock,
                                          accountLabel: {
                                              state.accountLabel(for: $0.account)
                                          },
                                          onOpen: { onOpenMyPR($0) })
                        }
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

    /// The empty and error states already reserve a whole row's height for a
    /// 20pt SF Symbol, so the mascot costs no layout at all — and it puts the
    /// character where the drawer is otherwise at its most boring.
    private func problem(title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 6) {
            if let mascot = state.selectedMascot {
                MascotView(mascot: mascot,
                           style: state.spriteStyle,
                           scale: Layout.emptyStateMascotScale)
            } else {
                Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(.tertiary)
            }
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
            // Same order as the My PRs bar: the two scopes, then sort, then
            // the narrowing filter. One bar's habits should carry to the other.
            if state.showsAccountPicker { AccountFilterMenu(state: state) }

            RepoFilterMenu(state: state)

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
                // A pencil, not a bust: the account picker at the head of this
                // same bar is the profile glyph, and the two answer different
                // questions — who *wrote* the pull request, against which of
                // your identities fetched it. Two identical busts in one bar
                // asked the reader to tell them apart by their words alone.
                FilterPill(symbol: "pencil",
                           text: state.authorFilter ?? "All authors",
                           active: state.isFiltered)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

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

private extension View {
    /// Publishes this view's frame as a header control, so a press on it
    /// reaches SwiftUI instead of being taken as a window drag.
    func headerControl() -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: HeaderControlsKey.self,
                    value: [geometry.frame(in: .named(DrawerView.coordinateSpace))]
                )
            }
        )
    }
}
