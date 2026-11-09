import Foundation
import PRRadarCore

/// Runs automatic reviews, one at a time, and carries out what the row's
/// buttons decide.
///
/// Lives in the app target because it is wiring: every rule it consults —
/// which PRs are eligible, what the review says, where a thread may be
/// anchored, what counts as a failure — is a pure function in `PRRadarCore`
/// with tests of its own. What is left here is the order things happen in, and
/// the two resources that cannot be tested without the world: a git checkout
/// and a subprocess.
@MainActor
final class AutoReviewCoordinator {

    /// What a row's buttons can ask for.
    enum Action: Equatable {
        case commentOnly
        case approve
        case requestChanges
        case rerun
        case post
    }

    private unowned let state: AppState
    /// Logins of every account, so a PR the user wrote is never reviewed —
    /// whichever of their identities happens to have surfaced it.
    var viewerLogins: Set<String> = []
    var isOnline = true

    /// One worker, and one review at a time. A review is a whole Claude Code
    /// session — CPU, network and money — and three at once on a laptop is a
    /// fan event. It is also the only reason the header's "reviewing acme#12"
    /// can name a single thing.
    private var worker: Task<Void, Never>?
    private var startTimes: [Date] = []

    /// Three failures in a row and the feature switches itself off. An
    /// auto-poster that is broken should stop, not work its way down the list
    /// leaving a trail of identical errors.
    private var consecutiveFailures = 0
    private static let failureLimit = 3

    /// Long enough for a real review of a large diff, short enough that a
    /// wedged session is noticed the same morning.
    private static let timeout: TimeInterval = 15 * 60

    init(state: AppState) {
        self.state = state
        recoverFromInterruption()
    }

    /// Whatever the last run left in flight goes back in the queue, and the
    /// checkouts it left behind go in the bin.
    ///
    /// A review does not survive the app that started it, and it is routinely
    /// asked not to: `make install` pkills the running copy, and a crash or a
    /// log-out does the same thing less politely. Both halves of a review leak
    /// when that happens. The record sticks at `running`, where — being read as
    /// `.alreadyHandled` — nothing will ever reconsider it and no button is
    /// drawn to argue with, so the row says "reviewing…" for ever. And the
    /// worktree survives, because the `defer` that removes it died with the
    /// process; a checkout of a real repository is tens of megabytes, and one
    /// is stranded per interrupted run.
    ///
    /// Done in `init` rather than at the first refresh so that it lands before
    /// `recordSkips` and `pending` ever see the log.
    private func recoverFromInterruption() {
        var log = state.autoReviewLog
        let interrupted = log.reconcileInterrupted()
        if !interrupted.isEmpty {
            state.autoReviewLog = log
            Log.debug("re-queued \(interrupted.count) interrupted review(s): "
                      + interrupted.joined(separator: ", "))
        }
        reapWorktrees()
    }

    /// Deletes review worktrees that no longer have a review behind them.
    ///
    /// Which is emphatically *not* everything carrying our prefix. A copy of
    /// this app started by `make run` sits alongside the installed one by
    /// design, and both use the same temporary directory — so the question is
    /// never "is this ours" but "is anyone still using it". `Workspace` owns
    /// the answer; the two shims below are the parts of it that need the world.
    private func reapWorktrees() {
        let temp = FileManager.default.temporaryDirectory
        let stale = ((try? FileManager.default.contentsOfDirectory(atPath: temp.path)) ?? [])
            .filter { Workspace.isWorktree(path: $0) }
            .filter { name in
                let path = temp.appendingPathComponent(name).path
                return Workspace.isReapable(Self.owner(of: path), age: Self.age(of: path))
            }
        guard !stale.isEmpty else { return }

        Task.detached {
            for name in stale {
                let path = temp.appendingPathComponent(name).path
                // Asked before the files go, because afterwards there is nothing
                // left to ask: a worktree knows which clone owns it, and that
                // clone is the only place the registration can be pruned from.
                // `worktree remove` is not used — git refuses to remove the
                // worktree it was invoked inside, which is the only place we can
                // invoke it from without already knowing the answer.
                let owner = try? await Self.runGit(
                    ["-C", path, "rev-parse", "--path-format=absolute", "--git-common-dir"])
                try? FileManager.default.removeItem(atPath: path)
                if let owner = owner?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !owner.isEmpty {
                    _ = try? await Self.runGit(["-C", owner, "worktree", "prune"])
                }
            }
        }
    }

