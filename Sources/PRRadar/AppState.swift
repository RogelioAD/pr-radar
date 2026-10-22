import SwiftUI
import PRRadarCore

@MainActor
final class AppState: ObservableObject {

    // MARK: - Reviews tab

    /// Everything waiting on the viewer, unfiltered. The badge counts these.
    @Published var items: [ReviewItem] = [] {
        didSet {
            // A row that has gone cannot have its findings open. Left behind,
            // its key would hold the drawer at double width over a list with
            // nothing open in it.
            let live = Set(items.map(\.pingKey))
            if !openFindings.isSubset(of: live) { openFindings.formIntersection(live) }
        }
    }

    /// Rows whose findings list is open, by ping key.
    ///
    /// Here rather than in the row, where it started, because the *panel* has
    /// to read it: showing a diff doubles the drawer's width, and a row-local
    /// `@State` is invisible to the frame calculation that would have to grow.
    ///
    /// A set rather than one key, because comparing two findings in the same
    /// file is the commonest reason to open the code at all.
    @Published var openFindings: Set<String> = []

    /// How wide the drawer should be drawn, and framed, right now.
    ///
    /// Read in both places, from one rule: a panel and its contents that
    /// disagree about the width clip.
    var drawerWidth: CGFloat { drawerWidth(room: room, tab: selectedTab) }

    /// The same, for a room and tab the drawer has not moved to yet.
    ///
    /// Asked *before* the move, because both halves of the drawer have to be
    /// told to travel at once: the window eases, and the contents only ease
    /// too if the change that resized them was made inside an animation. Which
    /// means knowing it was a resize before making it.
    func drawerWidth(room: DrawerRoom?, tab: DrawerTab,
                     openKeys: Set<String>? = nil) -> CGFloat {
        // Which tab is showing decides which set of keys the question is about;
        // the question is the same one either way.
        let open = openKeys ?? expanded(on: tab)
        return DrawerWidth.isWide(room: room, openKeys: open,
                                  expandable: expandable(on: tab))
            ? Layout.wideDrawerWidth
            : Layout.drawerWidth
    }

    /// The width a row is laid out at, which follows the drawer's.
    ///
    /// `Layout.listContentWidth` is the standard one and is still right most of
    /// the time; a row told that while the drawer is at double width simply
    /// leaves half of it empty.
    var listContentWidth: CGFloat { drawerWidth - Layout.listPadding }

    /// What is expanded on a tab, and what could be.
    func expanded(on tab: DrawerTab) -> Set<String> {
        switch tab {
        case .reviews: return openFindings
        case .mine: return openThreads
        }
    }

    func expandable(on tab: DrawerTab) -> [String] {
        switch tab {
        case .reviews: return keysAwaitingSelection
        case .mine: return idsWithUnresolvedThreads
        }
    }

    /// Pull requests of yours with a thread there is something to show for.
    ///
    /// The count and the threads can disagree: `reviewThreads` is fetched a
    /// hundred at a time and a thread GitHub gave no id to is dropped. A row
    /// saying `3 open` with nothing behind it must not offer to open.
    var idsWithUnresolvedThreads: [String] {
        scopedMyPRs.filter { !$0.unresolvedThreads.isEmpty }.map(\.id)
    }
    @Published var sortOrder: ReviewSortOrder = Prefs.sortOrder {
        didSet { Prefs.sortOrder = sortOrder }
    }
    /// nil means every author.
    @Published var authorFilter: String?

    /// Narrows the Reviews list by what the triage signals say — CI that is
    /// not already red, or pull requests nobody has approved yet.
    ///
    /// A second axis from the author menu rather than another entry in it, in
    /// the same sense the pancake button is a second axis on My PRs: *small
    /// ones nobody has looked at* is one question, and it takes two controls
    /// to ask it.
    @Published var reviewFilter: ReviewFilter = Prefs.reviewFilter {
        didSet { Prefs.reviewFilter = reviewFilter }
    }

    /// Which row the keyboard is on. See `Selection`.
    ///
    /// Not persisted and not shared with the pointer: hovering a row does not
    /// move it, and it does not survive the drawer closing. It is where the
    /// keyboard is looking right now, which is not a preference and not a
    /// fact about the work.
    @Published var selection = Selection()

    /// The ids the selection steps through, in the order they are drawn.
    var selectableIDs: [String] {
        switch selectedTab {
        case .reviews: return displayedItems.map(\.id)
        case .mine: return displayedMyPRs.map(\.id)
        }
    }

    /// The review request the selection is on, if the Reviews tab is showing.
    var selectedItem: ReviewItem? {
        guard selectedTab == .reviews, let id = selection.id else { return nil }
        return displayedItems.first { $0.id == id }
    }

    var selectedMyPR: MyPullRequest? {
        guard selectedTab == .mine, let id = selection.id else { return nil }
        return displayedMyPRs.first { $0.id == id }
    }

    /// Applies one key press. Returns whether it was used, so a key the drawer
    /// has no meaning for is left for whatever else wants it.
    @discardableResult
    func handle(_ command: KeyCommand) -> Bool {
        switch command {
        case .moveDown, .moveUp:
            let ids = selectableIDs
            guard !ids.isEmpty else { return false }
            selection.move(by: command == .moveDown ? 1 : -1, in: ids)
            return true
        case .tab(let index):
            guard let tab = DrawerTab.allCases.indices.contains(index)
                    ? DrawerTab.allCases[index] : nil
            else { return false }
            guard tab != selectedTab else { return true }
            selectedTab = tab
            // The selection belongs to a list, and this is a different one.
            selection.clear()
            return true
        case .snooze:
            guard let item = selectedItem else { return false }
            // An hour, which is the shortest of the three. A keystroke should
            // not be able to put something down until Monday without saying
            // so — the menu is where the longer ones are, with their names on.
            snooze(item, until: Date().addingTimeInterval(3_600))
            // Onto whatever took its place, so a run of them clears without
            // the selection falling off the list.
            selection.validate(against: selectableIDs)
            return true
        case .open, .collapse, .refresh:
            // Handled by the panel, which owns the window and the browser.
            return false
        }
    }

    /// Review requests you have opened and not finished with. See `Opened`.
    @Published var opened: Opened = Prefs.opened {
        didSet { Prefs.opened = opened }
    }

    /// Review requests put down until later. See `Snoozes`.
    @Published var snoozes: Snoozes = Prefs.snoozes {
        didSet { Prefs.snoozes = snoozes }
    }

    /// Whether the list is showing the sleeping rows instead of the waking
    /// ones.
    ///
    /// Session-only, where the triage filter is persisted. It is a way of
    /// looking at the list rather than a standing preference about the work,
    /// and leaving it on across a restart would open the drawer onto a list of
    /// rows that are all asleep beside a badge reading zero — the same
    /// empty-drawer trap that keeps the author filter out of defaults.
    @Published var showingSnoozed = false

    // MARK: - Shared filters

    /// Narrows **both** tabs to one repository, as `owner/name`. Shared rather
    /// than per-tab because "I'm in this repo today" is one intent, not two.
    /// Several, not one. "I'm in this repo today" was the intent the filter
    /// was built for, and plenty of days it is three of them — with one
    /// selection the only way to see three was to see all twelve.
    ///
    /// Empty means every repository, which is what nil meant before.
    @Published var repoFilter: Set<String> = Prefs.repoFilter {
        didSet { Prefs.repoFilter = repoFilter }
    }

    /// Adds or removes one repository from the scope.
    func toggleRepo(_ repo: String) {
        if repoFilter.contains(repo) {
            repoFilter.remove(repo)
        } else {
            repoFilter.insert(repo)
        }
    }

