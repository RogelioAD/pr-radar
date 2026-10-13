import Foundation
import PRRadarCore

/// Runs resolve skills against your own pull requests, one at a time, and posts
/// what they decide.
///
/// The sibling of `AutoReviewCoordinator`, and the same division of labour:
/// every rule it consults — which trees are usable, what the run decided, which
/// threads may close — is a pure function in `PRRadarCore` with tests of its
/// own, and what is left here is the order things happen in plus the two
/// resources that cannot be tested without the world.
///
/// Three things make it genuinely different from its sibling, and all three are
/// the same fact wearing different clothes: **this one writes to a checkout the
/// developer actually works in.**
///
/// - It is **never automatic.** There is no queue, no poll hook and no switch.
///   Bot reviewers comment again after every push, so a resolver on a timer
///   would answer its own fixes for ever, and spend money doing it. It runs
///   when a button is pressed and not otherwise.
/// - It **refuses rather than tidies.** A tree with work in it, a branch
///   checked out nowhere, a checkout behind the pull request: every one of
///   those is a refusal with a sentence, never a stash or a checkout performed
///   on the user's behalf.
/// - It is **not restarted after a crash.** `AutoReviewCoordinator` re-queues
///   an interrupted review because a review that died had only read. A resolve
///   that died may have edited, committed and pushed, and nothing can tell from
///   outside which. The record becomes evidence instead.
@MainActor
final class ResolveCoordinator {

    /// What a row's buttons can ask for once a run has finished.
    enum Action: Equatable {
        case post
        case dismiss
    }

    private unowned let state: AppState
    private var worker: Task<Void, Never>?
    /// Which row the worker is for, so Stop can be drawn on that row and only
    /// that one.
    private var runningKey: String?

