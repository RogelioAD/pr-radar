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
    func setFinding(_ id: String, on item: ReviewItem, selected: Bool) {
        guard var record = autoReviewLog[item.pingKey],
              let index = record.prepared.firstIndex(where: { $0.id == id })
        else { return }
        record.prepared[index].isSelected = selected
        autoReviewLog[item.pingKey] = record
    }

    /// Ticks or unticks a whole tier at once — the "all three nits, actually"
    /// case, which is otherwise three presses in a narrow drawer.
    func setTier(_ tier: FindingTier, on item: ReviewItem, selected: Bool) {
        guard var record = autoReviewLog[item.pingKey] else { return }
        for index in record.prepared.indices where record.prepared[index].tier == tier {
            record.prepared[index].isSelected = selected
        }
        autoReviewLog[item.pingKey] = record
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
        var filtered = scopedItems
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
        guard let repo = repoFilter else { return }
        let counts = repoCount(repo)
        if counts.reviews == 0 && counts.mine == 0 { repoFilter = nil }
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

    var isRepoFiltered: Bool { repoFilter != nil }
    var isFiltered: Bool { authorFilter != nil }
    var isMyPRFiltered: Bool { effectiveMyPRFilter != .all || myPRStackedOnly }

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
        case .reviews: return displayedItems.count
        case .mine: return displayedMyPRs.count
        // A grid row, not a trophy. The drawer snaps to what the eye reads as
        // a line, and nobody reads a shelf a trophy at a time.
        case .trophies: return trophyRows.count
        // A group, not a control. Snapping to individual toggles would let the
        // drawer settle between a section's header and the first thing under
        // it, which reads as a heading for nothing.
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
            return displayedItems.map {
                rowHeights[rowKey(.reviews, $0.id)]
                    ?? Layout.estimatedRowHeight(for: .reviews)
            }
        case .mine:
            return MyPRGrouping.stopHeights(
                units: displayedMyPRUnits,
                stackChrome: Layout.stackGroupPadding * 2,
                height: { rowHeights[rowKey(.mine, $0.id)] })
        case .trophies:
            return trophyRows.indices.compactMap {
                rowHeights[rowKey(.trophies, TrophyGrid.rowID($0))]
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
    var showsAccountPicker: Bool { accounts.count > 1 }

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
    var shouldHidePanel: Bool {
        items.isEmpty && myPRs.isEmpty && !hasProblem && !isPartial
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
