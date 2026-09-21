import AppKit
import Network
import SwiftUI
import PRRadarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let state = AppState()
    private var leadsWindow: NSWindow?
    private let notifier = Notifier()
    private var panel: PanelController!
    private var pollTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?
    /// Guards the release check the way `isRefreshing` guards the PR fetch.
    /// Needed now that a manual press no longer rides the PR fetch's guard:
    /// the six-hour timer and a press can otherwise overlap, and two checks
    /// racing both read the old `notifiedUpdate` and both notify.
    private var isCheckingForUpdate = false

    /// Discovered once per launch and reused for every poll.
    private var viewerLogin: String?
    private var teams: [TeamRef] = []

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

        let token: String
        do {
            token = try Token.resolve()
        } catch {
            state.authError = error.localizedDescription
            panel.syncVisibility()
            return
        }

        let client = GitHubClient(token: token)
        do {
            if viewerLogin == nil {
                let discovered = try await client.fetchViewerAndTeams()
                viewerLogin = discovered.login
                teams = discovered.teams
            }
            guard let login = viewerLogin else { return }

            let searches = try await client.fetchPullRequests(teams: teams)
            let inbox = ReviewInbox(viewerLogin: login, teams: teams)
            let items = inbox.build(from: searches)

            Log.debug("refresh ok: \(items.count) items")
            state.authError = nil
            state.lastError = nil
            state.items = items
            // Drop measurements for rows that are gone, and an author filter
            // whose author no longer has anything waiting — otherwise the
            // drawer would sit empty next to a non-zero badge.
            state.rowHeights = RowHeightKeys.pruned(state.rowHeights,
                                                    tab: .reviews,
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

            await refreshMyPRs(client: client)

            panel.refreshLayoutIfExpanded()
            panel.refreshBadgeSize()
            panel.syncVisibility()
            if Log.startExpanded && !(items.isEmpty && state.myPRs.isEmpty) {
                panel.setExpanded(true)
            }
        } catch {
            Log.debug("refresh failed: \(error)")
            // Keep showing the last known list rather than blanking out on a
            // transient network failure.
            state.lastError = error.localizedDescription
            if state.items.isEmpty {
                state.authError = error.localizedDescription
                panel.syncVisibility()
            }
        }
    }

    /// The My PRs tab. Failures here must not blank the Reviews tab, so they
    /// are recorded and swallowed rather than thrown.
    private func refreshMyPRs(client: GitHubClient) async {
        do {
            let result = try await client.fetchMyPullRequests()
            var mine = MyPRInbox(leads: Prefs.leadsByRepo).build(from: result)

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

            let liveIDs = Set(mine.map(\.id))
            state.rowHeights = RowHeightKeys.pruned(state.rowHeights,
                                                    tab: .mine,
                                                    liveIDs: liveIDs)
            state.myPRs = mine
            validateRepoFilter()
            Log.debug("my PRs: \(mine.count), ready to merge: \(state.myPRsReadyToMerge)")
        } catch {
            Log.debug("my PRs fetch failed: \(error)")
            state.lastError = error.localizedDescription
        }
    }

    /// Drops a persisted repo filter that no longer matches anything in either
    /// tab — otherwise a repo you finished with would leave both drawers empty
    /// next to non-zero badges, with no obvious cause.
    private func validateRepoFilter() {
        guard let repo = state.repoFilter else { return }
        let counts = state.repoCount(repo)
        if counts.reviews == 0 && counts.mine == 0 {
            Log.debug("clearing stale repo filter: \(repo)")
            state.repoFilter = nil
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

        menu.addItem(mascotMenuItem())

        menu.addItem(withTitle: "Leads…",
                     action: #selector(menuEditLeads), keyEquivalent: "").target = self

        let loginItem = NSMenuItem(title: "Start at login",
                                   action: #selector(menuToggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit PR Radar",
                     action: #selector(menuQuit), keyEquivalent: "q").target = self
        return menu
    }

    /// There is no preferences window, and this context menu is where
    /// "Start at login" already lives — so it is this app's settings surface,
    /// and the character picker belongs in it.
    ///
    /// Clicking the mascot in the drawer header cycles the cast; this is for
    /// picking one directly, and for turning it off.
    private func mascotMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "Mascot", action: nil, keyEquivalent: "")
        let submenu = NSMenu()

        let off = NSMenuItem(title: "Off", action: #selector(menuPickMascot(_:)),
                             keyEquivalent: "")
        off.target = self
        off.representedObject = ""
        off.state = state.mascot == nil ? .on : .off
        submenu.addItem(off)
        submenu.addItem(.separator())

        for mascot in Mascot.all {
            let item = NSMenuItem(title: mascot.name, action: #selector(menuPickMascot(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = mascot.id.rawValue
            item.state = state.mascot == mascot.id ? .on : .off
            item.toolTip = "Tell: \(mascot.tellName)"
            submenu.addItem(item)
        }

        parent.submenu = submenu
        return parent
    }

    @objc private func menuPickMascot(_ sender: NSMenuItem) {
        let raw = sender.representedObject as? String ?? ""
        state.mascot = raw.isEmpty ? nil : MascotID(rawValue: raw)
        // The widget's footprint changes with the character — and vanishes
        // back to the old tile when it is switched off.
        panel.refreshBadgeSize()
    }

    @objc private func menuEditLeads() {
        let view = LeadsEditorView(
            repos: state.repos,
            search: { repo, text in
                try await GitHubClient(token: try Token.resolve())
                    .searchMembers(repo: repo, matching: text)
            },
            onChange: { [weak self] in self?.refreshNow() })
        // A fresh view each time, so the repo list and leads are current.
        let window = leadsWindow ?? NSWindow()
        window.contentViewController = NSHostingController(rootView: view)
        window.title = "Leads"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        if leadsWindow == nil { window.center() }
        leadsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func menuRefresh() { refreshNow() }

    @objc private func menuOpenGitHub() {
        let url = URL(string: "https://github.com/pulls/review-requested")!
        NSWorkspace.shared.open(url)
    }

    @objc private func menuToggleLoginItem() {
        do {
            if LoginItem.isEnabled {
                try LoginItem.disable()
            } else {
                try LoginItem.enable(appPath: Bundle.main.bundlePath)
            }
        } catch {
            state.lastError = "Login item: \(error.localizedDescription)"
        }
    }

    @objc private func menuOpenUpdate() {
        if let url = state.updateStatus.url { NSWorkspace.shared.open(url) }
    }

    @objc private func menuQuit() { NSApp.terminate(nil) }
}