    /// Narrows **both** tabs to one account, by `host/login`. nil means all of
    /// them, which is the only value under which the badge answers "who is
    /// waiting on you" for the whole of your work.
    @Published var accountFilter: String? = Prefs.accountFilter {
        didSet {
            Prefs.accountFilter = accountFilter
            // Switching account is the second way a repo filter can go stale,
            // and it goes stale immediately rather than at the next refresh:
            // the repo you were narrowed to may not exist for this identity at
            // all, which would leave an empty drawer beside a non-zero strip.
            dropStaleRepoFilter()
        }
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

    @Published var myPRs: [MyPullRequest] = [] {
        didSet {
            // Same reason as `items`: a row that has gone cannot have anything
            // open on it, and a key left behind would hold the drawer wide.
            let live = Set(myPRs.map(\.id))
            if !openThreads.isSubset(of: live) { openThreads.formIntersection(live) }
        }
    }
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

    // MARK: - Rooms

    /// The header-reached surface currently covering the drawer, or nil for the
    /// ordinary tabs.
    ///
    /// A mode rather than more `DrawerTab` cases: a room replaces the tab
    /// strip, so a tab that hides the control it lives in would be a strange
    /// kind of tab. Keeping `selectedTab` underneath is what lets leaving a
    /// room put you back where you were.
    ///
    /// One optional rather than a flag per room, so opening the second cannot
    /// leave the first open behind it — there is no value here that means both.
    @Published var room: DrawerRoom? = Prefs.drawerRoom {
        didSet { Prefs.drawerRoom = room }
    }

    var showingTrophies: Bool { room == .trophies }
    var showingSettings: Bool { room == .settings }

    @Published var trophyState: TrophyState = AppState.loadTrophies() {
        // Never written while the shelf is a fiction: looking at the room as
        // a finished thing must not *make* it one, and looking at it empty
        // must not clear it.
        didSet { if Log.fakeShelf == nil { Prefs.trophyState = trophyState } }
    }

    static func loadTrophies() -> TrophyState {
        switch Log.fakeShelf {
        case .all: return .everythingUnlocked(at: Date())
        case .empty: return TrophyState()
        case nil: return Prefs.trophyState
        }
    }

    // MARK: - Settings

    /// Whether a LaunchAgent is registered to start the app at login.
    ///
    /// Mirrored here rather than read from `LoginItem` at each use: the truth is
    /// a file on disk, and a SwiftUI body that stats the filesystem every time
    /// it is evaluated is a poor way to draw a switch. Written only through
    /// `setOpensAtLogin`, which is the one place that can fail.
    @Published private(set) var opensAtLogin: Bool = LoginItem.isEnabled

    /// Registers or unregisters the login item, reporting a failure the same
    /// way a failed refresh is reported and leaving the switch where it was.
    ///
    /// The switch follows the filesystem rather than the click: a write that
    /// threw must not leave a control claiming the opposite of what is true.
    func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try LoginItem.enable(appPath: Bundle.main.bundlePath)
            } else {
                try LoginItem.disable()
            }
        } catch {
            lastError = "Login item: \(error.localizedDescription)"
        }
        opensAtLogin = LoginItem.isEnabled
    }

    /// Whether clearing the review queue drops the achievement banner.
    @Published var widgetVisible: Bool = Prefs.widgetVisible {
        didSet {
            Prefs.widgetVisible = widgetVisible
            // Taking effect at the next poll would mean choosing it from a menu
            // and watching nothing happen for a minute.
            onWidgetVisibilityChanged?()
        }
    }
    /// Set by the delegate, so the choice lands immediately.
    var onWidgetVisibilityChanged: (() -> Void)?

    @Published var notifyComments: Bool = Prefs.notifyComments {
        didSet { Prefs.notifyComments = notifyComments }
    }
    @Published var notifyBotComments: Bool = Prefs.notifyBotComments {
        didSet { Prefs.notifyBotComments = notifyBotComments }
    }
    @Published var celebrateCleared: Bool = Prefs.celebrateCleared {
        didSet { Prefs.celebrateCleared = celebrateCleared }
    }

    /// Which repository the update check watches, as the settings field holds
    /// it — which is not always something worth storing.
    ///
    /// Kept as the edit buffer so the field can be emptied and retyped, and
    /// written through only once it names a repository. Persisting each
    /// keystroke would leave the check pointed at `Rogelio` the moment someone
    /// selected the old value and started typing a new one.
    @Published var updateRepoDraft: String = Prefs.updateRepo

    // MARK: - Automatic review

    /// Whether PR Radar reviews the PRs waiting on you by itself.
    ///
    /// Written through like every other switch, but see `toggleAutoReview()`
    /// for the one path that is allowed to refuse.
    @Published var autoReviewEnabled: Bool = Prefs.autoReview {
        didSet { Prefs.autoReview = autoReviewEnabled }
    }

    /// How much of a finished review goes out without being looked at.
    @Published var reviewMode: AutoReviewMode = Prefs.reviewMode {
        didSet { Prefs.reviewMode = reviewMode }
    }

    /// Ticks or unticks one finding on a held review.
    ///
    /// Writes straight back to the log, which is what persists the choice: a
    /// review can sit half-picked-over across a relaunch, and losing the ticks
    /// would mean reading nine findings again.
    /// Looks in both arrays, because the row draws them as one list. A comment
    /// you wrote has to untick like any other, and which array it came out of
    /// is bookkeeping the row has no business knowing about.
    func setFinding(_ id: String, on item: ReviewItem, selected: Bool) {
        guard var record = autoReviewLog[item.pingKey] else { return }
        if let index = record.prepared.firstIndex(where: { $0.id == id }) {
            record.prepared[index].isSelected = selected
        } else if let index = record.authored.firstIndex(where: { $0.id == id }) {
            record.authored[index].isSelected = selected
        } else {
            return
        }
        autoReviewLog[item.pingKey] = record
    }

    /// Ticks or unticks a whole tier at once — the "all three nits, actually"
    /// case, which is otherwise three presses in a narrow drawer.
    func setTier(_ tier: FindingTier, on item: ReviewItem, selected: Bool) {
        guard var record = autoReviewLog[item.pingKey] else { return }
        for index in record.prepared.indices where record.prepared[index].tier == tier {
            record.prepared[index].isSelected = selected
        }
        for index in record.authored.indices where record.authored[index].tier == tier {
            record.authored[index].isSelected = selected
        }
        autoReviewLog[item.pingKey] = record
    }

    /// Adds a comment you wrote to a finished review.
    ///
    /// Ticked on arrival, unlike a nit: you do not type a sentence into a
    /// narrow drawer in order to then decide whether to send it.
    ///
    /// Returns whether it landed, so the field can keep what was typed when it
    /// did not — a row whose record has gone is the one case, and silently
    /// swallowing the text there would be worse than the failure.
    @discardableResult
    func addAuthoredComment(_ comment: PreparedFinding, on item: ReviewItem) -> Bool {
        guard var record = autoReviewLog[item.pingKey], record.status == .ready
        else { return false }
        // A second comment on the same line with the same words is the double
        // press, not a second thought. `id` is tier|file|line|summary, so this
        // is exactly the test the findings list already de-duplicates on.
        guard !record.sendable.contains(where: { $0.id == comment.id }) else { return false }
        record.authored.append(comment)
        autoReviewLog[item.pingKey] = record
        return true
    }

    /// Takes one back out. Only ever an authored comment: the skill's findings
    /// are unticked, never deleted, because the row is a record of what the
    /// review said as well as a list of what you are sending.
    func removeAuthoredComment(_ id: String, on item: ReviewItem) {
        guard var record = autoReviewLog[item.pingKey] else { return }
        record.authored.removeAll { $0.id == id }
        autoReviewLog[item.pingKey] = record
    }

    // MARK: - The plain-English lens

    /// Whether the drawer is showing plain-English readings.
    ///
    /// Flipped through `LensCoordinator.toggle()` rather than set directly from
    /// a view, because switching it on is also what starts the translating.
    @Published var lensOn: Bool = Prefs.lensOn {
        didSet { Prefs.lensOn = lensOn }
    }

    /// Whether a lens run is in flight, for the header to say so.
    ///
    /// Live and never persisted: a run does not survive the app that started
    /// it, and a spinner restored at launch would spin for ever.
    @Published var lensTranslating = false

    @Published var lensStore: LensStore = Prefs.lensStore {
        didSet { Prefs.lensStore = lensStore }
    }

    weak var lens: LensCoordinator?

    func toggleLens() { lens?.toggle() }

    /// Every piece of text the lens would translate, for what is on screen now.
    ///
    /// Drawn from the *displayed* lists rather than everything fetched, which
    /// is the difference between translating what you are looking at and
    /// translating a filtered-out backlog you are not. A filter that hides
    /// twenty rows should not spend anything on them.
    ///
    /// Only what a row actually renders: a finding's `summary` and a comment's
    /// `body`. `detail` and `recommendation` are hover text, and hover text
    /// stays in the original words by design — the reading is the lens, the
    /// tooltip is the source.
    var lensSources: [String] { lensSources(visibleOnly: false) }

    /// The text you can actually read right now: the rows that are open.
    ///
    /// Its own list because the lens is pressed to change *what is on screen*,
    /// and a row whose findings or threads are collapsed shows none of this.
    /// Translating everything in one undifferentiated pass meant the first
    /// thing to come back was as likely to be a comment on a closed row as the
    /// one being looked at — so the press appeared to do nothing for a minute,
    /// and then changed something out of sight.
    var lensVisibleSources: [String] { lensSources(visibleOnly: true) }

    private func lensSources(visibleOnly: Bool) -> [String] {
        var sources: [String] = []
        for item in displayedItems {
            if visibleOnly, !openFindings.contains(item.pingKey) { continue }
            guard let record = review(for: item) else { continue }
            for prepared in record.prepared + record.authored {
                sources.append(prepared.finding.summary)
            }
        }
        for pr in displayedMyPRs {
            if visibleOnly, !openThreads.contains(pr.id) { continue }
            for thread in pr.unresolvedThreads {
                for comment in thread.comments {
                    sources.append(comment.body)
                }
            }
        }
        return sources
    }

    /// Everything fetched, filtered or not — what pruning keeps.
    ///
    /// Deliberately wider than `lensSources`. Translating is driven by what is
    /// on screen, but *keeping* must not be: an author filter hides rows for as
    /// long as it is set, and pruning against the visible list would throw away
    /// their readings and buy them again the moment it is cleared.
    var lensKeepable: [String] {
        var sources: [String] = []
        for item in items {
            guard let record = review(for: item) else { continue }
            for prepared in record.prepared + record.authored {
                sources.append(prepared.finding.summary)
            }
        }
        for pr in myPRs {
            for thread in pr.unresolvedThreads {
                for comment in thread.comments { sources.append(comment.body) }
            }
        }
        return sources
    }

    /// The reading for a piece of text, or nil when there is not one.
    ///
    /// nil whenever the lens is off, so a view asking this question does not
    /// also have to ask whether the feature is on. One place to get it wrong
    /// instead of every call site.
    func lensReading(for source: String) -> String? {
        guard lensOn else { return nil }
        return lensStore.reading(for: source)
    }

    // MARK: - Finding things on disk

    /// One git call, for the two questions this type answers about the disk.
    ///
    /// A copy of the review coordinator's own, and deliberately so: that one
    /// runs a review and throws its own failures, and this one only ever asks a
    /// checkout what its origin is. Routing that through the coordinator's
    /// error vocabulary would make a nil answer here look like a failed run.
    /// Where git is, or nil. The same three candidates every caller here uses,
    /// asked in one place so a fourth does not get its own list.
    static func gitPath() -> String? {
        ProcessRunner.firstExecutable(
            among: ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"])
    }

    static func runGit(_ arguments: [String]) async throws -> String {
        guard let git = ProcessRunner.firstExecutable(
            among: ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"])
        else { return "" }
        let result = try await ProcessRunner.run(
            executable: git, arguments: arguments, timeout: 30)
        guard result.exitCode == 0 else { return "" }
        return result.stdout
    }

    // Started on the review coordinator and were private there. They answer
    // two questions the app asks from more than one place — where a repository
    // is checked out, and which directories a helper might live in — and a
    // second copy of a forty-line list of Node install layouts is how such
    // things drift.

    /// A checkout of `repo` somewhere under `root`, found by asking git.
    ///
    /// Matching on the folder's *name* was the first version and it fails on
    /// the commonest real layout there is: a worktrees directory, where every
    /// checkout is named after its branch and not one of them is named after
    /// the repository. Renamed clones fail the same way. So the name-based
    /// guesses are tried first — they are free and usually right — and then
    /// every git directory under the root is asked what its origin actually is.
    ///
    /// A worktree is a perfectly good answer: `git worktree add` from inside
    /// one resolves to the shared common directory, so the new checkout comes
    /// off the same object store.
    func findCheckout(of repo: String, under root: String) async -> URL? {
        var seen = Set<String>()
        var candidates = Workspace.candidates(root: root, repo: repo)

        // Then the root itself and everything one level inside it.
        let expanded = (root as NSString).expandingTildeInPath
        candidates.append(expanded)
        let children = (try? FileManager.default.contentsOfDirectory(atPath: expanded)) ?? []
        candidates += children
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { (expanded as NSString).appendingPathComponent($0) }

        for path in candidates where seen.insert(path).inserted {
            guard isGitCheckout(path) else { continue }
            guard let remote = try? await Self.runGit(["-C", path, "remote", "get-url", "origin"])
            else { continue }
            if Workspace.remote(remote, names: repo) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// True for a clone *or* a worktree. In a clone `.git` is a directory; in a
    /// worktree it is a file pointing at the shared one. Testing only for a
    /// directory is what made every worktree invisible.
    func isGitCheckout(_ path: String) -> Bool {
        FileManager.default.fileExists(
            atPath: (path as NSString).appendingPathComponent(".git"))
    }

    func helperPaths() -> [String] {
        // The skill shells out to `gh`, which a GUI-launched app's PATH does
        // not contain. The same directories `claude` is looked for in, because
        // the two are installed the same ways and by the same people — two
        // Homebrew paths found `gh` on this machine and would have failed on a
        // MacPorts or nix one, with the review dying halfway through rather
        // than saying anything useful.
        //
        // The directory `claude` was actually found in goes first: whatever
        // installed one very often installed the other beside it.
        var paths: [String] = []
        if let claude = claudePath {
            paths.append((claude as NSString).deletingLastPathComponent)
        }
        paths += ClaudeInvocation.binDirectories(
            home: NSHomeDirectory(),
            pathVariable: ProcessInfo.processInfo.environment["PATH"])

        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    /// Repos automatic review is allowed to touch, lowercased for comparison.
    @Published var reviewRepos: [String] = Prefs.reviewRepos {
        didSet { Prefs.reviewRepos = reviewRepos }
    }

    var reviewAllowlist: Set<String> { Set(reviewRepos.map { $0.lowercased() }) }

    func isReviewAllowed(_ repo: String) -> Bool {
        reviewAllowlist.contains(repo.lowercased())
    }

    func setReviewAllowed(_ repo: String, _ allowed: Bool) {
        let key = repo.lowercased()
        if allowed {
            guard !reviewRepos.contains(where: { $0.lowercased() == key }) else { return }
            reviewRepos = (reviewRepos + [repo]).sorted()
        } else {
            reviewRepos.removeAll { $0.lowercased() == key }
        }
    }

    /// Every automatic review the app remembers.
    @Published var autoReviewLog: AutoReviewLog = Prefs.autoReviewLog {
        didSet {
            Prefs.autoReviewLog = autoReviewLog
            // A row that can no longer draw a findings list is not a row with
            // one open. Pressing a decision retires the findings with the
            // record, and a key left behind would re-open the list by itself if
            // the review were ever run again.
            let openable = Set(keysAwaitingSelection)
            if !openFindings.isSubset(of: openable) {
                openFindings.formIntersection(openable)
            }
        }
    }

    /// Pull requests of yours whose unresolved threads are open, by row id.
    ///
    /// Its own set rather than sharing `openFindings`: the two tabs are keyed
    /// differently — a ping key names one *request* to review, a row id names a
    /// pull request — and one set would have them colliding the moment the two
    /// namespaces overlapped.
    @Published var openThreads: Set<String> = []

    /// Rows showing a findings list to pick over, which is the only thing that
    /// widens the drawer. Scoped, because a row filtered out of the list is not
    /// on screen to be wide for.
    var keysAwaitingSelection: [String] {
        scopedItems
            .filter { autoReviewLog[$0.pingKey]?.isAwaitingSelection == true }
            .map(\.pingKey)
    }

    /// The pingKey of the review currently running, for the header's pulse.
    /// Not persisted: a review does not survive a relaunch.
    @Published var reviewInFlight: String?

    /// Rows with a mutation in flight, so a button cannot be pressed twice
    /// into the same round trip.
    ///
    /// Live and never persisted, like `reviewInFlight` beside it: an action
    /// does not survive the app that started it, and one remembered across a
    /// relaunch would be a row nobody could ever press again.
    @Published var rowActions = ActionGate()

    /// Ping keys waiting their turn, in the order they will be taken.
    ///
    /// Live rather than persisted, deliberately. Waiting is a fact about this
    /// minute — the queue is recomputed every refresh and again between
    /// reviews — and a `queued` record written to the log would outlive the
    /// condition: `recordSkips` only ever clears records it owns, so one left
    /// behind by a pull request that stopped being eligible would sit there
    /// claiming to be next for good.
    @Published var reviewQueue: [String] = []

    /// What the row shows for this PR.
    ///
    /// `PRRADAR_FAKE_REVIEW` stands a record up for every row, because the
    /// states this feature exists to produce are otherwise reachable only by
    /// spending real money on somebody's real pull request.
    func review(for item: ReviewItem) -> AutoReviewRecord? {
        if let faked = Log.fakeReview { return faked }
        return autoReviewLog[item.pingKey]
    }

    /// Held weakly: the coordinator already refers back to this state, and the
    /// delegate owns them both.
    weak var autoReviewer: AutoReviewCoordinator?

    func act(_ action: AutoReviewCoordinator.Action, on item: ReviewItem) {
        autoReviewer?.act(action, on: item)
    }

    /// Merges the base branch into the pull request, through GitHub rather than
    /// the local checkout.
    ///
    /// Lived on the resolve coordinator until that feature was removed, and had
    /// no business there: it touches no worktree, runs no skill and spends
    /// nothing. It is one mutation and the sentence to say when it fails.
    func updateBranch(_ pr: MyPullRequest) {
        let key = pr.id
        guard rowActions.begin(key) else { return }
        Task {
            await performUpdateBranch(pr)
            rowActions.end(key)
        }
    }

    private func performUpdateBranch(_ pr: MyPullRequest) async {
        guard let account = accounts.first(where: { $0.id == pr.account })
                ?? accounts.first,
              let token = Accounts.token(for: account),
              let nodeID = pr.nodeID,
              // Required, not optional. Without it GitHub would merge whatever
              // the branch happens to be now, which may be several pushes past
              // the row that offered the button.
              let headOid = pr.headOid
        else {
            lastError = "That PR arrived without the ids a merge needs."
            return
        }
        do {
            _ = try await GitHubClient(token: token)
                .updateBranch(pullRequestID: nodeID, expectedHeadOid: headOid)
            Log.debug("updated \(pr.repo)#\(pr.number) from \(pr.baseRefName)")
        } catch {
            // Said out loud rather than logged. The two interesting failures
            // both need the user to do something: the branch moved under them,
            // or the merge conflicts.
            lastError = "Could not update #\(pr.number) from "
                + "\(pr.baseRefName). It may have moved, or it may conflict — "
                + "you will have to merge it yourself."
        }
    }

    /// Asks reviewers who requested changes to look again.
    func nudge(_ people: [Approval], on pr: MyPullRequest) {
        let key = pr.id
        guard rowActions.begin(key) else { return }
        Task {
            await performNudge(people, on: pr)
            rowActions.end(key)
        }
    }

    private func performNudge(_ people: [Approval], on pr: MyPullRequest) async {
        let ids = people.compactMap(\.nodeID)
        guard let account = accounts.first(where: { $0.id == pr.account })
                ?? accounts.first,
              let token = Accounts.token(for: account),
              let nodeID = pr.nodeID,
              !ids.isEmpty
        else {
            lastError = "That PR arrived without the ids a re-request needs."
            return
        }
        do {
            _ = try await GitHubClient(token: token)
                .requestReview(pullRequestID: nodeID, userIDs: ids)
            Log.debug("re-requested \(ids.count) on \(pr.repo)#\(pr.number)")
        } catch {
            // Worth saying out loud: the press looked like it worked, and the
            // people on the other end are the whole point of it.
            lastError = "Could not re-request a review on #\(pr.number). "
                + "Nobody has been notified."
        }
    }

    /// Posts a reply to one of your own review threads.
    ///
    /// Returns whether it landed, so the field can keep what was typed when it
    /// did not. Nothing is resolved here — a reply and a resolution are two
    /// different claims, and the row deliberately only makes the first.
    func reply(to threadID: String, body: String, on pr: MyPullRequest) async -> Bool {
        guard let account = accounts.first(where: { $0.id == pr.account })
                ?? accounts.first,
              let token = Accounts.token(for: account)
        else {
            lastError = "No token for the account that pull request came from."
            return false
        }
        let url = await GitHubClient(token: token).replyToThread(id: threadID, body: body)
        if url == nil {
            lastError = "Could not post that reply to #\(pr.number). "
                + "What you typed is still there."
        } else {
            Log.debug("replied on \(pr.repo)#\(pr.number)")
        }
        return url != nil
    }

    /// The skill to run, as the settings field holds it — an edit buffer for
    /// the same reason `updateRepoDraft` is one.
    @Published var reviewSkillDraft: String = Prefs.reviewSkill ?? ""

    /// The ceiling on one review, in dollars. Zero means no ceiling.
    ///
    /// Surfaced rather than buried in `defaults` because of how it failed when
    /// it was buried: an invisible cap set below the cost of a real review
    /// killed every one of them partway through, and nothing on screen said a
    /// budget existed at all.
    @Published var reviewBudget: Double = Prefs.reviewBudget {
        didSet { Prefs.reviewBudget = reviewBudget }
    }

    /// How many reviews may start in any rolling hour. Zero means no cap.
    ///
    /// Surfaced for the reason the spend limit was, and after the same failure:
    /// rows sat there saying "hourly limit reached" with nothing anywhere in
    /// the app naming the limit, let alone offering to move it. A ceiling you
    /// cannot see is only distinguishable from a bug by reading the source.
    @Published var reviewMaxPerHour: Int = Prefs.reviewMaxPerHour {
        didSet {
            let clamped = max(0, reviewMaxPerHour)
            if clamped != reviewMaxPerHour { reviewMaxPerHour = clamped; return }
            Prefs.reviewMaxPerHour = clamped
        }
    }

    /// Where the clones live.
    ///
    /// Written through the moment it changes rather than buffered like the
    /// skill field, because it is now picked rather than typed — and this
    /// platform's convention, which the settings room already keeps, is that
    /// anything you choose from a menu applies at once. It is also why it does
    /// not appear in `hasPendingSettings`: a picker is never unsaved.
    @Published var reviewWorkspace: String? = Prefs.reviewWorkspace {
        didSet { Prefs.reviewWorkspace = reviewWorkspace }
    }

    /// Where the folder menu starts when nothing has been chosen. Home, because
    /// that is where a developer's clones almost always are.
    var reviewBrowsingFrom: String {
        reviewWorkspace.map(FolderPicker.normalized) ?? NSHomeDirectory()
    }

    /// The subfolders of whatever is being browsed, capped.
    ///
    /// Reads the disk, so it is a method on the store rather than something the
    /// view recomputes as it draws: a menu body is evaluated more often than it
    /// is opened, and listing a directory on each of those would be a lot of
    /// syscalls to draw the same six names.
    func reviewSubfolders(of path: String) -> [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
        return FolderPicker.visible(contents).filter { name in
            var isDirectory: ObjCBool = false
            let child = (path as NSString).appendingPathComponent(name)
            return FileManager.default.fileExists(atPath: child, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    }

    /// How many of a folder's children are git clones — the one fact that says
    /// whether this is the right folder.
    func reviewCloneCount(in path: String) -> Int {
        reviewSubfolders(of: path).prefix(FolderPicker.limit * 4).count { name in
            let child = (path as NSString).appendingPathComponent(name)
            return FileManager.default.fileExists(
                atPath: (child as NSString).appendingPathComponent(".git"))
        }
    }

    /// Where the `claude` CLI was found, or nil. Resolved once: a binary does
    /// not appear halfway through a session, and checking the filesystem on
    /// every settings redraw would be a lot of `stat` for a static answer.
    @Published var claudePath: String? = AppState.findClaude()

    /// Everywhere `claude` can be found without asking a shell.
    ///
    /// A binary named by hand wins outright: somebody who has typed a path has
    /// answered the question better than any search can, and silently ignoring
    /// them in favour of a guess would be worse than not offering the field.
    static func findClaude() -> String? {
        let manager = FileManager.default
        if let named = Prefs.claudePath, manager.isExecutableFile(atPath: named) {
            return named
        }
        if let found = ClaudeInvocation.candidates()
            .first(where: { manager.isExecutableFile(atPath: $0) }) {
            return found
        }
        // The version-manager layouts, whose directory names cannot be known in
        // advance because the version is in them. Newest last is not worth
        // sorting for: any of them is a working `claude`.
        for parent in ClaudeInvocation.versionedParents(home: NSHomeDirectory()) {
            let versions = (try? manager.contentsOfDirectory(atPath: parent)) ?? []
            for version in versions.sorted() {
                let path = ClaudeInvocation.versionedCandidate(parent: parent, version: version)
                if manager.isExecutableFile(atPath: path) { return path }
            }
        }
        return nil
    }

    /// The last resort: ask the developer's own shell where `claude` is.
    ///
    /// A GUI-launched app inherits a `PATH` of `/usr/bin:/bin:/usr/sbin:/sbin`
    /// and nothing else, so every version manager is invisible to it — but the
    /// shell that starts when they open a terminal knows, because their own
    /// rc files set it up. Run as login *and* interactive: nvm and mise are
    /// conventionally initialised in `.zshrc`, which a login shell alone does
    /// not read.
    ///
    /// Only ever called when everything cheaper has failed, and only once.
    /// Timed out rather than trusted: this is somebody else's shell profile and
    /// it is entitled to be slow, but not to hang a launch.
    func resolveClaudeFromLoginShell() async {
        guard claudePath == nil else { return }
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        guard FileManager.default.isExecutableFile(atPath: shell) else { return }

        let result = try? await ProcessRunner.run(
            executable: shell, arguments: ["-ilc", "command -v claude"], timeout: 15)
        // The last usable line, because an rc file is free to print whatever it
        // likes before the answer and plenty of them do.
        let found = (result?.stdout ?? "")
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }
        if let found {
            claudePath = found
            Log.debug("found claude via login shell: \(found)")
        }
    }

    /// Everything the feature needs before it can do anything.
    var canAutoReview: Bool {
        claudePath != nil && ReviewSkill.normalized(reviewSkillDraft) != nil
    }

    /// The room's switch.
    ///
    /// It refuses to turn on without a skill to run, and it can do that quietly
    /// because of where it now lives: the field it is complaining about is two
    /// rows below it, already wearing its own warning. The header button used
    /// to be this control and had to open Settings to explain itself; giving
    /// automatic review a room of its own is what made that unnecessary.
    func toggleAutoReview() {
        autoReviewEnabled = autoReviewEnabled ? false : canAutoReview
    }

    func commitReviewSkill() {
        if let skill = ReviewSkill.normalized(reviewSkillDraft) {
            Prefs.reviewSkill = skill
        }
        reviewSkillDraft = Prefs.reviewSkill ?? ""
        // A feature with nothing to run must not sit there claiming to be on.
        if !canAutoReview { autoReviewEnabled = false }
    }

    /// Whether anything typed is waiting to be applied.
    ///
    /// Only the typed fields can be pending. Switches and pickers write through
    /// the moment they are touched — that is this platform's convention and the
    /// room keeps it — so they are never unsaved and never light this up.
    var hasPendingSettings: Bool {
        updateRepoDraft != Prefs.updateRepo
            || reviewSkillDraft != (Prefs.reviewSkill ?? "")
    }

    /// Applies every pending field. Same path the fields take on Return and on
    /// losing focus, so the button can never mean something they do not.
    func saveSettings() {
        commitUpdateRepo()
        commitReviewSkill()
    }

    /// Accepts the draft if it names a repo, and otherwise puts back whatever
    /// is actually stored — so leaving the field never silently breaks the
    /// update check.
    func commitUpdateRepo() {
        if let repo = ReleaseSource.normalized(updateRepoDraft) {
            Prefs.updateRepo = repo
        }
        updateRepoDraft = Prefs.updateRepo
    }

    /// Whether the badge has been dragged away from the size it follows by
    /// default, which is the only time resetting it does anything.
    var hasCustomBadgeSize: Bool { badgeTileSize != Layout.dockTileSize }

    /// The running build, for the settings footer. There is no About window and
    /// no menu bar item, so without this the version is not visible anywhere.
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "dev"
    }

    /// Mascot cycles since the drawer was last opened.
    ///
    /// Not persisted, and reset on every open: `Carousel` is for sitting
    /// there clicking the thing, and ten clicks spread over ten weeks is not
    /// that.
    @Published var mascotCycles = 0

    /// What the drawer is actually showing below the header.
    var activeSurface: DrawerSurface {
        room?.surface ?? DrawerSurface(selectedTab)
    }

    var trophyRows: [[Trophy]] { TrophyGrid.rows() }

    var settingsSections: [SettingsSection] { SettingsSection.allCases }
    var reviewSections: [ReviewSection] { ReviewSection.allCases }

    /// The review room's footer line: on or off, and what it has done.
    ///
    /// Counts the *posted* records against the rows currently waiting, which is
    /// the only honest denominator — the log remembers pings that have long
    /// since left the list, and "12 reviewed" next to a drawer holding two
    /// would be a number about nothing on screen.
    var reviewSummary: String {
        guard autoReviewEnabled else {
            return canAutoReview ? "Off" : "Off — nothing to run"
        }
        if let key = reviewInFlight,
           let running = items.first(where: { $0.pingKey == key }) {
            return "Reviewing \(running.repoShortName)#\(running.number)"
        }
        let waiting = items.filter { autoReviewLog[$0.pingKey]?.status == .posted }.count
        guard waiting > 0 else { return "On · \(reviewRepos.count) repos" }
        return waiting == 1
            ? "On · 1 review waiting on you"
            : "On · \(waiting) reviews waiting on you"
    }

    var trophyProgress: String {
        TrophyGrid.progress(unlocked: trophyState.unlockedIDs)
    }

    /// Opening the shelf is what counts as having looked at it. Every other
    /// room simply opens.
    /// Which trophies to mark as new *while the shelf is open*.
    ///
    /// Opening the room has always cleared `unseen` — that is what takes the
    /// dot off the button, and it should, because you have now seen them. But
    /// clearing it on the way in left nothing for the shelf itself to point at:
    /// the room knew something was new right up until the moment you could have
    /// looked. This holds the answer for the length of the visit.
    ///
    /// Not persisted. It is a fact about this visit, not about the shelf.
    @Published private(set) var newTrophies: Set<String> = []

    func open(_ room: DrawerRoom) {
        let leavingShelf = self.room == .trophies && room != .trophies
        self.room = room
        if room == .trophies {
            // Captured before clearing, so the room can still say which.
            if trophyState.hasUnseen {
                newTrophies = trophyState.unseen
                trophyState.markAllSeen()
            }
        } else if leavingShelf {
            newTrophies = []
        }
    }

    /// Enters `room`, or leaves it if it is already the one open.
    ///
    /// A toggle because each room has exactly one way in, so that control has
    /// to be the way out too — the X beside it shuts the whole drawer, which is
    /// a different thing to want. Opening one room from inside another simply
    /// replaces it, which is what makes the gear and the trophy reachable from
    /// each other rather than only from the drawer.
    func toggle(_ room: DrawerRoom) {
        if self.room == room {
            if room == .trophies { newTrophies = [] }
            self.room = nil
        } else {
            open(room)
        }
    }

    /// Whether this trophy was unlocked since the shelf was last looked at.
    func isNew(_ id: TrophyID) -> Bool { newTrophies.contains(id.rawValue) }

    /// The visit is over — by leaving the room, or by shutting the drawer on it.
    func endTrophyVisit() { newTrophies = [] }

    /// Measured height of each row, keyed by a surface-namespaced row id.
    @Published var rowHeights: [String: CGFloat] = [:]

    /// Where inside each row the drawer may stop, keyed as the heights are.
    ///
    /// Offsets from a row's own top — the bottom edge of each comment or
    /// finding showing on it. Empty for a closed row, which is then a single
    /// stop exactly as before.
    @Published var rowCuts: [String: [CGFloat]] = [:]
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
        // The sleeping list is shown whole. The filters narrow the work you
        // are choosing between, and a row you have already chosen to put down
        // is not in that choice — hiding some of what you parked, behind a
        // filter you set for a different purpose, is how a row gets lost.
        if showingSnoozed { return sortOrder.apply(to: snoozedItems) }
        var filtered = effectiveReviewFilter.apply(to: awakeItems)
        if let author = authorFilter {
            filtered = filtered.filter { $0.authorLogin == author }
        }
        return sortOrder.apply(to: filtered)
    }

    /// The triage filter, or `.all` when nothing in scope could answer it.
    ///
    /// The same shape `effectiveMyPRFilter` uses for needs-lead: a filter
    /// whose control is not on screen must not still be narrowing the list
    /// behind it, or a preference set last week hides rows with nothing left
    /// to switch off.
    var effectiveReviewFilter: ReviewFilter {
        showsReviewFilter ? reviewFilter : .all
    }

    /// Whether the triage filter could hide anything in the list as it stands.
    /// Scoped by repository and account, like every other count in the bar.
    var showsReviewFilter: Bool { ReviewFilter.isUseful(on: awakeItems) }

    /// The rows in scope that are not asleep — what the list and the badge
    /// are both built from.
    var awakeItems: [ReviewItem] { snoozes.awake(scopedItems, now: clock) }

    /// The rows in scope that are. Counted so the bar can say so, because the
    /// one thing the badge must never be is silently short.
    var snoozedItems: [ReviewItem] { snoozes.asleep(scopedItems, now: clock) }

    var snoozedCount: Int { snoozedItems.count }

    /// Whether anything parked is about to come back.
    ///
    /// Read off the same clock the rows age by, so the character stirs on the
    /// tick that redraws them rather than on one of its own.
    var isWakingSoon: Bool {
        snoozedItems.contains { item in
            guard let wake = snoozes.wakeTime(for: item.pingKey) else { return false }
            return wake.timeIntervalSince(clock) <= Mood.stirringWindow
        }
    }

    /// When a row wakes, or nil if it is not asleep *now*.
    ///
    /// Asked rather than read straight off the store: a wake time that has
    /// already passed is still in there until the next prune, and a row back
    /// in the list wearing "wakes in 0m" would be describing a state it has
    /// already left.
    func wakeTime(for item: ReviewItem) -> Date? {
        guard snoozes.isAsleep(item.pingKey, now: clock) else { return nil }
        return snoozes.wakeTime(for: item.pingKey)
    }

    /// Puts a row down until `wake`, and tells the queue to leave it alone.
    func snooze(_ item: ReviewItem, until wake: Date) {
        snoozes.snooze(item.pingKey, until: wake)
    }

    /// Records that a row was opened. Called from the one place that opens
    /// one, so there is no second path that could forget to.
    func markOpened(_ item: ReviewItem) {
        var updated = opened
        updated.open(item.pingKey, at: Date())
        if updated != opened { opened = updated }
    }

    func wake(_ item: ReviewItem) {
        snoozes.wake(item.pingKey)
        // Nothing left to look at, so stop looking at it. The same rule the
        // author filter follows when its last pull request is reviewed: a
        // view that can only show an empty list clears itself rather than
        // leaving you staring at one.
        if snoozedItems.isEmpty { showingSnoozed = false }
    }

    /// Drops snoozes that have expired or whose pull request is gone.
    ///
    /// `complete` is false when the round could not reach every account, and
    /// then only the expired half runs — pruning against a partial list would
    /// quietly wake every row belonging to the account that was unreachable.
    func pruneSnoozes(complete: Bool) {
        let known = complete ? Set(items.map(\.pingKey)) : nil
        var pruned = snoozes
        pruned.prune(known: known, now: clock)
        if pruned != snoozes { snoozes = pruned }
        if showingSnoozed && snoozedItems.isEmpty { showingSnoozed = false }

        // Same round, same rule. A pull request that has left the fetch has
        // been reviewed, merged or closed, and there is nothing left to
        // remember about having opened it.
        var stillOpen = opened
        stillOpen.prune(known: known)
        if stillOpen != opened { opened = stillOpen }
    }

    /// The My PRs list as the drawer actually lays it out: lone PRs and stack
    /// groups, in display order.
    ///
    /// This is the choke point, not `displayedMyPRs` — the drawer sizes itself
    /// by summing one measured height per *unit*, and a group is one unit
    /// however many PRs are in it.
    var displayedMyPRUnits: [MyPRUnit] {
        // `scopedMyPRs` rather than the repo filter alone: an account is a
        // scope in the same sense a repo is, and a stack half of which belongs
        // to an identity you have scoped away is not a stack you are looking at.
        let filtered = effectiveMyPRFilter.apply(to: scopedMyPRs)
        // Grouping is what the pancake button is *for*. Everywhere else the
        // list stays a flat list of PRs, exactly as it was — a plate and a
        // column of pancakes is a lot of furniture to impose on someone who
        // asked to see their failing checks.
        guard myPRStackedOnly else {
            return myPRSortOrder.apply(to: filtered).map(MyPRUnit.single)
        }
        // Grouped *then* narrowed to groups, rather than filtering PRs on
        // `isStacked`: that flag is computed against the whole inbox, so it
        // would keep a PR whose partner a scope has already hidden — a stack
        // of one, which is not a stack.
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

    /// Every repo seen, paired with the host it was seen on.
    ///
    /// Deliberately *not* account-scoped, unlike `repos`: this backs the leads
    /// editor, and leads are a standing decision about a repository rather
    /// than a view of today's list. Scoping it would hide a repo's leads
    /// behind whichever identity happened to be selected, and editing them
    /// would mean remembering to switch accounts first.
    var leadRepos: [RepoRef] {
        let seen = items.map { ($0.repo, $0.account) } + myPRs.map { ($0.repo, $0.account) }
        var refs: Set<RepoRef> = []
        for (repo, account) in seen {
            refs.insert(RepoRef(repo: repo, host: Accounts.host(ofID: account)))
        }
        return RepoRef.sorted(Array(refs))
    }

    /// An account that can read `host`, for the member search.
    ///
    /// The active account's token is the wrong one to reach for now: the repo
    /// being edited may belong to the other identity entirely, and searching
    /// an Enterprise repo with a github.com token returns nothing rather than
    /// failing — which reads as "this repo has no members".
    func account(forHost host: String) -> Account? {
        accounts.first { $0.host == host && $0.isHealthy } ?? accounts.first { $0.host == host }
    }

    func repoCount(_ repo: String) -> (reviews: Int, mine: Int) {
        (RepoScope.apply(repo, to: accountScopedItems, repoOf: \.repo).count,
         RepoScope.apply(repo, to: accountScopedMyPRs, repoOf: \.repo).count)
    }

    /// What switching to this account would show you **in the tab you are
    /// looking at**, ignoring the repo filter so the strip always reveals what
    /// is there rather than what the current repo leaves of it.
    ///
    /// Follows the selected tab rather than always counting review requests.
    /// Counting one thing while the tab below counts another put "0" beside an
    /// account with eighteen open pull requests, which reads as "nothing here"
    /// — a number whose meaning you have to already know is worse than no
    /// number, and this app's whole badge is built on the opposite rule.
    /// Both tabs' counts for one account, the way the repo menu reports a repo.
    ///
    /// Two numbers rather than `accountCount`'s one, because that answers for
    /// whichever tab is showing and the settings room has no tab — a single
    /// number there would silently mean "reviews" or "mine" depending on where
    /// the drawer happened to be before it was opened.
    func accountCounts(_ id: String) -> (reviews: Int, mine: Int) {
        (AccountScope.apply(id, to: items, accountOf: \.account).count,
         AccountScope.apply(id, to: myPRs, accountOf: \.account).count)
    }

    /// What is wrong with an account, or nil when nothing is.
    ///
    /// Ordered by what the user can act on first: a token `gh` already knows is
    /// bad is a login away from working, a round that failed may simply be the
    /// network, and a missing scope is a standing choice they may have made.
    func accountProblem(_ account: Account) -> String? {
        if !account.isHealthy { return "Needs `gh auth login`" }
        if failedAccounts.contains(account.id) { return "Could not be read this refresh" }
        if account.canReadTeams == false { return "No read:org — team reviews will not appear" }
        return nil
    }

    func accountCount(_ id: String?) -> Int {
        switch selectedTab {
        case .reviews: return AccountScope.apply(id, to: items, accountOf: \.account).count
        case .mine: return AccountScope.apply(id, to: myPRs, accountOf: \.account).count
        }
    }

    /// Drops a repo filter that matches nothing for the current account scope.
    ///
    /// Lives here rather than in the refresh loop because there are now two
    /// ways to invalidate it — a refresh, and an account switch — and a rule
    /// with two triggers and one implementation cannot drift between them.
    func dropStaleRepoFilter() {
        guard !repoFilter.isEmpty else { return }
        let live = repoFilter.filter { repo in
            let counts = repoCount(repo)
            return counts.reviews > 0 || counts.mine > 0
        }
        // Name by name. With three repositories picked and one of them
        // finished, the other two are still exactly what was asked for, and
        // clearing the whole scope because part of it went stale would throw
        // away a choice that is still good.
        if live != repoFilter { repoFilter = live }
    }

    /// The account to name on a row, or nil when naming it would be noise:
    /// only one account exists, the list is already scoped to one, or the row
    /// predates the tag.
    func accountLabel(for id: String) -> String? {
        guard showsAccountPicker, accountFilter == nil else { return nil }
        guard let account = accounts.first(where: { $0.id == id }),
              !account.login.isEmpty
        else { return nil }
        return Accounts.shortLogin(account.login)
    }

    static func shortRepoName(_ repo: String) -> String { RepoScope.shortName(repo) }

    var isRepoFiltered: Bool { !repoFilter.isEmpty }
    var isFiltered: Bool { authorFilter != nil }
    var isReviewFiltered: Bool { effectiveReviewFilter != .all }
    var isMyPRFiltered: Bool { effectiveMyPRFilter != .all || myPRStackedOnly }

    /// Reviewers holding more than one of your pull requests. See `ReviewerLoad`.
    ///
    /// Built from the scoped list rather than all of them, so it agrees with
    /// the rows underneath it — a roll-up over work a repo filter is hiding
    /// would be a line about pull requests that are not on screen.
    var reviewerLoads: [ReviewerLoad] { ReviewerLoad.build(from: scopedMyPRs) }

    /// Whether any PR belongs to a repo with leads configured.
    var hasLeadGate: Bool { myPRs.contains(where: \.hasLeadGate) }

    /// "Needs lead" means nothing until a lead is configured, so it is
    /// neither offered nor applied then.
    var effectiveMyPRFilter: MyPRFilter {
        myPRFilter == .needsLead && !hasLeadGate ? .all : myPRFilter
    }

    var availableMyPRFilters: [MyPRFilter] {
        MyPRFilter.allCases.filter { $0 != .needsLead || hasLeadGate }
    }

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
        // The number of *stops*, which is no longer the number of pull
        // requests: a row with its findings or threads open is split into one
        // stop per thing showing. `max` rather than the measured count alone,
        // so a list that has not reported yet still gets a boundary per row
        // from the estimates.
        case .reviews: return max(displayedItems.count, rowHeights(for: .reviews).count)
        case .mine: return max(displayedMyPRs.count, rowHeights(for: .mine).count)
        // A grid row, not a trophy. The drawer snaps to what the eye reads as
        // a line, and nobody reads a shelf a trophy at a time.
        case .trophies: return trophyRows.count
        // A group, not a control. Snapping to individual toggles would let the
        // drawer settle between a section's header and the first thing under
        // it, which reads as a heading for nothing.
        // A shelf, not a character: the drawer snaps to what the eye reads
        // as a group, and nobody reads a cast one face at a time.
        case .mascots: return MascotGrid.shelves.count
        case .settings: return SettingsSection.allCases.count
        case .review: return ReviewSection.allCases.count
        }
    }

    /// Measured heights of a tab's rows, in display order.
    func rowHeights(for surface: DrawerSurface) -> [CGFloat] {
        switch surface {
        case .reviews:
            // `map` with a fallback, not `compactMap`. Dropping the rows that
            // have not reported yet shortens the array, and the sizing reads it
            // positionally — so row 2's measurement was being used as row 1's,
            // and the list came out the wrong height whenever a row in the
            // middle of it had not been drawn yet. Keeping every position and
            // filling the gaps with the estimate is what makes the index mean
            // what the sizing thinks it means.
            return displayedItems.flatMap { item -> [CGFloat] in
                let key = rowKey(.reviews, item.id)
                guard let measured = rowHeights[key] else {
                    return [Layout.estimatedRowHeight(for: .reviews)]
                }
                return segments(of: measured, key: key)
            }
        case .mine:
            return MyPRGrouping.stopHeights(
                units: displayedMyPRUnits,
                stackChrome: Layout.stackGroupPadding * 2,
                height: { rowHeights[rowKey(.mine, $0.id)] },
                segments: { item, measured in
                    segments(of: measured, key: rowKey(.mine, item.id))
                })
        case .trophies:
            return trophyRows.indices.compactMap {
                rowHeights[rowKey(.trophies, TrophyGrid.rowID($0))]
            }
        case .mascots:
            return MascotGrid.shelves.compactMap {
                rowHeights[rowKey(.mascots, MascotGrid.shelfID($0.cohort))]
            }
        case .settings:
            return SettingsSection.allCases.compactMap {
                rowHeights[rowKey(.settings, $0.id)]
            }
        case .review:
            return ReviewSection.allCases.compactMap {
                rowHeights[rowKey(.review, $0.id)]
            }
        }
    }

    /// One row, split into the pieces the drag may land between.
    ///
    /// The row itself when nothing on it is open, which is every row on four of
    /// the six surfaces and most rows on the other two.
    private func segments(of measured: CGFloat, key: String) -> [CGFloat] {
        guard let cuts = rowCuts[key], !cuts.isEmpty else { return [measured] }
        return RowSegments.split(height: measured, cuts: cuts,
                                 spacing: Layout.rowSpacing)
    }

    var activeRowCount: Int { rowCount(for: activeSurface) }
    var activeRowHeights: [CGFloat] { rowHeights(for: activeSurface) }

    var userContentHeight: CGFloat? {
        // A self-sizing surface has no dragged height, even if one was stored
        // before it became self-sizing — an old value must not outlive the
        // behaviour that produced it.
        get { activeSurface.fitsContent ? nil : userContentHeights[activeSurface] }
        set {
            if let newValue {
                userContentHeights[activeSurface] = newValue
            } else {
                userContentHeights.removeValue(forKey: activeSurface)
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
    ///
    /// Sleeping rows are not in it either. The badge answers *what is waiting
    /// on me*, and a pull request deliberately parked until Monday is not
    /// waiting on you now — going on nagging about it is the thing the snooze
    /// was pressed to stop. The drawer says how many are asleep whenever any
    /// are, so the number is never silently short.
    var count: Int { awakeItems.count }

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
    var showsAccountPicker: Bool { accounts.count > 1 }

    // MARK: - Mascot

    /// nil means the user turned the mascot off.
    @Published var mascot: MascotID? = Prefs.mascot {
        didSet {
            Prefs.mascot = mascot
            if let mascot { trophyState.record(TrophyFact.mascotSeen(mascot)) }
            // Choosing one of the new characters *is* reading the
            // announcement. Leaving the banner up over a drawer already
            // showing what it advertises is the app talking past the user.
            if let mascot, mascot != oldValue,
               Mascot.named(mascot).cohort.rawValue == NewCastNotice.acknowledgement {
                dismissCastNotice()
            }
        }
    }

    /// The cohort whose arrival has already been announced, or nil.
    ///
    /// Published so dismissing the banner re-lays the drawer out: the panel is
    /// framed from a height that counts the strip, and a dismissal the state
    /// does not announce leaves the window 52pt taller than what is in it.
    @Published var seenCastNotice: String? = Prefs.seenCastNotice {
        didSet { Prefs.seenCastNotice = seenCastNotice }
    }

    /// Whether the drawer is carrying the arrival banner.
    var showsCastNotice: Bool {
        NewCastNotice.shouldShow(acknowledged: seenCastNotice)
    }

    /// Who the banner is announcing.
    var castNoticeVisitors: [MascotID] { NewCastNotice.visitors }

    /// What the room and the picker call the shelf of characters this build
    /// did not ship — whoever is signed in, since they are the one who made
    /// them. Falls back when no account has answered yet: a heading that says
    /// "nil" is worse than a generic one.
    var customCohortTitle: String {
        guard let login = accounts.first?.login, !login.isEmpty else {
            return "Your Mascots"
        }
        return "\(login) Mascots"
    }

    func dismissCastNotice() {
        seenCastNotice = NewCastNotice.acknowledgement
    }

    /// A transient reaction that outranks the derived mood while it lasts.
    /// Event-driven only — a review arriving. Pointer state is tracked
    /// separately below.
    @Published var reaction: Reaction?

    /// Pointer state, kept as facts rather than written straight into
    /// `reaction`.
    ///
    /// Hover and press arrive as independent events, so last-write-wins gets
    /// it wrong in both directions: releasing a drag while the pointer is
    /// still over the badge would clear the hover too, and a hover-out
    /// arriving mid-drag would cancel the press. Holding both and ranking
    /// them means neither event has to know what the other is doing.
    @Published var isHoveringBadge = false
    @Published var isPressingBadge = false

    /// What the character is reacting to, most urgent first: a hand on it
    /// beats a ping, and a ping beats a pointer merely resting on it.
    var activeReaction: Reaction? {
        Reaction.resolve(pressed: isPressingBadge,
                         event: reaction,
                         hovering: isHoveringBadge)
    }

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
                hasProblem: hasProblem,
                snoozed: snoozedCount,
                wakingSoon: isWakingSoon)
    }

    /// What the character is actually drawn as right now.
    var spriteStyle: SpriteStyle {
        activeReaction?.style(tint: mood.style.health) ?? mood.style
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
        mascotCycles += 1
    }

    /// What the next click lands on, for the tooltip.
    var nextMascotName: String? {
        MascotID.next(after: mascot).map { Mascot.named($0).name } ?? "no mascot"
    }

    /// One-shot reaction, used when a new review lands. Cancels any previous
    /// one so two pings in quick succession do not leave it stuck.
    private var startleTask: Task<Void, Never>?

    /// One beat of applause for a pull request of yours going in.
    ///
    /// Shares `startle`'s machinery and its length, because they are the same
    /// kind of event: news about one thing, over in under a second, and then
    /// back to whatever the queue actually says.
    func cheer() {
        guard mascot != nil else { return }
        startleTask?.cancel()
        reaction = .cheered
        startleTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.reaction = nil
        }
    }

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
    /// Never hidden on a short round. Hiding on a partial result would state
    /// "nothing is waiting on you" on the strength of accounts that were never
    /// read — the single reading this whole feature exists to prevent — and it
    /// would take the badge, and with it the only way back in, off the screen.
    /// Whether the panel should be off screen.
    ///
    /// Two clauses, and no opinion about your workload. It used to also go when
    /// both lists were empty — see `Prefs.widgetVisible` for why that is gone.
    ///
    /// `!expanded` stays: an open drawer is never taken away from under you,
    /// whatever the switch says, because hiding is about passive presence and a
    /// drawer somebody is reading is not passive. It is also what lets Settings
    /// be opened from the menu while the widget is turned off.
    var shouldHidePanel: Bool {
        !widgetVisible && !expanded
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