    /// Who owns a worktree, by asking the operating system about the pid its
    /// marker names.
    ///
    /// `kill(pid, 0)` signals nothing; it only reports whether the process is
    /// there. A recycled pid would read as `live` and leave a dead review's
    /// checkout on disk — which is the harmless way round to be wrong, and the
    /// reason the test is framed this way rather than the other.
    private static func owner(of path: String) -> Workspace.WorktreeOwner {
        let marker = (path as NSString).appendingPathComponent(Workspace.ownerMarker)
        guard let text = try? String(contentsOfFile: marker, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return .unmarked }
        return kill(pid, 0) == 0 ? .live : .abandoned
    }

    /// How long ago a worktree was created. Unreadable reads as brand new, so
    /// the doubt is resolved by leaving it alone.
    private static func age(of path: String) -> TimeInterval {
        let created = (try? FileManager.default.attributesOfItem(atPath: path))?[.creationDate]
        guard let created = created as? Date else { return 0 }
        return Date().timeIntervalSince(created)
    }

    deinit { worker?.cancel() }

    // MARK: - Driving the queue

    /// Called once a refresh has landed, with both lists in place.
    ///
    /// Returns immediately. It must never be awaited from inside `refresh()`'s
    /// `isRefreshing` guard: a fifteen-minute review holding that flag would
    /// freeze the sixty-second poll and grey out the drawer's refresh button
    /// for the duration.
    func refreshLanded() {
        prune()
        recordSkips()
        publishQueue()
        guard isOnline, worker == nil else { return }
        guard !pending().isEmpty else { return }

        worker = Task { [weak self] in
            await self?.drain()
            self?.worker = nil
        }
    }

    private func pending() -> [ReviewItem] {
        AutoReviewQueue.pending(items: state.items,
                                log: state.autoReviewLog,
                                viewerLogins: viewerLogins,
                                allowlist: state.reviewAllowlist,
                                policy: policy(),
                                startedInLastHour: startedInLastHour(),
                                now: Date())
    }

    /// Tells the rows who is waiting, and in what order.
    private func publishQueue() {
        guard !Log.fakeQueue else {
            state.reviewQueue = state.items.map(\.pingKey)
            return
        }
        let queue = AutoReviewQueue.waiting(pending: pending(),
                                            inFlight: state.reviewInFlight)
        if queue != state.reviewQueue { state.reviewQueue = queue }
    }

    private func policy() -> AutoReviewPolicy {
        AutoReviewPolicy(isEnabled: state.autoReviewEnabled && state.canAutoReview,
                         maxPerHour: state.reviewMaxPerHour)
    }

    private func startedInLastHour() -> Int {
        let cutoff = Date().addingTimeInterval(-3_600)
        startTimes.removeAll { $0 < cutoff }
        return startTimes.count
    }

    /// Writes down why a PR is *not* being reviewed, so a row never sits there
    /// looking un-reviewed with no explanation. Only the reasons worth reading
    /// are recorded — a chip saying a feature you never turned on is off would
    /// teach people to ignore the chips.
    ///
    /// **Recomputed every refresh, never remembered.** A skip is a condition,
    /// and the conditions are exactly the things a user goes and changes: tick
    /// the repo, name the skill, mark the draft ready. Stamping the reason once
    /// left the row insisting on something that had stopped being true — and
    /// the stale record was also what stopped the PR being reconsidered, so the
    /// only way out was to delete a defaults key. So each pass overwrites the
    /// reason, and clears it the moment there is no longer one.
    private func recordSkips() {
        let now = Date()
        var log = state.autoReviewLog

        for item in state.items {
            // Only ever touch a row this function owns. A queued, running,
            // posted or dismissed record is real work, and is not ours to
            // second-guess.
            let existing = log[item.pingKey]
            guard existing == nil || existing?.status == .skipped else { continue }

            let skip = AutoReviewQueue.skip(
                for: item, log: log, viewerLogins: viewerLogins,
                allowlist: state.reviewAllowlist, policy: policy(),
                startedInLastHour: startedInLastHour(), now: now)

            guard let skip, skip.isWorthShowing else {
                // Nothing to say any more. Clearing it is what lets a PR that
                // was skipped before the repo was allowlisted be picked up now.
                if existing != nil { log[item.pingKey] = nil }
                continue
            }

            guard existing?.failure != skip.reason else { continue }
            var record = AutoReviewRecord(status: .skipped)
            record.failure = skip.reason
            record.finishedAt = now
            log[item.pingKey] = record
        }

        if log != state.autoReviewLog { state.autoReviewLog = log }
    }

