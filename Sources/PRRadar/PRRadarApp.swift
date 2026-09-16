import AppKit
import PRRadarCore

// Not `main.swift`: top-level code is nonisolated, which cannot touch the
// main-actor-isolated AppKit types. An explicit @MainActor entry point can.
@main
struct PRRadarApp {
    /// `NSApplication.delegate` does not retain its delegate, so the instance
    /// has to be owned somewhere that outlives `main()`. Held only in a local,
    /// ARC releases it right after the assignment — the app then sits in a
    /// running run loop with no delegate and never shows a window.
    @MainActor private static var retainedDelegate: AppDelegate?

    @MainActor
    static func main() {
        // `--print` runs one fetch, dumps what the drawer would show, and exits.
        // Useful for checking data parity against `gh` without the GUI.
        if CommandLine.arguments.contains("--print") {
            Diagnostics.runAndExit()
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        retainedDelegate = delegate
        app.delegate = delegate
        // Accessory: no Dock icon, no menu bar — the panel is the whole interface.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

enum Diagnostics {
    static func runAndExit() -> Never {
        let semaphore = DispatchSemaphore(value: 0)
        var exitCode: Int32 = 0

        Task {
            do {
                let (token, source) = try Token.resolveWithSource()
                print("token: resolved via \(source.rawValue) (\(token.prefix(4))…)")

                let client = GitHubClient(token: token)
                let (login, teams) = try await client.fetchViewerAndTeams()
                print("viewer: \(login)")
                print("teams:  \(teams.isEmpty ? "none" : teams.map(\.qualified).joined(separator: ", "))")

                let searches = try await client.fetchPullRequests(teams: teams)
                let rawCounts = searches
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value.nodes.count)" }
                    .joined(separator: " ")
                print("scopes: \(rawCounts)")

                let items = ReviewInbox(viewerLogin: login, teams: teams).build(from: searches)
                print("\nwaiting on you: \(items.count)")
                for item in items {
                    let age = TimeAgo.short(since: item.pingedAt)
                    print("  #\(item.number)  \(age.padding(toLength: 4, withPad: " ", startingAt: 0)) "
                          + "\(item.authorLogin.padding(toLength: 22, withPad: " ", startingAt: 0)) "
                          + "\(item.repoShortName)")
                    print("        \(item.title)")
                }

                try await printMyPRs(client: client)
            } catch {
                FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
                exitCode = 1
            }
            semaphore.signal()
        }

        semaphore.wait()
        exit(exitCode)
    }

    static func printMyPRs(client: GitHubClient) async throws {
        let result = try await client.fetchMyPullRequests()
        let inbox = MyPRInbox(leadLogins: Prefs.leadLogins)
        var mine = inbox.build(from: result)

        // Second phase is allowed to fail on its own; behindBy stays unknown.
        do {
            let compares = try await client.fetchCompares(for: mine)
            mine = MyPRInbox.applyCompares(compares, to: mine)
        } catch {
            print("\n(compare phase failed: \(error.localizedDescription))")
        }

        print("\nmy open PRs: \(mine.count)   leads: \(Prefs.leadLogins.joined(separator: ", "))")
        for pr in MyPRSortOrder.newestFirst.apply(to: mine) {
            let behind: String = {
                switch pr.branchState {
                case .upToDate: return "up to date"
                case .needsRebase(let n): return n.map { "needs rebase (\($0) behind)" }
                                                 ?? "needs rebase"
                case .conflicts: return "conflicts"
                case .unknown: return "base state unknown"
                }
            }()
            print("  #\(pr.number)  \(pr.repoShortName)  [\(pr.health.rawValue)]")
            print("        \(pr.title)")
            print("        decision=\(pr.reviewDecision.rawValue) merge=\(pr.mergeBlocker.rawValue) \(behind)")
            let live = pr.liveApprovals.map { "\($0.shortName)\($0.isLead ? "*" : "")" }
            let dismissed = pr.dismissedApprovals.map { "\($0.shortName)\($0.isLead ? "*" : "")" }
            print("        approvals live=[\(live.joined(separator: ","))] "
                  + "dismissed=[\(dismissed.joined(separator: ","))] "
                  + "lead=\(pr.approvingLead.map { $0.shortName } ?? "NEEDED")")
            print("        checks pass=\(pr.checks.passing) fail=\(pr.checks.failing) "
                  + "run=\(pr.checks.running) skip=\(pr.checks.skipped) "
                  + "rollup=\(pr.checks.rollupState ?? "none")")
            if !pr.checks.failingNames.isEmpty {
                print("        failing: \(pr.checks.failingNames.joined(separator: ", "))")
            }
            print("        threads \(pr.unresolvedThreadCount) open of \(pr.totalThreadCount)  "
                  + "+\(pr.additions) -\(pr.deletions) in \(pr.changedFiles) files  "
                  + "open \(TimeAgo.short(since: pr.createdAt))")
            print("        \(pr.headRefName) -> \(pr.baseRefName)"
                  + (pr.stackedOn.map { "  [stacked on #\($0)]" } ?? "")
                  + (pr.blocksRestackOf.isEmpty ? "" : "  [rebase strands \(pr.blocksRestackOf.map { "#\($0)" }.joined(separator: ", "))]")
                  + (pr.isReadyToMerge ? "  READY TO MERGE" : ""))
        }
    }
}
