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

    // MARK: - Shared filters

    /// Narrows **both** tabs to one repository, as `owner/name`. Shared rather
    /// than per-tab because "I'm in this repo today" is one intent, not two.
    @Published var repoFilter: String? = Prefs.repoFilter {
        didSet { Prefs.repoFilter = repoFilter }
    }

    // MARK: - My PRs tab

    @Published var myPRs: [MyPullRequest] = []
    @Published var myPRSortOrder: MyPRSortOrder = Prefs.myPRSortOrder {
        didSet { Prefs.myPRSortOrder = myPRSortOrder }
    }
    @Published var myPRFilter: MyPRFilter = Prefs.myPRFilter {
        didSet { Prefs.myPRFilter = myPRFilter }
    }
    /// Narrows the list to stacks. A second axis rather than a `MyPRFilter`
    /// case, so it combines with whatever the filter menu is set to.
    @Published var myPRStackedOnly: Bool = Prefs.myPRStackedOnly {
        didSet {
            Prefs.myPRStackedOnly = myPRStackedOnly
            if myPRStackedOnly { trophyState.record(TrophyFact.usedStackedFilter) }
        }
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
    /// Whether a newer PR Radar release is published.
    @Published var updateStatus: UpdateStatus = .unknown
    /// Ticks so relative timestamps re-render without a network round trip.
    @Published var clock = Date()

    // MARK: - Trophy room

    /// Whether the drawer is showing the shelf instead of a list.
    ///
    /// A mode rather than a third `DrawerTab`: the room replaces the tab
    /// strip, so a tab that hides the control it lives in would be a strange
    /// kind of tab. Keeping `selectedTab` underneath is what lets leaving the
    /// room put you back where you were.
    @Published var showingTrophies: Bool = Prefs.showingTrophies {
        didSet { Prefs.showingTrophies = showingTrophies }
    }

    @Published var trophyState: TrophyState = AppState.loadTrophies() {
        // Never written while the debug flag is on: looking at the room as a
        // finished thing must not *make* it one.
        didSet { if !Log.fakeTrophies { Prefs.trophyState = trophyState } }
    }

    static func loadTrophies() -> TrophyState {
        Log.fakeTrophies ? .everythingUnlocked(at: Date()) : Prefs.trophyState
    }

    /// Mascot cycles since the drawer was last opened.
    ///
    /// Not persisted, and reset on every open: `Carousel` is for sitting
    /// there clicking the thing, and ten clicks spread over ten weeks is not
    /// that.
    @Published var mascotCycles = 0

    /// What the drawer is actually showing below the header.
    var activeSurface: DrawerSurface {
        showingTrophies ? .trophies : DrawerSurface(selectedTab)
    }

    var trophyRows: [[Trophy]] { TrophyGrid.rows() }

    var trophyProgress: String {
        TrophyGrid.progress(unlocked: trophyState.unlockedIDs)
    }

    /// Opening the room is what counts as having looked at the shelf.
    func openTrophyRoom() {
        showingTrophies = true
        if trophyState.hasUnseen { trophyState.markAllSeen() }
    }

    /// Measured height of each row, keyed by a surface-namespaced row id.
    @Published var rowHeights: [String: CGFloat] = [:]
    /// Row-list height the user dragged to, per surface: My PR rows are far
    /// taller than review rows and a shelf row is shorter than either, so a
    /// single shared height would fight itself.
    @Published var userContentHeights: [DrawerSurface: CGFloat] = AppState.loadHeights()

    static func loadHeights() -> [DrawerSurface: CGFloat] {
        var result: [DrawerSurface: CGFloat] = [:]
        for surface in DrawerSurface.allCases {
            if let height = Prefs.drawerContentHeight(for: surface) { result[surface] = height }
        }
        return result
    }

    // MARK: - Displayed lists

    var displayedItems: [ReviewItem] {
        var filtered = RepoScope.apply(repoFilter, to: items, repoOf: \.repo)
        if let author = authorFilter {
            filtered = filtered.filter { $0.authorLogin == author }
        }
        return sortOrder.apply(to: filtered)
    }

    /// The My PRs list as the drawer actually lays it out: lone PRs and stack
    /// groups, in display order.
    ///
    /// This is the choke point, not `displayedMyPRs` — the drawer sizes itself
    /// by summing one measured height per *unit*, and a group is one unit
    /// however many PRs are in it.
    var displayedMyPRUnits: [MyPRUnit] {
        let scoped = RepoScope.apply(repoFilter, to: myPRs, repoOf: \.repo)
        let filtered = myPRFilter.apply(to: scoped)
        // Grouping is what the pancake button is *for*. Everywhere else the
        // list stays a flat list of PRs, exactly as it was — a plate and a
        // column of pancakes is a lot of furniture to impose on someone who
        // asked to see their failing checks.
        guard myPRStackedOnly else {
            return myPRSortOrder.apply(to: filtered).map(MyPRUnit.single)
        }
        // Grouped *then* narrowed to groups, rather than filtering PRs on
        // `isStacked`: that flag is computed against the whole inbox, so it
        // would keep a PR whose partner the repo filter has already hidden —
        // a stack of one, which is not a stack.
        return MyPRGrouping.units(filtered, order: myPRSortOrder).filter(\.isStack)
    }

    /// The same list, flattened. Counts and empty states answer in pull
    /// requests, because that is what the user is counting.
    var displayedMyPRs: [MyPullRequest] {
        displayedMyPRUnits.flatMap(\.pullRequests)
    }

    /// Authors available to filter by, within the current repo filter — so the
    /// author menu never offers someone the repo filter has already excluded.
    var authors: [String] {
        let scoped = RepoScope.apply(repoFilter, to: items, repoOf: \.repo)
        return Array(Set(scoped.map(\.authorLogin)))
            .sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Every repo appearing in either tab, so the menu covers both.
    var repos: [String] {
        RepoScope.names(reviews: items.map(\.repo), mine: myPRs.map(\.repo))
    }

    func repoCount(_ repo: String) -> (reviews: Int, mine: Int) {
        (RepoScope.apply(repo, to: items, repoOf: \.repo).count,
         RepoScope.apply(repo, to: myPRs, repoOf: \.repo).count)
    }

    static func shortRepoName(_ repo: String) -> String { RepoScope.shortName(repo) }

    var isRepoFiltered: Bool { repoFilter != nil }
    var isFiltered: Bool { authorFilter != nil }
    var isMyPRFiltered: Bool { myPRFilter != .all || myPRStackedOnly }

    /// Whether anything in scope is stacked.
    ///
    /// Scoped by repo but not by the filter menu: the repo filter is a scope —
    /// "I'm in this repo today" — so a repo with no stacks should not offer a
    /// stacked filter, while a bar whose controls came and went every time you
    /// changed the *other* filter would be its own kind of annoying.
    var hasStackedPRs: Bool {
        MyPRGrouping.containsStack(RepoScope.apply(repoFilter, to: myPRs, repoOf: \.repo))
    }

    // MARK: - Active-surface geometry

    /// Row ids are namespaced by surface so no two can collide.
    func rowKey(_ surface: DrawerSurface, _ id: String) -> String {
        RowHeightKeys.key(surface: surface, id: id)
    }

    /// How many rows the drawer's height snaps to.
    ///
    /// Pull requests, not units: a stack is one card but several rows, and a
    /// drawer that could only stop at whole cards could not be dragged at all
    /// while the pancake filter is the only thing showing.
    func rowCount(for surface: DrawerSurface) -> Int {
        switch surface {
        case .reviews: return displayedItems.count
        case .mine: return displayedMyPRs.count
        // A grid row, not a trophy. The drawer snaps to what the eye reads as
        // a line, and nobody reads a shelf a trophy at a time.
        case .trophies: return trophyRows.count
        }
    }

    /// Measured heights of a tab's rows, in display order.
    func rowHeights(for surface: DrawerSurface) -> [CGFloat] {
        switch surface {
        case .reviews:
            return displayedItems.compactMap { rowHeights[rowKey(.reviews, $0.id)] }
        case .mine:
            return MyPRGrouping.stopHeights(
                units: displayedMyPRUnits,
                stackChrome: Layout.stackGroupPadding * 2,
                height: { rowHeights[rowKey(.mine, $0.id)] })
        case .trophies:
            return trophyRows.indices.compactMap {
                rowHeights[rowKey(.trophies, TrophyGrid.rowID($0))]
            }
        }
    }

    var activeRowCount: Int { rowCount(for: activeSurface) }
    var activeRowHeights: [CGFloat] { rowHeights(for: activeSurface) }

    var userContentHeight: CGFloat? {
        get { userContentHeights[activeSurface] }
        set {
            if let newValue {
                userContentHeights[activeSurface] = newValue
            } else {
                userContentHeights.removeValue(forKey: activeSurface)
            }
        }
    }

    // MARK: - Repo scope
    //
    // The repo filter behaves as a *scope* — "I'm working in this repo today" —
    // so the badge follows it. The author and state filters are temporary view
    // narrowing and deliberately do not, or the badge would flicker every time
    // you poked at a menu.

    var repoScopedItems: [ReviewItem] {
        RepoScope.apply(repoFilter, to: items, repoOf: \.repo)
    }

    var repoScopedMyPRs: [MyPullRequest] {
        RepoScope.apply(repoFilter, to: myPRs, repoOf: \.repo)
    }

    // MARK: - Badge

    /// The badge counts review requests only — the number you owe other people.
    /// Your own PRs are informational and must not inflate it.
    var count: Int { repoScopedItems.count }

    /// Lights the badge's secondary dot: PRs of mine that are ready to merge.
    var myPRsReadyToMerge: Int { repoScopedMyPRs.filter(\.isReadyToMerge).count }

    /// The most overdue request in scope.
    var worstStaleness: Staleness {
        guard let oldest = repoScopedItems.map(\.pingedAt).min() else { return .fresh }
        return Staleness.of(oldest, now: clock)
    }

    var hasProblem: Bool { authError != nil }

    // MARK: - Mascot

    /// nil means the user turned the mascot off.
    @Published var mascot: MascotID? = Prefs.mascot {
        didSet {
            Prefs.mascot = mascot
            if let mascot { trophyState.record(TrophyFact.mascotSeen(mascot)) }
        }
    }

    /// A transient reaction that outranks the derived mood while it lasts:
    /// being hovered, being dragged, or a review arriving.
    @Published var reaction: Reaction?

    /// The badge's square size in points, as dragged from one of its corners.
    ///
    /// Every badge metric derives from this — tile, glyph, counter chips,
    /// sprite scale — so resizing is one number changing and the rest
    /// following. Defaults to the Dock's tile size, which is what the badge
    /// was fixed to before it could be resized at all.
    @Published var badgeTileSize: CGFloat = Prefs.badgeTileSize ?? Layout.dockTileSize {
        didSet { Prefs.badgeTileSize = badgeTileSize }
    }

    /// Backing scale of the screen the panel is actually on, published by
    /// `PanelController`.
    ///
    /// The view cannot work this out for itself, and guessing `NSScreen.main`
    /// is wrong on a mixed-DPI setup: the panel would be framed for one scale
    /// and drawn at another, which is exactly the fractional cell size that
    /// turns pixel art into a blurry JPEG.
    @Published var backingScale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2

    var selectedMascot: Mascot? { mascot.map(Mascot.named) }

    /// One derivation for every surface, so the drawer's character and the
    /// badge's can never disagree about what is going on.
    var mood: Mood {
        Mood.of(reviews: count,
                worst: worstStaleness,
                readyToMerge: myPRsReadyToMerge,
                isRefreshing: isRefreshing,
                hasProblem: hasProblem)
    }

    /// What the character is actually drawn as right now.
    var spriteStyle: SpriteStyle {
        reaction?.style(tint: mood.style.health) ?? mood.style
    }

    /// The collapsed widget — character, mood mark and a chip per non-zero
    /// count. Size does not depend on the animation frame, so the panel can be
    /// framed from this without knowing what frame is on screen.
    ///
    /// nil when the mascot is off, which is what puts the original tile back.
    var badgeLayout: SpriteLayout? {
        guard let mascot = selectedMascot else { return nil }
        return .widget(mascot: mascot,
                       style: spriteStyle,
                       frame: 0,
                       blink: false,
                       reviews: count,
                       reviewHealth: hasProblem ? .neutral : worstStaleness.health,
                       readyToMerge: myPRsReadyToMerge)
    }

    /// Advances to the next character, then to off, then round again. The whole
    /// picker, for anyone who finds it by clicking.
    ///
    /// "Off" is a stop on the loop, not the end of it — cycling out of it has
    /// to lead back to the first character or the control dead-ends.
    func cycleMascot() {
        mascot = MascotID.next(after: mascot)
        mascotCycles += 1
    }

    /// What the next click lands on, for the tooltip.
    var nextMascotName: String? {
        MascotID.next(after: mascot).map { Mascot.named($0).name } ?? "no mascot"
    }

    /// One-shot reaction, used when a new review lands. Cancels any previous
    /// one so two pings in quick succession do not leave it stuck.
    private var startleTask: Task<Void, Never>?

    func startle() {
        guard mascot != nil else { return }
        startleTask?.cancel()
        reaction = .startled
        startleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.reaction = nil
        }
    }

    /// Hidden only when *both* tabs are empty. Keying this on review requests
    /// alone would make My PRs unreachable exactly when the review queue is
    /// clear, which is when you most want to look at your own work.
    ///
    /// Deliberately ignores the repo scope: a filter matching nothing would
    /// otherwise hide the badge, leaving no way to reach the drawer and clear
    /// the very filter causing it.
    var shouldHidePanel: Bool {
        items.isEmpty && myPRs.isEmpty && !hasProblem
    }
}

extension Staleness {
    /// `health` itself now lives in PRRadarCore — it is the definition of the
    /// signal, and the mascot needs it too. Only the colour stays here.
    var tint: Color { health.tint }
}

extension Health {
    /// The single place colour is assigned, so checks, blockers, approvals and
    /// staleness cannot drift apart — the values themselves now live in
    /// PRRadarCore as `Health.rgb`, because the build-time icon generator has
    /// to read the same scale without importing SwiftUI.
    var tint: Color { Color(rgb) }
}