    private func prune() {
        var log = state.autoReviewLog
        log.prune(liveKeys: Set(state.items.map(\.pingKey)), now: Date())
        if log != state.autoReviewLog { state.autoReviewLog = log }
    }

    private func drain() async {
        while !Task.isCancelled, isOnline, let item = pending().first {
            await review(item)
            // Between reviews as well as on every refresh: a drain of three
            // runs for half an hour without one landing, and the rows behind
            // the current one would otherwise keep saying what was true when
            // it started.
            publishQueue()
            if consecutiveFailures >= Self.failureLimit {
                stop("Automatic review switched itself off after "
                     + "\(Self.failureLimit) reviews failed in a row.")
                return
            }
        }
    }

    /// Switches the feature off, and leaves an account of why that outlives the
    /// minute it was decided in.
    ///
    /// `lastError` alone was not enough and could not have been: the next
    /// refresh overwrites it with whatever that round had to say, and it is
    /// sixty seconds away at most. So the feature turned itself off — which it
    /// does, by design, while nobody is at the desk — and by the time anyone
    /// looked there was a switch in the off position and no account of who had
    /// moved it. `autoReviewStopped` is kept until the switch goes back on.
    private func stop(_ reason: String) {
        state.autoReviewEnabled = false
        state.autoReviewStopped = reason
        state.lastError = reason
        consecutiveFailures = 0
        Log.debug("automatic review switched itself off: \(reason)")
    }

    // MARK: - One review

    private func review(_ item: ReviewItem) async {
        let key = item.pingKey
        let startedAt = Date()
        startTimes.append(startedAt)
        update(key) { record in
            record.status = .running
            record.startedAt = startedAt
            record.attempts += 1
        }
        state.reviewInFlight = key
        publishQueue()
        defer { if state.reviewInFlight == key { state.reviewInFlight = nil } }

        do {
            let (findings, diff) = try await run(item)
            // Anchored once, here, because it needs the diff — and the diff
            // exists only in the worktree the review just ran in. By the time
            // anybody is ticking boxes it is gone.
            let prepared = AutoReviewComment.prepare(findings, diff: diff)
            let composed = AutoReviewComment.compose(
                prepared, skill: Prefs.reviewSkill ?? "", pingKey: key)

            var seconds: TimeInterval?
            update(key) { record in
                // Stamped here, where the run actually ended, and not inferred
                // later from `finishedAt` — posting rewrites that.
                record.runSeconds = record.startedAt.map { -$0.timeIntervalSinceNow }
                seconds = record.runSeconds
                record.counts = findings.counts
                record.body = composed.body
                record.threads = composed.threads
                record.prepared = prepared
                record.status = .ready
                record.finishedAt = Date()
            }
            consecutiveFailures = 0
            recordTrophyFacts(findings, seconds: seconds)

            if state.reviewMode.postsWithoutAsking {
                await post(item, composed)
            }
        } catch let failure as AutoReviewFailure {
            // The hour's ceiling is a ceiling on reviews, and a run that never
            // reached the skill was not one. Left counted, a repository the
            // network could not be bothered with would eat the whole hour's
            // budget in about four seconds.
            if !failure.ranTheSkill,
               let index = startTimes.lastIndex(of: startedAt) {
                startTimes.remove(at: index)
            }
            fail(key, failure.message, ranTheSkill: failure.ranTheSkill)
        } catch {
            fail(key, AutoReviewRecord.truncated(error.localizedDescription))
        }
    }

