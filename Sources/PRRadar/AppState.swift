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

    /// Narrows **both** tabs to one account, by `host/login`. nil means all of
    /// them, which is the only value under which the badge answers "who is
    /// waiting on you" for the whole of your work.
    @Published var accountFilter: String? = Prefs.accountFilter {
        didSet { Prefs.accountFilter = accountFilter }
    }

    /// Every account discovered on this machine, active one first.
    @Published var accounts: [Account] = []

    /// Accounts whose fetch failed this round, by `host/login`.
    ///
    /// Kept separate from `lastError` because the consequence is different: a
    /// total failure leaves the previous list standing, while a partial one
    /// produces a list and a count that are **real but incomplete**. Nothing
    /// about a smaller number looks wrong, so the incompleteness has to be
    /// carried explicitly or it is not communicated at all.
    @Published var failedAccounts: Set<String> = []

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
    /// Whether a newer PR Radar release is published.
    @Published var updateStatus: UpdateStatus = .unknown
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
        var filtered = scopedItems
        if let author = authorFilter {
            filtered = filtered.filter { $0.authorLogin == author }
        }
        return sortOrder.apply(to: filtered)
    }

    var displayedMyPRs: [MyPullRequest] {
        myPRSortOrder.apply(to: myPRFilter.apply(to: scopedMyPRs))
    }

    /// Authors available to filter by, within the current repo filter — so the
    /// author menu never offers someone the repo filter has already excluded.
    var authors: [String] {
        Array(Set(scopedItems.map(\.authorLogin)))
            .sorted { $0.lowercased() < $1.lowercased() }
    }

    /// Every repo appearing in either tab, so the menu covers both — within the
    /// account scope, so the menu never offers a repo the account strip has
    /// already excluded. Same rule the author menu follows one level down.
    var repos: [String] {
        RepoScope.names(reviews: accountScopedItems.map(\.repo),
                        mine: accountScopedMyPRs.map(\.repo))
    }

    func repoCount(_ repo: String) -> (reviews: Int, mine: Int) {
        (RepoScope.apply(repo, to: accountScopedItems, repoOf: \.repo).count,
         RepoScope.apply(repo, to: accountScopedMyPRs, repoOf: \.repo).count)
    }

    /// Counts for one account's tab in the strip, ignoring the repo filter so
    /// the strip always shows what switching to that account would reveal.
    func accountCount(_ id: String?) -> Int {
        AccountScope.apply(id, to: items, accountOf: \.account).count
    }

    static func shortRepoName(_ repo: String) -> String { RepoScope.shortName(repo) }

    var isRepoFiltered: Bool { repoFilter != nil }
    var isFiltered: Bool { authorFilter != nil }
    var isMyPRFiltered: Bool { myPRFilter != .all }

    // MARK: - Active-tab geometry

    /// Row ids are namespaced by tab so the two lists cannot collide.
    func rowKey(_ tab: DrawerTab, _ id: String) -> String {
        RowHeightKeys.key(tab: tab, id: id)
    }

    func rowCount(for tab: DrawerTab) -> Int {
        switch tab {
        case .reviews: return displayedItems.count
        case .mine: return displayedMyPRs.count
        }
    }

    /// Measured heights of a tab's rows, in display order.
    func rowHeights(for tab: DrawerTab) -> [CGFloat] {
        switch tab {
        case .reviews:
            return displayedItems.compactMap { rowHeights[rowKey(.reviews, $0.id)] }
        case .mine:
            return displayedMyPRs.compactMap { rowHeights[rowKey(.mine, $0.id)] }
        }
    }

    var activeRowCount: Int { rowCount(for: selectedTab) }
    var activeRowHeights: [CGFloat] { rowHeights(for: selectedTab) }

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

    // MARK: - Scope
    //
    // The repo and account filters behave as *scopes* — "I'm working in this
    // repo today", "I'm working as this identity today" — so the badge follows
    // both. The author and state filters are temporary view narrowing and
    // deliberately do not, or the badge would flicker every time you poked at a
    // menu.
    //
    // Account is applied first: the repo menu is built from what the scoped
    // account can see, so narrowing to an account cannot leave a repo selected
    // that the account has nothing in.

    var accountScopedItems: [ReviewItem] {
        AccountScope.apply(accountFilter, to: items, accountOf: \.account)
    }

    var accountScopedMyPRs: [MyPullRequest] {
        AccountScope.apply(accountFilter, to: myPRs, accountOf: \.account)
    }

    var scopedItems: [ReviewItem] {
        RepoScope.apply(repoFilter, to: accountScopedItems, repoOf: \.repo)
    }

    var scopedMyPRs: [MyPullRequest] {
        RepoScope.apply(repoFilter, to: accountScopedMyPRs, repoOf: \.repo)
    }

    // MARK: - Badge

    /// The badge counts review requests only — the number you owe other people.
    /// Your own PRs are informational and must not inflate it.
    var count: Int { scopedItems.count }

    /// True when this round could not reach every account in scope, so `count`
    /// is real but short. The badge has to say so: a number that is merely
    /// smaller than the truth looks exactly like good news.
    var isPartial: Bool {
        AccountScope.isPartial(failed: failedAccounts, scope: accountFilter)
    }

    /// Lights the badge's secondary dot: PRs of mine that are ready to merge.
    var myPRsReadyToMerge: Int { scopedMyPRs.filter(\.isReadyToMerge).count }

    /// The most overdue request in scope.
    var worstStaleness: Staleness {
        guard let oldest = scopedItems.map(\.pingedAt).min() else { return .fresh }
        return Staleness.of(oldest, now: clock)
    }

    var hasProblem: Bool { authError != nil }

    /// Accounts to show in the strip. Hidden entirely below two, since a strip
    /// offering one choice is a control that cannot be used.
    var showsAccountStrip: Bool { accounts.count > 1 }

    // MARK: - Mascot

    /// nil means the user turned the mascot off.
    @Published var mascot: MascotID? = Prefs.mascot {
        didSet { Prefs.mascot = mascot }
    }

    /// A transient reaction that outranks the derived mood while it lasts:
    /// being hovered, being dragged, or a review arriving.
    @Published var reaction: Reaction?

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
                       reviewHealth: hasProblem || isPartial ? .neutral : worstStaleness.health,
                       readyToMerge: myPRsReadyToMerge)
    }

    /// Advances to the next character, then to off, then round again. The whole
    /// picker, for anyone who finds it by clicking.
    ///
    /// "Off" is a stop on the loop, not the end of it — cycling out of it has
    /// to lead back to the first character or the control dead-ends.
    func cycleMascot() {
        mascot = MascotID.next(after: mascot)
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