    /// Where leases live: beside the app's own data, never inside the user's
    /// repository. See `ResolveLease`.
    private static var leaseDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("PRRadar/resolve-leases", isDirectory: true)
    }

    init(state: AppState) {
        self.state = state
        reconcileAbandoned()
    }

    deinit { worker?.cancel() }

    // MARK: - Launch

    /// Turns whatever the last run left behind into something the row can say.
    ///
    /// Deliberately the opposite of `AutoReviewCoordinator.recoverFromInterruption`,
    /// which puts interrupted work back in the queue. Nothing is re-queued here
    /// and nothing is deleted — a worktree this app did not create is not this
    /// app's to tidy, and a half-finished run is evidence before it is mess.
    private func reconcileAbandoned() {
        var log = state.resolveLog
        let abandoned = log.reconcileAbandoned(
            headOf: { Self.headSync(of: $0) },
            isAlive: { record in
                guard let tree = record.treePath,
                      let lease = Self.lease(forTree: tree)
                else { return false }
                return lease.holder(alive: { kill($0, 0) == 0 },
                                    selfPID: ProcessInfo.processInfo
                                        .processIdentifier) == .live
            })
        guard !abandoned.isEmpty else { return }
        state.resolveLog = log
        Log.debug("resolve: reconciled \(abandoned.count) abandoned run(s): "
                  + abandoned.joined(separator: ", "))
    }

    // MARK: - Starting one

    /// Checks everything, then runs. Returns immediately.
    ///
    /// One run at a time across the whole app, and that includes automatic
    /// review: both are a whole Claude Code session, and this one also runs the
    /// repository's test suite. Two at once on a laptop is a fan event, and two
    /// `cargo` builds against one `target/` corrupt the cache.
    func resolve(_ pr: MyPullRequest, scope: ResolveScope = .threads) {
        let key = pr.id
        guard state.rowActions.begin(key) else { return }
        guard worker == nil else {
            state.rowActions.end(key)
            state.lastError = "Something is already running. One at a time."
            return
        }

        runningKey = key
        worker = Task { [weak self] in
            await self?.run(pr, scope: scope)
            self?.worker = nil
            self?.runningKey = nil
            self?.state.rowActions.end(key)
        }
    }

    /// Stops a run somebody is watching and has decided they do not want.
    ///
    /// There was no way to do this at all for a while, which was the wrong
    /// shape for a feature whose whole job takes a quarter of an hour: the only
    /// ways out were quitting the app or finding the pid. A run you have
    /// changed your mind about is the ordinary case, not an incident.
    ///
    /// **Cancelled, not killed.** Cancelling the task makes `ProcessRunner`
    /// send one `SIGTERM` and stop watching — and because a resolve run passes
    /// `escalate: false`, no `SIGKILL` follows. A session part-way through
    /// `git commit` gets to finish rather than leaving `index.lock` behind in a
    /// repository the developer works in. The cost is that stopping is not
    /// instant, and the row says so.
    func stop(_ pr: MyPullRequest) {
        guard runningKey == pr.id, let worker else { return }
        Log.debug("stopping resolve for \(pr.id)")
        update(pr.id) { $0.failure = "Stopping…" }
        worker.cancel()
    }

    /// Whether this row is the one with a session behind it.
    func isRunning(_ pr: MyPullRequest) -> Bool { runningKey == pr.id }

    private func run(_ pr: MyPullRequest, scope: ResolveScope) async {
        let key = pr.id

        // Every guard, against the tree as it is right now — not as it was when
        // the row was drawn. A tree can go dirty in the seconds between.
        // The same guards for both jobs. A merge needs a clean tree at the
        // pull request's head quite as much as a set of fixes does — more so,
        // since it is about to create a conflicted state on purpose.
        var probe = await probe(pr)

        // One refusal the run can answer itself, so it does, rather than
        // bouncing the work back as a second button to press.
        //
        // A branch that has moved — usually a bot pushing after a review —
        // leaves the checkout behind the pull request, and starting there would
        // merge into code older than the pull request and then cite it. That is
        // worth stopping for, and it is *not* worth asking about: it is a fetch
        // and a pointer move with no decision in it. So the run brings the
        // checkout up and carries on, and the guards are asked again afterwards
        // rather than assumed to have been satisfied.
        //
        // Only ever a fast-forward. A branch with commits of its own still
        // refuses, because a reset would make it work and would throw them
        // away — see `fastForwardIfBehind`.
        if case .headMismatch = ResolveGuard.evaluate(probe, pr: pr) {
            if await fastForwardIfBehind(pr) {
                probe = await self.probe(pr)
            }
        }

        if let block = ResolveGuard.evaluate(probe, pr: pr) {
            var record = ResolveRecord(status: .blocked, mode: state.resolveMode,
                                       scope: scope)
            record.block = block
            record.failure = block.reason
            record.finishedAt = Date()
            state.resolveLog[key] = record
            return
        }

        guard let claude = state.claudePath,
              let skill = ReviewSkill.normalized(state.resolveSkillDraft),
              let tree = Self.tree(for: pr, in: probe)
        else { return }

        let preRunOid = probe.localHead
        let mode = state.resolveMode

        var record = ResolveRecord(status: .running, mode: mode, scope: scope)
        record.startedAt = Date()
        record.treePath = tree
        record.preRunOid = preRunOid
        state.resolveLog[key] = record

        Self.writeLease(ResolveLease(
            appPID: ProcessInfo.processInfo.processIdentifier,
            repo: pr.repo, number: pr.number, branch: pr.headRefName,
            treePath: tree, preRunOid: preRunOid, mode: mode))
        defer { Self.clearLease(forTree: tree) }

        // The full conversation, not the poll's three-comments-and-320-characters.
        // A session asked to rule on an argument it was handed a truncated copy
        // of is being set up to be wrong — "a thread cut off mid-argument reads
        // as settled", as the skill's own notes put it.
        // Only a threads run needs them, and only a threads run pays for the
        // extra request.
        let threads = scope.producesReplies
            ? (await fullThreads(for: pr) ?? pr.unresolvedThreads)
            : []

        let request = ResolveRequest(
            skill: skill, repo: pr.repo, number: pr.number, url: pr.url,
            branch: pr.headRefName, headOid: pr.headOid ?? preRunOid ?? "",
            treePath: tree, scope: scope, gates: state.resolveGates,
            baseBranch: pr.baseRefName, mode: mode,
            outOfScope: state.resolveOutOfScope, pending: state.resolvePending,
            threads: threads, model: Prefs.reviewModel,
            budgetUSD: Prefs.resolveBudget)

        let timeout = TimeInterval(Prefs.resolveTimeoutMinutes * 60)
        do {
            let result = try await ProcessRunner.run(
                executable: claude,
                arguments: ResolveInvocation.arguments(for: request),
                workingDirectory: URL(fileURLWithPath: tree),
                environment: ProcessRunner.environment(extraPaths: state.helperPaths()),
                timeout: timeout,
                // Never. A SIGKILL inside `git commit` leaves index.lock in a
                // repository the developer works in, and every git command they
                // run afterwards fails with an error that does not name us.
                escalate: false)

            // Asked before the table is read, because it decides how a failure
            // is reported: a run that pushed and then produced nothing readable
            // is not a retry, it is a go-and-look.
            let pushed = await Self.commits(in: tree, since: preRunOid)

            let parsed = ResolveParser.parse(
                exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr,
                timedOut: result.timedOut, timeoutSeconds: Int(timeout),
                pushedShas: pushed)

            // Asked about before the result is judged: a cancelled run exits
            // non-zero because it was signalled, and reporting "exited with
            // code 143" to somebody who just pressed Stop would be the app
            // blaming them for its own obedience.
            if Task.isCancelled {
                stopped(key, pushed: pushed)
                return
            }

            switch parsed {
            case .success(let table):
                let onRemote = await Self.pushedCommits(in: tree, since: preRunOid)
                finish(key, table.sanitised(against: threads, pushedShas: onRemote,
                                            scope: scope),
                       pushed: pushed, mode: mode, scope: scope)
            case .failure(let failure):
                fail(key, failure, pushed: pushed)
            }
        } catch {
            let pushed = await Self.commits(in: tree, since: preRunOid)
            if Task.isCancelled {
                stopped(key, pushed: pushed)
            } else {
                fail(key, .unparseable(error.localizedDescription), pushed: pushed)
            }
        }
    }

    private func stopped(_ key: String, pushed: [String]) {
        update(key) { record in
            if record.runSeconds == nil {
                record.runSeconds = record.startedAt.map { -$0.timeIntervalSinceNow }
            }
            record.pushedShas = pushed
            record.finishedAt = Date()
            // Even a stopped run may have got as far as pushing, and that is
            // worth more than the fact it was stopped: there are commits on the
            // branch either way, and the row has to say so.
            if pushed.isEmpty {
                record.status = .stopped
                record.failure = "Stopped. Nothing had landed."
            } else {
                record.status = .landedUnreported
                record.failure = "Stopped after it had already committed."
            }
        }
    }

    private func finish(_ key: String, _ table: ResolveTable,
                        pushed: [String], mode: ResolveMode, scope: ResolveScope) {
        update(key) { record in
            record.runSeconds = record.startedAt.map { -$0.timeIntervalSinceNow }
            record.table = table
            record.pushedShas = pushed
            record.status = .ready
            record.finishedAt = Date()
            record.failure = nil
        }
        // Nothing is held when there is nothing to hold: an automatic run
        // posted its own replies, and a conflicts run never had any. Either way
        // the row is reporting rather than waiting.
        if mode.postsWithoutAsking || !scope.producesReplies {
            update(key) { $0.status = .posted }
        }
    }

    private func fail(_ key: String, _ failure: ResolveFailure, pushed: [String]) {
        Log.debug("resolve failed [\(key)]: \(failure.message)")
        update(key) { record in
            if record.runSeconds == nil {
                record.runSeconds = record.startedAt.map { -$0.timeIntervalSinceNow }
            }
            record.pushedShas = pushed
            record.failure = failure.message
            record.finishedAt = Date()
            // A run that put commits on the branch is its own terminal state,
            // and must not offer a retry that would layer a second set on top.
            if case .landedUnreported = failure {
                record.status = .landedUnreported
            } else {
                record.status = .failed
            }
        }
    }

    // MARK: - Posting

    func act(_ action: Action, on pr: MyPullRequest) {
        let key = pr.id
        guard state.rowActions.begin(key) else { return }
        Task {
            await perform(action, on: pr)
            state.rowActions.end(key)
        }
    }

    private func perform(_ action: Action, on pr: MyPullRequest) async {
        let key = pr.id
        switch action {
        case .dismiss:
            update(key) { $0.status = .dismissed; $0.finishedAt = Date() }

        case .post:
            guard let record = state.resolveLog[key],
                  let table = record.table,
                  let client = client(for: pr)
            else { return }

            var posted: [String] = []
            for row in table.postable {
                // Reply first, and check it is really there. A thread closed
                // over a reply that never landed reads to everybody else as
                // handled, which is the one failure this feature exists to
                // prevent — and `addPullRequestReviewThreadReply` has a silent
                // way of not landing: a PENDING review of your own swallows it.
                guard let url = await client.replyToThread(id: row.threadId,
                                                           body: row.reply),
                      !url.isEmpty
                else {
                    Log.debug("resolve: reply to \(row.threadId) did not land; "
                              + "leaving the thread open")
                    continue
                }
                posted.append(row.threadId)
                // And only then close it, and only when it may be closed.
                if row.mayResolve {
                    await client.resolveThread(id: row.threadId)
                }
            }

            update(key) { record in
                record.postedThreadIDs = posted
                record.status = .posted
                record.finishedAt = Date()
            }
        }
    }

    /// Merges the base branch into a pull request's head, server-side.
    ///
    /// Lives here rather than in a coordinator of its own because this is the
    /// one place that already knows how to act on *your* pull request as the
    /// account that surfaced it, and already holds the per-row gate that stops
    /// a second press landing on top of the first. It is not a resolve run and
    /// borrows none of its machinery: no skill, no checkout, no lease.
    ///
    /// It deliberately does **not** take the worker slot. There is no process
    /// and no test suite — it is one mutation — so blocking it behind a review
    /// that might be a quarter of an hour from finishing would be making the
    /// user wait on nothing.
    func updateBranch(_ pr: MyPullRequest) {
        let key = pr.id
        guard state.rowActions.begin(key) else { return }
        Task {
            await performUpdateBranch(pr)
            state.rowActions.end(key)
        }
    }

    private func performUpdateBranch(_ pr: MyPullRequest) async {
        guard let client = client(for: pr),
              let nodeID = pr.nodeID,
              // Required, not optional. Without it GitHub would merge whatever
              // the branch happens to be now, which may be several pushes past
              // the row that offered the button.
              let headOid = pr.headOid
        else {
            state.lastError = "That PR arrived without the ids a merge needs."
            return
        }
        do {
            _ = try await client.updateBranch(pullRequestID: nodeID,
                                              expectedHeadOid: headOid)
            Log.debug("updated \(pr.repo)#\(pr.number) from \(pr.baseRefName)")
        } catch {
            // Said out loud rather than logged. The two interesting failures
            // both need the user to do something: the branch moved under them,
            // or the merge conflicts — and the second one is what the Resolve
            // conflicts button beside this one is for.
            state.lastError = "Could not update #\(pr.number) from "
                + "\(pr.baseRefName). It may have moved, or it may conflict — "
                + "try Resolve conflicts."
        }
    }

    /// Brings the local checkout up to the pull request's head.
    ///
    /// The answer to the one refusal a developer cannot act on from inside the
    /// app without being told the command: *that checkout is at 021ba49; the PR
    /// is at 06ae402*. The branch has moved — usually a bot pushing after a
    /// review — and the guard is right to stop, because a run started on a
    /// stale head merges into code one commit behind the pull request and then
    /// writes replies citing it.
    ///
    /// **Fetch, then fast-forward, and nothing else.** It never resets, never
    /// force-updates, and stops the moment the local branch turns out to have
    /// commits of its own. A reset is the command that always works and
    /// sometimes silently destroys somebody's unpushed work; whether to rebase,
    /// push or discard those is a decision this is not entitled to make at a
    /// sixty-second poll.
    ///
    /// Takes the row gate but not the worker slot: it is a fetch and a pointer
    /// move, not a session.
    @discardableResult
    private func fastForwardIfBehind(_ pr: MyPullRequest) async -> Bool {
        guard let root = Prefs.reviewWorkspace,
              let clone = await state.findCheckout(of: pr.repo, under: root)
        else { return false }

        let porcelain = (try? await AppState.runGit(
            ["-C", clone.path, "worktree", "list", "--porcelain"])) ?? ""
        guard case .success(let found) = GitWorktrees.holding(
                branch: pr.headRefName,
                in: GitWorktrees.parse(porcelain: porcelain)),
              let tree = found
        else { return false }

        // Re-checked here rather than trusted from the probe that refused: the
        // tree can have gone dirty in the time it took somebody to read the row
        // and press the button, and this is about to move their HEAD.
        let status = GitStatus.parse(porcelainV2: (try? await AppState.runGit(
            ["-C", tree.path, "status", "--porcelain=v2", "--branch"])) ?? "")
        // The guard below will refuse on this anyway, and with a better
        // sentence than anything said here — so this simply declines to move a
        // tree that has somebody's work in it.
        guard status.isSafeToWorkIn else { return false }

        _ = try? await AppState.runGit(
            ["-C", clone.path, "fetch", "--quiet", "origin", pr.headRefName])

        let remote = "origin/\(pr.headRefName)"
        let counts = FastForward.counts(fromRevList: (try? await AppState.runGit(
            ["-C", tree.path, "rev-list", "--left-right", "--count",
             "HEAD...\(remote)"])) ?? "")
        guard let counts else { return false }

        switch FastForward.verdict(ahead: counts.ahead, behind: counts.behind) {
        case .upToDate:
            // Nothing to move. The head still disagreed with the pull request,
            // so the branch has moved somewhere this fetch cannot see — the
            // guard will say so.
            return false

        case .diverged(let ahead, _):
            // Stops here, deliberately. Fast-forwarding is impossible and
            // resetting would discard commits nobody else has; whether to
            // rebase, push or drop them is the developer's call, and this is a
            // button press, not a conversation.
            state.lastError = "\(pr.headRefName) has \(ahead) commit"
                + "\(ahead == 1 ? "" : "s") that \(remote) does not, so it cannot "
                + "be brought up to the PR without discarding them. Push or "
                + "rebase them first."
            return false

        case .canFastForward(let behind):
            do {
                _ = try await AppState.runGit(
                    ["-C", tree.path, "merge", "--ff-only", remote])
                Log.debug("caught \(tree.path) up to \(remote) (\(behind) behind)")
                return true
            } catch {
                state.lastError = "Could not bring \(pr.headRefName) up to the "
                    + "pull request — it may have been force-pushed."
                return false
            }
        }
    }

    /// Ticks one row of the table.
    func setRow(_ threadID: String, on pr: MyPullRequest, selected: Bool) {
        guard var record = state.resolveLog[pr.id], var table = record.table,
              let index = table.threads.firstIndex(where: { $0.threadId == threadID })
        else { return }
        // A row nobody disposed of does not become postable by being ticked.
        guard table.threads[index].mayResolve || !selected else { return }
        table.threads[index].isSelected = selected
        record.table = table
        state.resolveLog[pr.id] = record
    }

    /// The whole conversation on every open thread, fetched for this one run.
    ///
    /// Falls back to what the poll already has rather than failing: a truncated
    /// thread list is worse than an untruncated one and much better than no run
    /// at all, and the fallback is the data the row has been drawing all along.
    private func fullThreads(for pr: MyPullRequest) async -> [UnresolvedThread]? {
        guard let client = client(for: pr) else { return nil }
        return try? await client.fetchThreads(repo: pr.repo, number: pr.number)
    }

    // MARK: - Probing the world

    private func probe(_ pr: MyPullRequest) async -> ResolveProbe {
        var probe = ResolveProbe()
        probe.claudePath = state.claudePath
        probe.skill = ReviewSkill.normalized(state.resolveSkillDraft)
        probe.isAllowed = state.isResolveAllowed(pr.repo)
        probe.workspace = Prefs.reviewWorkspace

        guard let root = probe.workspace,
              let clone = await findCheckout(of: pr.repo, under: root)
        else { return probe }
        probe.clone = clone.path

        let porcelain = (try? await Self.git(["-C", clone.path, "worktree", "list",
                                              "--porcelain"])) ?? ""
        probe.worktrees = GitWorktrees.parse(porcelain: porcelain)

        guard case .success(let found) =
                GitWorktrees.holding(branch: pr.headRefName, in: probe.worktrees),
              let tree = found
        else { return probe }

        probe.localHead = (try? await Self.git(["-C", tree.path, "rev-parse", "HEAD"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        probe.status = GitStatus.parse(porcelainV2:
            (try? await Self.git(["-C", tree.path, "status", "--porcelain=v2",
                                  "--branch"])) ?? "")
        probe.operation = await Self.operationInProgress(in: tree.path)
        if let lease = Self.lease(forTree: tree.path),
           lease.holder(alive: { kill($0, 0) == 0 },
                        selfPID: ProcessInfo.processInfo.processIdentifier) == .live {
            probe.leaseHeldAt = tree.path
        }
        return probe
    }

    private static func tree(for pr: MyPullRequest, in probe: ResolveProbe) -> String? {
        guard case .success(let found) =
                GitWorktrees.holding(branch: pr.headRefName, in: probe.worktrees)
        else { return nil }
        return found?.path
    }

    /// Git's own marker files, asked of the filesystem. `status` does not
    /// report a rebase stopped between commits, and that is exactly the state
    /// an unattended run would do the most damage starting from.
    private static func operationInProgress(in tree: String) async -> GitOperation? {
        let gitDir = (try? await git(["-C", tree, "rev-parse", "--absolute-git-dir"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let gitDir, !gitDir.isEmpty else { return nil }
        for operation in GitOperation.allCases {
            for marker in operation.markers {
                let path = (gitDir as NSString).appendingPathComponent(marker)
                if FileManager.default.fileExists(atPath: path) { return operation }
            }
        }
        return nil
    }

    /// Commits on the branch that were not there before the run.
    private static func commits(in tree: String, since oid: String?) async -> [String] {
        guard let oid, !oid.isEmpty else { return [] }
        let output = (try? await git(["-C", tree, "log", "--format=%H",
                                      "\(oid)..HEAD"])) ?? ""
        return output.split(separator: "\n").map {
            String($0.trimmingCharacters(in: .whitespaces))
        }.filter { !$0.isEmpty }
    }

    /// Of those, the ones that are actually on the remote.
    ///
    /// This is what makes a reply true. The skill is told that a sha it cites
    /// must be pushed; this is the part that checks rather than asks, and a row
    /// whose commit is not here is held back rather than posted.
    private static func pushedCommits(in tree: String, since oid: String?) async -> Set<String> {
        let upstream = (try? await git(["-C", tree, "rev-parse", "--abbrev-ref",
                                        "@{upstream}"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let upstream, !upstream.isEmpty else { return [] }
        let local = await commits(in: tree, since: oid)
        var onRemote: Set<String> = []
        for sha in local {
            let merged = try? await git(["-C", tree, "merge-base", "--is-ancestor",
                                         sha, upstream])
            if merged != nil { onRemote.insert(sha) }
        }
        return onRemote
    }

    private static func headSync(of tree: String) -> String? {
        let git = ProcessRunner.firstExecutable(
            among: ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"])
        guard let git else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: git)
        process.arguments = ["-C", tree, "rev-parse", "HEAD"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func git(_ arguments: [String]) async throws -> String {
        guard let git = ProcessRunner.firstExecutable(
            among: ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"])
        else { throw ResolveFailure.unparseable("git was not found") }
        let result = try await ProcessRunner.run(
            executable: git, arguments: arguments, timeout: 120)
        guard result.exitCode == 0 else {
            throw ResolveFailure.exited(code: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
    }

    /// Reuses the review coordinator's search, which already asks git what a
    /// checkout's origin is rather than matching folder names, and already
    /// accepts a worktree as an answer.
    private func findCheckout(of repo: String, under root: String) async -> URL? {
        await state.findCheckout(of: repo, under: root)
    }

    // MARK: - Leases

    private static func leaseURL(forTree path: String) -> URL {
        leaseDirectory.appendingPathComponent(ResolveLease.filename(forTree: path))
    }

    private static func lease(forTree path: String) -> ResolveLease? {
        ResolveLease.decoded(from: try? Data(contentsOf: leaseURL(forTree: path)))
    }

    private static func writeLease(_ lease: ResolveLease) {
        try? FileManager.default.createDirectory(at: leaseDirectory,
                                                 withIntermediateDirectories: true)
        try? lease.encoded()?.write(to: leaseURL(forTree: lease.treePath), options: .atomic)
    }

    private static func clearLease(forTree path: String) {
        try? FileManager.default.removeItem(at: leaseURL(forTree: path))
    }

    // MARK: - Bookkeeping

    private func update(_ key: String, _ change: (inout ResolveRecord) -> Void) {
        var record = state.resolveLog[key] ?? ResolveRecord()
        change(&record)
        state.resolveLog[key] = record
    }

    private func client(for pr: MyPullRequest) -> GitHubClient? {
        guard let account = state.accounts.first(where: { $0.id == pr.account })
                ?? state.accounts.first,
              let token = Accounts.token(for: account)
        else { return nil }
        return GitHubClient(token: token)
    }
}