    /// Runs the skill and returns its findings, or throws the reason there are
    /// none. Never returns an empty result in place of a failure — a clean bill
    /// of health nobody earned is the worst thing this can produce.
    private func run(_ item: ReviewItem) async throws -> (AutoReviewFindings, DiffMap) {
        guard let claude = state.claudePath else { throw AutoReviewFailure.notInstalled }
        guard let skill = ReviewSkill.normalized(state.reviewSkillDraft) else {
            throw AutoReviewFailure.unparseable("no review skill is configured")
        }
        let worktree = try await checkout(item)
        defer { removeWorktree(worktree) }

        let request = AutoReviewRequest(
            skill: skill, repo: item.repo, number: item.number, url: item.url,
            model: Prefs.reviewModel, budgetUSD: Prefs.reviewBudget)

        let result = try await ProcessRunner.run(
            executable: claude,
            arguments: ClaudeInvocation.arguments(for: request),
            workingDirectory: worktree.path,
            environment: ProcessRunner.environment(extraPaths: state.helperPaths()),
            timeout: Self.timeout)

        let findings = try AutoReviewParser.parse(
            exitCode: result.exitCode, stdout: result.stdout, stderr: result.stderr,
            timedOut: result.timedOut, timeoutSeconds: Int(Self.timeout)).get()

        // The map is built from the worktree we just reviewed in, so a finding's
        // line numbers and the diff's agree by construction. An empty diff is
        // not fatal: every finding then falls back to the summary body rather
        // than being dropped.
        return (findings, DiffMap.parse(unifiedDiff: worktree.diff))
    }

    // MARK: - The checkout

    private struct Worktree {
        let clone: URL
        let path: URL
        let diff: String
    }

    /// Fetches the PR head into the user's own clone and checks it out in a
    /// throwaway worktree, so their working tree is never touched.
    private func checkout(_ item: ReviewItem) async throws -> Worktree {
        guard let root = Prefs.reviewWorkspace,
              let clone = await state.findCheckout(of: item.repo, under: root)
        else { throw AutoReviewFailure.noClone(item.repo) }

        let ref = Workspace.ref(forPR: item.number)
        _ = try await Self.fetch(["-C", clone.path, "fetch", "origin", "--force",
                                  Workspace.fetchRefspec(forPR: item.number)])

        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent(Workspace.worktreeName(
                forPR: item.number, token: String(UUID().uuidString.prefix(8))))
        _ = try await Self.runGit(["-C", clone.path, "worktree", "add", "--detach",
                                   path.path, ref])

        // Left before any reviewing starts, so another copy of the app launching
        // midway through this review can tell that it is somebody's and not
        // litter to be swept up.
        try? String(ProcessInfo.processInfo.processIdentifier).write(
            toFile: path.appendingPathComponent(Workspace.ownerMarker).path,
            atomically: true, encoding: .utf8)

        // The diff comes from here rather than from a second API call: the
        // RIGHT-side line numbers an inline comment needs are numbers in the
        // head blob, and the head blob is exactly what has just been checked
        // out — so they agree by construction.
        //
        // Against the pull request's *own* base, which `origin/HEAD` is not.
        // A pull request onto a long-running sprint branch diffed against the
        // default branch appears to change everything that branch has done
        // since it forked — 513 files for one that touched 39, on the pull
        // request that turned this up. Every extra line then looks commentable,
        // GitHub refuses the anchor with "Line could not be resolved", and
        // because a review posts as one mutation the *whole* review is lost
        // rather than the one bad thread. The skill was already being told to
        // use the pull request's own base; this is the diff agreeing with it.
        let range = await diffRange(for: item, clone: clone, worktree: path)
        let diff = (try? await Self.runGit(["-C", path.path, "diff", "--unified=3", range])) ?? ""

        return Worktree(clone: clone, path: path, diff: diff)
    }

