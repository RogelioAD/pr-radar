import AppKit
import SwiftUI
import PRRadarCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let state = AppState()
    private let notifier = Notifier()
    private var panel: PanelController!
    private var pollTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var updateTask: Task<Void, Never>?

    /// Discovered once per launch and reused for every poll.
    private var viewerLogin: String?
    private var teams: [TeamRef] = []

    private let pollInterval: Duration = .seconds(60)

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.debug("applicationDidFinishLaunching")
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

        startPolling()
        startClock()
        startUpdateChecks()
    }

    func applicationWillTerminate(_ notification: Notification) {
        pollTask?.cancel()
        clockTask?.cancel()
        updateTask?.cancel()
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
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
    private func refreshNow() {
        Task { await refresh(alsoCheckingForUpdate: true) }
    }

    private func refresh(alsoCheckingForUpdate checkForRelease: Bool = false) async {
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

            notifier.notifyNewPings(in: items)

            await refreshMyPRs(client: client)

            panel.refreshLayoutIfExpanded()
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

        // Awaited here rather than in a `defer`, which cannot await and so
        // would fire after isRefreshing had already cleared. Outside the
        // do/catch too, so a failed PR fetch does not skip it.
        if checkForRelease {
            await checkForUpdate()
            panel.refreshLayoutIfExpanded()
        }
    }

    /// The My PRs tab. Failures here must not blank the Reviews tab, so they
    /// are recorded and swallowed rather than thrown.
    private func refreshMyPRs(client: GitHubClient) async {
        do {
            let result = try await client.fetchMyPullRequests()
            var mine = MyPRInbox(leadLogins: Prefs.leadLogins).build(from: result)

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
