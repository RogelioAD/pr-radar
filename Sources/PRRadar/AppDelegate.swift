import AppKit
import Network
import SwiftUI
import PRRadarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let state = AppState()
    private let notifier = Notifier()
    private var panel: PanelController!
    private let banner = AchievementBanner()
    /// The review count at the last refresh, so a queue reaching zero can be
    /// told from a queue that was already there. nil until the first refresh
    /// lands: launching into an empty queue is not an achievement.
    private var lastReviewCount: Int?
    /// Pull requests ever merged, from the count query. nil until it answers,
    /// which the rules read as *unknown* rather than as none.
    private var mergedLifetime: Int?
    private var pollTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    /// Guards the release check the way `isRefreshing` guards the PR fetch.
    /// Needed now that a manual press no longer rides the PR fetch's guard:
    /// the six-hour timer and a press can otherwise overlap, and two checks
    /// racing both read the old `notifiedUpdate` and both notify.
    private var isCheckingForUpdate = false

    /// Discovered once per launch and reused for every poll.
    /// Viewer login and teams per account id. One entry per identity, because
    /// the teams that decide which review requests are yours are a property of
    /// the account, not of the machine.
    private var viewerCache: [String: (login: String, teams: [TeamRef])] = [:]

    private let pathMonitor = NWPathMonitor()
    /// Assumed true until the monitor says otherwise, so a slow first callback
    /// cannot swallow the launch fetch.
    private var isOnline = true

    /// Low Power Mode is the user asking for less background work, and a review
    /// request is not worth overruling that for — the drawer's Refresh is still
    /// immediate either way.
    private var pollInterval: Duration {
        ProcessInfo.processInfo.isLowPowerModeEnabled ? .seconds(300) : .seconds(60)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.debug("applicationDidFinishLaunching")
        // The system's tooltip delay is tuned for hints you can do without.
        // Here a tooltip is the *only* label a trophy has — the grid is
        // deliberately captionless — so waiting out the default reads as the
        // app having nothing to say rather than as it being discreet.
        //
        // Registered rather than set, so it lives in the registration domain:
        // anyone who has chosen their own `NSInitialToolTipDelay` keeps it.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
        guard !anotherCopyIsRunning() else {
            // Before any UI exists, so a duplicate never gets as far as
            // placing a panel.
            NSApp.terminate(nil)
            return
        }
        if let appearance = Log.forcedAppearance {
            NSApp.appearance = appearance
        }
        notifier.prepare()

        panel = PanelController(state: state)
        panel.onOpen = { [weak self] item in
            NSWorkspace.shared.open(item.url)
            self?.panel.setExpanded(false)
        }
        panel.onOpenMyPR = { [weak self] item in
            NSWorkspace.shared.open(item.url)
            self?.panel.setExpanded(false)
        }
        panel.onRefresh = { [weak self] in self?.refreshNow() }
        panel.menuProvider = { [weak self] in self?.buildMenu() }
        panel.show()

        startNetworkMonitor()
        startPolling()
        startClock()
        startUpdateChecks()
    }

    /// A second copy is not a harmless spare: it restores the same saved badge
    /// origin and floats at the same window level, so the two panels land on
    /// exactly the same frame. Whichever the window server puts in front hides
    /// the other's count badges — the counters go first, being the part that
    /// overhangs the tile — and the order flips as windows are ordered front,
    /// which is what made it look intermittent.
    ///
    /// Returns false when unbundled, which is how `make run` starts it: there
    /// is no bundle identifier to match on, and a debug copy running alongside
    /// the installed one is deliberate.
    private func anotherCopyIsRunning() -> Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: identifier)
            .filter { $0.processIdentifier != mine }
        guard !others.isEmpty else { return false }
        Log.debug("already running as pid \(others.map(\.processIdentifier)); exiting")
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTask?.cancel()
        clockTask?.cancel()
        updateTask?.cancel()
        pathMonitor.cancel()
    }

    // MARK: - Polling

    /// Polling into a dead network just logs a failure a minute, and the
    /// interesting moment — coming back online — used to wait out the rest of
    /// the interval. Watching the path covers both.
    private func startNetworkMonitor() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let online = path.status == .satisfied
                defer { self.isOnline = online }
                Log.debug("network: \(online ? "online" : "offline")")
                // Reconnecting is worth a fetch immediately rather than at the
                // next tick: it is exactly when the list is most out of date.
                if online, !self.isOnline { await self.refresh() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.rogelioacosta.prradar.network"))
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                if self?.isOnline ?? true {
                    await self?.refresh()
                } else {
                    Log.debug("poll skipped: offline")
                }
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(60))
            }
        }
    }

    /// Re-renders relative timestamps between network polls.
    private func startClock() {
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.state.clock = Date()
            }
        }
    }

    /// Releases appear on the order of days, so this checks at launch and then
    /// every six hours rather than riding the 60-second PR poll.
    private func startUpdateChecks() {
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkForUpdate()
                try? await Task.sleep(for: .seconds(6 * 60 * 60))
            }
        }
    }

    private func checkForUpdate() async {
        guard !isCheckingForUpdate else { return }
        isCheckingForUpdate = true
        defer { isCheckingForUpdate = false }

        guard let token = try? Token.resolve() else { return }
        let repo = Prefs.updateRepo
        let current = Bundle.main
            .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String

        // Acted on the chip: the version now running is one this app once
        // told you about. Checked here rather than at launch because
        // `notifiedUpdate` is only ever written here, and the two readings
        // would otherwise be a launch apart.
        if let current, let running = AppVersion(current),
           let announced = Prefs.notifiedUpdate.flatMap(AppVersion.init),
           running >= announced {
            state.trophyState.record(TrophyFact.installedOfferedUpdate)
        }

        do {
            let release = try await GitHubClient(token: token).fetchLatestRelease(repo: repo)
            let status = UpdateCheck.evaluate(current: current,
                                              latestTag: release?.tagName,
                                              releaseURL: release?.url)
            state.updateStatus = status
            Log.debug("update check: current=\(current ?? "?") "
                      + "latest=\(release?.tagName ?? "none") -> \(status)")

            // Announce a given version once, not every six hours.
            if case .available(let version, let url) = status,
               Prefs.notifiedUpdate != version.description {
                Prefs.notifiedUpdate = version.description
                notifier.notifyUpdate(version: version.description, url: url)
            }
            panel.refreshLayoutIfExpanded()
        } catch {
            // Leaves the status at whatever it was: a failed check must not
            // claim the app is current.
            Log.debug("update check failed: \(error)")
        }
    }

    /// Pressing Refresh also looks for a new PR Radar release, so there is a
    /// way to ask on demand rather than waiting out the six-hour timer. The
    /// background poll deliberately does not: it runs every 60 seconds, and
    /// releases do not appear that often.
    ///
    /// The two run as separate awaits rather than one combined pass because
    /// `refresh` drops out early when a poll is already in flight. Folding the
    /// release check into it meant a press landing in that window was a silent
    /// no-op — and a manual press is exactly when someone is watching for an
    /// answer. Each now guards only itself.
    private func refreshNow() {
        Task {
            await refresh()
            await checkForUpdate()
        }
    }

    private func refresh() async {
        guard !state.isRefreshing else { return }
        state.isRefreshing = true
        defer { state.isRefreshing = false }

        // Off the main actor: discovery runs `gh auth status`, which validates
        // every token over the network to report its state. Synchronously on
        // the main thread that is a beachball on every poll, where the old code
        // made one fast local call.
        let accounts = Self.padded(await Task.detached { Accounts.discover() }.value)
        state.accounts = accounts
        validateAccountFilter(against: accounts)

        // Sequential rather than concurrent. Each account is a couple of round
        // trips on a background poll, and doing them in turn keeps the viewer
        // cache a plain dictionary touched only from this actor. Worth
        // parallelising if anyone runs enough accounts to feel it.
        var fetches: [AccountFetch] = []
        for account in accounts {
            fetches.append(await fetch(account))
        }

        let reachable = fetches.filter { $0.error == nil }

        // Every account failing is the old total-failure case: keep the last
        // known list rather than blanking out on a transient network problem.
        // Some failing is different in kind — the lists below are real, just
        // short — and is carried by failedAccounts instead.
        guard !reachable.isEmpty else {
            let message = fetches.compactMap(\.error).first ?? "No GitHub account available."
            Log.debug("refresh failed for every account: \(message)")
            // The list left standing is the previous round's, and that one was
            // whole. Marking accounts here would put "…" against a total that
            // is complete and merely a minute old, which is a different fault
            // with a different remedy.
            state.failedAccounts = []
            state.lastError = message
            if state.items.isEmpty {
                state.authError = message
                panel.syncVisibility()
            }
            return
        }

        // Marked after the all-failed case above, which is not a short round.
        state.failedAccounts = Set(fetches.filter(\.isShort).map(\.account.id))

        let items = AccountMerge.merge(reachable.map(\.items))
        // An account whose pull requests could not be read keeps the ones it
        // contributed last round. Replacing them with nothing would turn a
        // transient failure into "you have no open PRs", which is what this
        // code path did before accounts were split out and is the behaviour
        // worth keeping.
        var mine = AccountMerge.merge(reachable.map {
            $0.myPRs ?? previousMyPRs(for: $0.account)
        })
        // After the merge rather than inside each account's fetch: there is one
        // longest stack across the lists the drawer shows, not one per identity.
        if Log.fakeStacks { mine = Self.splittingTheLongestStack(mine) }

        // Summed across the accounts that answered, and left nil when none did.
        // A partial sum under-reports, which costs at most a late trophy; a zero
        // standing in for "did not answer" would instead read as a real count
        // and tell the rules the viewer has never merged anything.
        let counted = reachable.compactMap(\.merged)
        mergedLifetime = counted.isEmpty ? nil : counted.reduce(0, +)

        Log.debug("refresh ok: \(items.count) items from \(reachable.count)/\(accounts.count) account(s)")
        state.authError = nil
        // The first account's failure, so a partial round still names one cause.
        // The count of what failed lives in failedAccounts; this is the wording.
        state.lastError = fetches.compactMap(\.error).first
        state.items = items
        // Drop measurements for rows that are gone, and an author filter
        // whose author no longer has anything waiting — otherwise the
        // drawer would sit empty next to a non-zero badge.
        state.rowHeights = RowHeightKeys.pruned(state.rowHeights,
                                                surface: .reviews,
                                                liveIDs: Set(items.map(\.id)))
        if let author = state.authorFilter,
           !items.contains(where: { $0.authorLogin == author }) {
            state.authorFilter = nil
        }
        state.clock = Date()
        state.lastUpdated = Date()

        // The one edge worth a reaction: something new landed while you
        // were not looking.
        if notifier.notifyNewPings(in: items) { state.startle() }

        state.rowHeights = RowHeightKeys.pruned(state.rowHeights,
                                                surface: .mine,
                                                liveIDs: Set(mine.map(\.id)))
        state.myPRs = mine
        validateRepoFilter()
        Log.debug("my PRs: \(mine.count), ready to merge: \(state.myPRsReadyToMerge)")

        // Once both tabs have landed, never between them: a third of the rules
        // read the review queue, a third read your own pull requests, and three
        // read both.
        evaluateTrophies()

        panel.refreshLayoutIfExpanded()
        panel.refreshBadgeSize()
        panel.syncVisibility()
        if Log.startExpanded && !(items.isEmpty && state.myPRs.isEmpty) {
            panel.setExpanded(true)
        }
    }

    // MARK: - Per-account fetch

    /// One account's contribution to the two lists, kept whole until every
    /// account has reported.
    ///
    /// The error is carried rather than thrown because a failure here is not a
    /// failure of the refresh: the other accounts' rows are still good, and the
    /// only wrong answer is to discard them or to present what is left as
    /// complete.
    private struct AccountFetch {
        let account: Account
        var items: [ReviewItem] = []
        /// nil when this half could not be fetched — which is not the same as
        /// fetching it and finding none, and must not be stored as if it were.
        var myPRs: [MyPullRequest]?
        /// Lifetime merged count, which the trophy rules read. nil when this
        /// account did not answer — distinct from zero, which is a real count.
        var merged: Int?
        var error: String?

        /// Whether this account's contribution is short, for any reason. An
        /// account can be perfectly reachable and still return half a round.
        var isShort: Bool { error != nil || myPRs == nil }
    }

    private func fetch(_ account: Account) async -> AccountFetch {
        guard account.isHealthy else {
            // gh already knows this token is bad, so there is nothing to learn
            // from spending a round trip to be told again.
            return AccountFetch(account: account,
                                error: "\(account.login.isEmpty ? "This account" : account.login) needs `gh auth login`.")
        }
        guard let token = Accounts.token(for: account) else {
            // The empty login is the no-`gh` machine, where the only useful
            // thing to say names both ways of supplying a token.
            return AccountFetch(account: account,
                                error: account.login.isEmpty
                                    ? TokenError.notFound.localizedDescription
                                    : "No token for \(account.login). Run `gh auth login`.")
        }

        if Log.failAccount == account.login {
            return AccountFetch(account: account,
                                error: "forced failure (PRRADAR_FAIL_ACCOUNT)")
        }

        let client = GitHubClient(token: token)
        do {
            let viewer: (login: String, teams: [TeamRef])
            if let cached = viewerCache[account.id] {
                viewer = cached
            } else {
                let discovered = try await client.fetchViewerAndTeams()
                viewer = (discovered.login, discovered.teams)
                viewerCache[account.id] = viewer
            }

            let searches = try await client.fetchPullRequests(teams: viewer.teams)
            let inbox = ReviewInbox(viewerLogin: viewer.login, teams: viewer.teams)
            var result = AccountFetch(account: account,
                                      items: tagged(inbox.build(from: searches), with: account))

            // The My PRs half is independently fallible: losing it must not cost
            // the review requests this account already returned.
            do {
                guard Log.failAccount != "mine" else {
                    throw TokenError.notFound  // any error; the path is what matters
                }
                result.myPRs = tagged(try await fetchMyPRs(client: client, host: account.host),
                                      with: account)
            } catch {
                // Left nil deliberately. The account stays reachable — its
                // review requests arrived — but it is short, so it is marked,
                // and the caller keeps this account's previous pull requests
                // rather than replacing them with nothing.
                Log.debug("my PRs fetch failed for \(account.id): \(error)")
            }
            result.merged = await fetchMergedCount(client: client)
            return result
        } catch {
            Log.debug("fetch failed for \(account.id): \(error)")
            return AccountFetch(account: account, error: error.localizedDescription)
        }
    }

    /// Works out what has been earned, and says so.
    ///
    /// Run once per refresh, after *both* tabs have landed: a third of the
    /// rules read the review queue, a third read your own pull requests, and
    /// three of them read both. Evaluating between the two fetches would give
    /// every rule a view of half a refresh.
    ///
    /// All the rules themselves live in `TrophyEvaluator`. This assembles
    /// what it is allowed to see and does what it says.
    private func evaluateTrophies() {
        // A forced shelf is a fiction, and evaluating against it would end
        // it: the backfill would fill an empty one on the first refresh,
        // which is the very state `none` exists to hold still.
        guard Log.fakeShelf == nil else { return }

        // The banner needs something to be earned, and most of what earns
        // one is not arrangeable on demand. This drops real ones on the first
        // refresh so they can be looked at. See `Log.fakeBanner`.
        if lastReviewCount == nil, !Log.fakeBanner.isEmpty {
            banner.show(Self.requestedBanners(Log.fakeBanner),
                        on: panel.currentScreen)
        }

        var snapshot = TrophySnapshot()
        snapshot.reviews = state.items
        snapshot.myPRs = state.myPRs
        snapshot.scopedReviewCount = state.count
        snapshot.previousScopedReviewCount = lastReviewCount
        snapshot.mergedLifetime = mergedLifetime
        snapshot.badgeTileSize = state.badgeTileSize
        // The reachable extremes, not the bounds. With a character drawn the
        // badge settles on whole device pixels and stops short of both — so
        // measured against the bounds, a badge dragged as far as it goes has
        // never once been at its largest or smallest.
        let reach = Layout.reachableBadgeTileRange(hasMascot: state.selectedMascot != nil,
                                                   backingScale: state.backingScale)
        snapshot.badgeMinimum = reach.minimum
        snapshot.badgeMaximum = reach.maximum
        snapshot.mascotCyclesThisSession = state.mascotCycles
        snapshot.now = Date()
        // From the same pref the update check watches, so a fork rewards
        // contributions to the fork rather than to the original.
        snapshot.homeRepo = Prefs.updateRepo
        lastReviewCount = state.count

        let (next, unlocked) = TrophyEvaluator.evaluate(snapshot, state: state.trophyState)
        state.trophyState = next
        guard !unlocked.isEmpty else { return }
        Log.debug("unlocked: \(unlocked.map(\.rawValue).joined(separator: ", "))")
        // Looking at the shelf is what marks it read. Doing it here as well
        // as on opening the room covers the case of something unlocking
        // while the room is already the thing on screen — the dot would
        // otherwise appear for trophies being looked at.
        if state.expanded, state.showingTrophies {
            state.trophyState.markAllSeen()
        }
        guard Prefs.celebrateCleared else { return }
        banner.show(unlocked, on: panel.currentScreen)
    }

    /// Resolves `PRRADAR_FAKE_BANNER` into trophies.
    ///
    /// Debug only. `many` expands past the banner's run limit so the summary
    /// form is reachable — that path is otherwise only seen on a first
    /// install, which is exactly once per machine.
    private static func requestedBanners(_ names: [String]) -> [TrophyID] {
        if names == ["many"] {
            return Trophy.all.prefix(8).map(\.id)
        }
        return names.compactMap { name in
            guard let id = TrophyID(rawValue: name) else {
                Log.debug("no trophy called '\(name)'")
                return nil
            }
            return id
        }
    }

    /// How many pull requests one account's viewer has ever merged.
    ///
    /// Swallowed on failure, like the My PRs fetch and for the same reason:
    /// a count that did not answer must read as *unknown* to the rules, not
    /// as zero — and certainly not as a reason to fail the refresh that
    /// carries both tabs.
    private func fetchMergedCount(client: GitHubClient) async -> Int? {
        do {
            return try await client.fetchMergedCount()
        } catch {
            Log.debug("merged count failed: \(error)")
            return nil
        }
    }

    /// Repeats the discovered account up to `PRRADAR_FAKE_ACCOUNTS`.
    ///
    /// Debug only. See `Log.fakeAccounts`. The copies are marked active so that
    /// `Accounts.token(for:)` falls back to the real token for them — without
    /// that they would every one of them fail to resolve, and the fake would
    /// only ever show the strip full of broken accounts rather than the working
    /// state it exists to produce.
    private static func padded(_ accounts: [Account]) -> [Account] {
        guard let want = Log.fakeAccounts, let real = accounts.first,
              accounts.count < want
        else { return accounts }
        let extra = (accounts.count..<want).map { index in
            Account(login: "\(real.login)-alt\(index)",
                    host: real.host,
                    isActive: true,
                    isHealthy: true,
                    scopes: real.scopes)
        }
        Log.debug("faking \(extra.count) extra account(s)")
        return accounts + extra
    }

    /// What this account contributed to the last round, kept when a fetch for
    /// it fails.
    private func previousMyPRs(for account: Account) -> [MyPullRequest] {
        state.myPRs.filter { $0.account == account.id }
    }

    private func tagged(_ items: [ReviewItem], with account: Account) -> [ReviewItem] {
        items.map { var copy = $0; copy.account = account.id; return copy }
    }

    private func tagged(_ prs: [MyPullRequest], with account: Account) -> [MyPullRequest] {
        prs.map { var copy = $0; copy.account = account.id; return copy }
    }

    /// One account's own pull requests.
    private func fetchMyPRs(client: GitHubClient,
                            host: String) async throws -> [MyPullRequest] {
        let result = try await client.fetchMyPullRequests()
        var mine = MyPRInbox(leads: Prefs.leadsByRepo, host: host).build(from: result)

        // Second phase, independently fallible: if it fails, behindBy stays
        // nil and the row shows "behind ?" rather than claiming "behind 0".
        do {
            let compares = try await client.fetchCompares(for: mine)
            mine = MyPRInbox.applyCompares(compares, to: mine)
        } catch {
            Log.debug("compare phase failed: \(error)")
        }

        if let fake = Log.fakeBehind {
            mine = mine.map { var copy = $0; copy.behindBy = fake; return copy }
        }
        if Log.fakeReady {
            mine = mine.map { var copy = $0; copy.mergeBlocker = .clean; return copy }
        }
        return mine
    }

    /// Drops a scope naming an account that is no longer logged in — otherwise
    /// logging out between launches leaves the drawer scoped to an identity it
    /// cannot read, which looks exactly like having nothing to do.
    private func validateAccountFilter(against accounts: [Account]) {
        guard let scope = state.accountFilter else { return }
        if !accounts.contains(where: { $0.id == scope }) {
            Log.debug("clearing stale account filter: \(scope)")
            state.accountFilter = nil
        }
    }

    /// Cuts the longest stack's middle link, turning one group into two.
    ///
    /// Debug only. See `Log.fakeStacks`.
    private static func splittingTheLongestStack(_ items: [MyPullRequest]) -> [MyPullRequest] {
        let stacks = MyPRGrouping.units(items, order: .newestFirst).compactMap { unit -> MyPRStack? in
            guard case .stack(let stack) = unit else { return nil }
            return stack
        }
        guard let longest = stacks.max(by: { $0.depth < $1.depth }),
              longest.depth >= 4 else { return items }
        let cut = longest.members[longest.depth / 2]
        return items.map { item in
            var copy = item
            if copy.id == cut.id { copy.stackedOn = nil }
            if copy.repo == cut.repo { copy.blocksRestackOf.removeAll { $0 == cut.number } }
            return copy
        }
    }

    /// Drops a persisted repo filter that no longer matches anything in either
    /// tab — otherwise a repo you finished with would leave both drawers empty
    /// next to non-zero badges, with no obvious cause.
    ///
    /// The rule itself lives on AppState, which is also where an account switch
    /// reaches it. One implementation, because the two triggers must agree.
    private func validateRepoFilter() {
        let before = state.repoFilter
        state.dropStaleRepoFilter()
        if before != nil, state.repoFilter == nil {
            Log.debug("cleared stale repo filter: \(before ?? "")")
        }
    }

    // MARK: - Context menu
    //
    // There is no Dock icon or menu bar item, so this is the only way to quit.

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        if let lastUpdated = state.lastUpdated {
            let status = NSMenuItem(
                title: "Updated \(TimeAgo.long(since: lastUpdated))",
                action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)
        }
        if let error = state.lastError ?? state.authError {
            let item = NSMenuItem(title: String(error.prefix(70)), action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
        menu.addItem(.separator())

        menu.addItem(withTitle: "Refresh now",
                     action: #selector(menuRefresh), keyEquivalent: "r").target = self
        if case .available(let version, _) = state.updateStatus {
            let item = NSMenuItem(title: "Download PR Radar \(version)…",
                                  action: #selector(menuOpenUpdate),
                                  keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        menu.addItem(withTitle: "Open review requests on GitHub",
                     action: #selector(menuOpenGitHub), keyEquivalent: "").target = self

        // The mascot picker, "Start at login" and "Reset badge size" were all
        // here until the drawer grew a settings room. One entry that opens it
        // rather than a copy of each control: two places to change one setting
        // is two places to keep agreeing with each other, and the menu was
        // never a good home for a text field.
        menu.addItem(withTitle: "Settings…",
                     action: #selector(menuOpenSettings), keyEquivalent: ",").target = self

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PR Radar",
                     action: #selector(menuQuit), keyEquivalent: "q").target = self
        return menu
    }

    @objc private func menuOpenSettings() { panel.openRoom(.settings) }

    @objc private func menuRefresh() { refreshNow() }

    @objc private func menuOpenGitHub() {
        let url = URL(string: "https://github.com/pulls/review-requested")!
        NSWorkspace.shared.open(url)
    }

    @objc private func menuOpenUpdate() {
        if let url = state.updateStatus.url { NSWorkspace.shared.open(url) }
    }

    @objc private func menuQuit() { NSApp.terminate(nil) }
}