    /// What to diff the checked-out head against.
    ///
    /// Three answers, in descending order of how much they actually know:
    /// the pull request's declared base, then the repository's default branch,
    /// then the head's own parent. The last two are guesses and are only
    /// reached when the first is unavailable — a base GitHub did not report, or
    /// one the fetch could not find, such as a branch already deleted after a
    /// merge.
    private func diffRange(for item: ReviewItem, clone: URL, worktree: URL) async -> String {
        if let branch = item.baseRef, !branch.isEmpty {
            let target = Workspace.baseRef(forPR: item.number)
            let fetched = try? await Self.fetch(
                ["-C", clone.path, "fetch", "origin", "--force",
                 Workspace.baseRefspec(branch: branch, forPR: item.number)])
            if fetched != nil,
               let merge = try? await Self.runGit(
                   ["-C", worktree.path, "merge-base", "HEAD", target]),
               case let base = merge.trimmingCharacters(in: .whitespacesAndNewlines),
               !base.isEmpty {
                return "\(base)..HEAD"
            }
            Log.debug("base \(branch) unavailable for \(item.repo)#\(item.number); "
                      + "falling back")
        }
        if let merge = try? await Self.runGit(
            ["-C", worktree.path, "merge-base", "HEAD", "origin/HEAD"]),
           case let base = merge.trimmingCharacters(in: .whitespacesAndNewlines),
           !base.isEmpty {
            return "\(base)..HEAD"
        }
        return "HEAD~1..HEAD"
    }

    /// Always, whatever happened: a worktree left behind is litter in somebody
    /// else's repository.
    private func removeWorktree(_ worktree: Worktree) {
        Task.detached {
            _ = try? await Self.runGit(["-C", worktree.clone.path, "worktree",
                                        "remove", "--force", worktree.path.path])
        }
    }

    /// Every git this class runs is preparing a checkout, never reviewing, so
    /// it throws `.checkout` rather than the `.exited` a skill produces.
    ///
    /// That used to be the same case, and the collision is what made a resolver
    /// blinking indistinguishable from a review that ran and failed: the row
    /// said "The review failed", the attempt was spent, and the strike was
    /// counted. Nothing had reviewed anything.
    private static func runGit(_ arguments: [String]) async throws -> String {
        guard let git = ProcessRunner.firstExecutable(
            among: ["/usr/bin/git", "/opt/homebrew/bin/git", "/usr/local/bin/git"])
        else { throw AutoReviewFailure.checkout("git was not found") }

        let result = try await ProcessRunner.run(
            executable: git, arguments: arguments, timeout: 120)
        guard result.exitCode == 0 else {
            throw AutoReviewFailure.checkout(
                result.stderr.isEmpty ? "git exited with code \(result.exitCode)"
                                      : result.stderr)
        }
        return result.stdout
    }

    /// A git that reaches the network, asked again while the fault reads as the
    /// network's rather than the repository's. See `GitFault`.
    ///
    /// Here rather than in `runGit` because most of what this class runs is
    /// local — a worktree, a merge-base — and a local command that failed will
    /// fail again in two seconds. Only the fetches have anything to gain.
    private static func fetch(_ arguments: [String]) async throws -> String {
        for delay in GitFault.retryDelays {
            do { return try await runGit(arguments) }
            catch let failure as AutoReviewFailure where failure.isWorthRetrying {
                Log.debug("fetch failed on the network — asking again in "
                          + "\(Int(delay))s: \(failure.message)")
                try? await Task.sleep(for: .seconds(delay))
            }
        }
        return try await runGit(arguments)
    }

    // MARK: - Posting and deciding

    /// What the shelf is allowed to remember about a finished review.
    ///
    /// Counted and flagged here rather than read back off the log later: the
    /// log prunes, and a tally that forgets is not a tally. Only successes are
    /// counted — a run that failed reviewed nothing.
    private func recordTrophyFacts(_ findings: AutoReviewFindings, seconds: TimeInterval?) {
        state.trophyState.bump(TrophyState.Counters.reviewsRun)
        if let seconds, seconds < 120 {
            state.trophyState.record(TrophyFact.reviewWasQuick)
        }
        if findings.counts[FindingTier.priority.rawValue, default: 0] > 0 {
            state.trophyState.record(TrophyFact.reviewFoundPriority)
        }
    }

    private func post(_ item: ReviewItem, _ composed: ComposedReview) async {
        guard let client = client(for: item), let nodeID = item.nodeID else { return }
        do {
            let review = try await client.submitReview(
                pullRequestID: nodeID, event: .comment,
                body: composed.body, threads: composed.threads)
            record(review, for: item)
        } catch {
            // A review goes out as one mutation, so GitHub refusing a single
            // anchor — "Line could not be resolved" — takes every other finding
            // with it. Nothing is wrong with the *review* in that case, only
            // with where one comment was pinned, so the summary goes out on its
            // own rather than the work being thrown away.
            //
            // Only worth trying when there were threads to be the problem.
            guard !composed.threads.isEmpty else {
                fail(item.pingKey, AutoReviewRecord.truncated(error.localizedDescription))
                return
            }
            Log.debug("posting \(item.repo)#\(item.number) with "
                      + "\(composed.threads.count) thread(s) failed: "
                      + "\(error.localizedDescription) — retrying as a summary")
            do {
                let review = try await client.submitReview(
                    pullRequestID: nodeID, event: .comment,
                    body: composed.body + AutoReviewComment.anchorsDroppedNote,
                    threads: [])
                record(review, for: item)
            } catch {
                fail(item.pingKey, AutoReviewRecord.truncated(error.localizedDescription))
            }
        }
    }

    /// Writes down a review that went out, however it went out.
    private func record(_ review: SubmittedReview, for item: ReviewItem) {
        update(item.pingKey) { record in
            record.status = .posted
            // Kept now, because this is the moment the row stops being
            // reachable: the review we have just submitted fulfils the
            // request, GitHub drops us from the reviewers, and the next
            // poll cannot find this pull request at all. The live item is
            // in hand here and nowhere later.
            record.subject = item
            record.reviewNodeID = review.id
            record.reviewURLString = review.url
            record.threadNodeIDs = review.commentIDs
            record.finishedAt = Date()
            record.failure = nil
            // Drafts, now that they are real comments on the PR. Keeping
            // them would grow the stored blob by a review's worth of prose
            // per pull request, to say something `threadNodeIDs` already
            // says better.
            record.threads = []
            record.prepared = []
            // Including what you wrote. It is on the pull request now, so
            // keeping the draft would only let a later press send it twice.
            record.authored = []
        }
    }

    /// One press per row at a time.
    ///
    /// Nothing about a row changes while its mutation is in the air — posting
    /// leaves the record at `ready` until GitHub answers — so for the second or
    /// so it takes, the row goes on drawing the enabled button that started it.
    /// Pressing it again submitted the whole review a second time: same body,
    /// same inline threads, one second apart, and GitHub accepted both.
    ///
    /// Released in every case, including a thrown one. A row held shut by a
    /// failure would be worse than the duplicate, because at least the
    /// duplicate did what was asked.
    func act(_ action: Action, on item: ReviewItem) {
        let key = item.pingKey
        guard state.rowActions.begin(key) else { return }
        Task {
            await perform(action, on: item)
            state.rowActions.end(key)
        }
    }

    private func perform(_ action: Action, on item: ReviewItem) async {
        let key = item.pingKey
        guard let record = state.autoReviewLog[key] else { return }

        switch action {
        case .commentOnly:
            // No network call at all. Dropping the pin is the whole of it: our
            // own review goes back to being ordinary activity newer than the
            // ping, and the existing rule hides the row by itself.
            update(key) { $0.status = .dismissed; $0.finishedAt = Date() }

        case .post:
            // Recomposed from the ticks as they stand, not from what was
            // composed when the review finished — the whole point of curated
            // mode is that the two differ.
            let chosen = record.sendable.isEmpty
                ? record.heldReview
                : AutoReviewComment.compose(record.sendable,
                                            skill: Prefs.reviewSkill ?? "",
                                            pingKey: key)
            guard let chosen, !chosen.body.isEmpty else { return }
            await post(item, chosen)

        case .approve:
            await submit(.approve, body: nil, on: item)

        case .requestChanges:
            await submit(.requestChanges, body: record.body, on: item)

        case .rerun:
            await supersede(record, on: item)
            update(key) { record in
                record.status = .queued
                // `failure` is deliberately left alone. Only `failed` and
                // `skipped` rows ever show it, so a stale one cannot reach the
                // screen — and clearing it here meant pressing Retry destroyed
                // the only record of what went wrong, which is precisely what
                // somebody does before asking why it went wrong.
                record.reviewNodeID = nil
                record.threadNodeIDs = []
            }
            refreshLanded()
        }
    }

    private func submit(_ event: ReviewEvent, body: String?, on item: ReviewItem) async {
        guard let client = client(for: item), let nodeID = item.nodeID else { return }
        do {
            _ = try await client.submitReview(pullRequestID: nodeID, event: event,
                                              body: body, threads: [])
            // Approve and Request-changes only. "Comment only" does not reach
            // here, and it is deliberately not a verdict — it is letting the
            // posted review stand without adding one.
            state.trophyState.record(TrophyFact.reviewDecided)
            // Dismissed as well as cleared server-side: GitHub drops the review
            // request, but the refresh between the mutation landing and the
            // search catching up would otherwise look like an un-reviewed ping.
            update(item.pingKey) { $0.status = .dismissed; $0.finishedAt = Date() }
        } catch {
            update(item.pingKey) {
                $0.failure = AutoReviewRecord.truncated(error.localizedDescription)
            }
        }
    }

    /// Retires the previous review rather than letting two of them stand.
    private func supersede(_ record: AutoReviewRecord, on item: ReviewItem) async {
        guard let client = client(for: item), let reviewID = record.reviewNodeID else { return }
        try? await client.updateReview(
            id: reviewID, body: AutoReviewComment.supersededBody(pingKey: item.pingKey))
        for threadID in record.threadNodeIDs {
            await client.resolveThread(id: threadID)
        }
    }

    /// The client for the account that surfaced this row.
    ///
    /// Not whichever account is active in `gh`. Reviewing as the wrong identity
    /// is invisible with one account configured and embarrassing with two.
    private func client(for item: ReviewItem) -> GitHubClient? {
        guard let account = state.accounts.first(where: { $0.id == item.account })
                ?? state.accounts.first,
              let token = Accounts.token(for: account)
        else { return nil }
        return GitHubClient(token: token)
    }

    // MARK: - Bookkeeping

    private func update(_ key: String, _ change: (inout AutoReviewRecord) -> Void) {
        var record = state.autoReviewLog[key] ?? AutoReviewRecord()
        change(&record)
        state.autoReviewLog[key] = record
    }

    /// Writes down a failure, and decides whether it counts.
    ///
    /// `ranTheSkill` is the whole of that decision — see
    /// `AutoReviewFailure.ranTheSkill`. A run stopped before the skill started
    /// still becomes a `failed` record, because the row has to say something
    /// and an hour's backoff is the right pace to try again at; it simply does
    /// not spend the pull request's attempts or move the feature closer to
    /// switching itself off.
    private func fail(_ key: String, _ message: String, ranTheSkill: Bool = true) {
        // Logged as well as stored. The record is the only other copy and it is
        // routinely overwritten — a retry starts by clearing the row — so
        // without this a failure that somebody retried before mentioning it
        // leaves nothing behind to diagnose.
        //
        // Worded by which of the two it was, because the log is where this
        // gets diagnosed and the old line said "review failed" for a fetch that
        // never reached the network — an hour of reading it as a skill that
        // kept producing the same error.
        Log.debug((ranTheSkill ? "review failed [" : "review did not start [")
                  + "\(key)]: \(message)")
        if ranTheSkill { consecutiveFailures += 1 }
        update(key) { record in
            if record.runSeconds == nil {
                record.runSeconds = record.startedAt.map { -$0.timeIntervalSinceNow }
            }
            // Handed back, so two bad fetches cannot exhaust a pull request's
            // budget without a word of it having been read.
            if !ranTheSkill { record.attempts = max(0, record.attempts - 1) }
            record.status = .failed
            record.failure = message
            record.finishedAt = Date()
        }
    }
}
