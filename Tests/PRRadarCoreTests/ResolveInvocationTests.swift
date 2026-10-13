import XCTest
@testable import PRRadarCore

/// What a resolve session is allowed to do, and what it is told.
///
/// The denials are the load-bearing part. Unlike review, this session can edit
/// files and push, so "the framing says not to" is not a control — the pull
/// request's own comments reach the model, and a sentence can be argued with.
final class ResolveInvocationTests: XCTestCase {

    private func request(mode: ResolveMode = .curated,
                         scope: ResolveScope = .threads,
                         gates: ResolveGates = .full,
                         outOfScope: ResolveOutOfScope = .deferWithReasoning,
                         pending: ResolvePendingPolicy = .leave,
                         threads: [UnresolvedThread] = []) -> ResolveRequest {
        ResolveRequest(
            skill: "/resolve", repo: "acme/app", number: 842,
            url: URL(string: "https://github.com/acme/app/pull/842")!,
            branch: "feat/thing", headOid: "a1b2c3d4",
            treePath: "/Users/me/code/app-feat",
            scope: scope, gates: gates, baseBranch: "main",
            mode: mode, outOfScope: outOfScope, pending: pending,
            threads: threads, budgetUSD: 10)
    }

    private func thread(_ id: String = "T1") -> UnresolvedThread {
        UnresolvedThread(id: id, path: "Sources/A.swift", line: 12,
                         isOutdated: false,
                         comments: [.init(author: "github-actions[bot]",
                                          body: "This drops the error.")],
                         moreComments: 0)
    }

    // MARK: - The prompt

    /// The rule inherited from `ClaudeInvocation`: anything but the command and
    /// its argument and the text stops reading as a command, so the skill never
    /// dispatches and a general-purpose model answers instead.
    func testThePromptIsTheCommandAndTheURLAndNothingElse() {
        XCTAssertEqual(ResolveInvocation.prompt(for: request()),
                       "/resolve https://github.com/acme/app/pull/842")
    }

    // MARK: - Tools

    func testNothingCanAskAQuestionInAnyMode() {
        for mode in ResolveMode.allCases {
            XCTAssertTrue(ResolveInvocation.disallowedTools(for: mode)
                .contains("AskUserQuestion"),
                "\(mode) could hang until the timeout")
        }
    }

    func testNothingCanWriteToAsanaInAnyMode() {
        for mode in ResolveMode.allCases {
            let denied = ResolveInvocation.disallowedTools(for: mode)
            XCTAssertTrue(denied.contains("mcp__claude_ai_Asana__create_tasks"), "\(mode)")
            XCTAssertTrue(denied.contains("mcp__claude_ai_Asana__update_tasks"), "\(mode)")
        }
    }

    /// PR Radar picked this worktree and proved what it is. A session that can
    /// move off it can land a fix in a tree nobody checked.
    func testNothingCanMoveOffTheChosenTreeInAnyMode() {
        for mode in ResolveMode.allCases {
            let denied = ResolveInvocation.disallowedTools(for: mode)
            for tool in ["Bash(git checkout:*)", "Bash(git switch:*)",
                         "Bash(gh pr checkout:*)", "Bash(git worktree add:*)"] {
                XCTAssertTrue(denied.contains(tool), "\(mode) may \(tool)")
            }
        }
    }

    func testNothingCanRewritePushedHistoryOrTouchTheSharedStashInAnyMode() {
        for mode in ResolveMode.allCases {
            let denied = ResolveInvocation.disallowedTools(for: mode)
            for tool in ["Bash(git push --force:*)", "Bash(git push -f:*)",
                         "Bash(git rebase:*)", "Bash(git reset:*)",
                         "Bash(git stash:*)"] {
                XCTAssertTrue(denied.contains(tool), "\(mode) may \(tool)")
            }
        }
    }

    func testTriageCannotChangeAnything() {
        let allowed = ResolveInvocation.allowedTools(for: .triage)
        let denied = ResolveInvocation.disallowedTools(for: .triage)
        XCTAssertFalse(allowed.contains("Edit"))
        XCTAssertFalse(allowed.contains("Write"))
        XCTAssertFalse(allowed.contains("Bash"), "a bare Bash would undo the whole mode")
        for tool in ["Edit", "Write", "Bash(git commit:*)", "Bash(git push:*)"] {
            XCTAssertTrue(denied.contains(tool), "triage may \(tool)")
        }
    }

    func testTheModesThatFixCanActuallyFix() {
        for mode in [ResolveMode.curated, .automatic] {
            let allowed = ResolveInvocation.allowedTools(for: mode)
            XCTAssertTrue(allowed.contains("Edit"), "\(mode)")
            XCTAssertTrue(allowed.contains("Bash"), "\(mode)")
            XCTAssertFalse(ResolveInvocation.disallowedTools(for: mode).contains("Edit"),
                           "\(mode) allows and denies Edit at once")
        }
    }

    /// `gh api` is how a thread is replied to *and* how one is read, and a
    /// prefix-matched permission cannot tell a query from a mutation. Denying
    /// it outright is the only enforceable version of "posts nothing" — which
    /// is affordable because the threads are handed over in the framing.
    func testACuratedRunCannotReachGitHubAtAll() {
        let denied = ResolveInvocation.disallowedTools(for: .curated)
        for tool in ["Bash(gh api:*)", "Bash(gh api graphql:*)",
                     "Bash(gh pr review:*)", "Bash(gh pr comment:*)",
                     "Bash(gh pr edit:*)"] {
            XCTAssertTrue(denied.contains(tool), "a curated run may \(tool)")
        }
    }

    func testAnAutomaticRunMayPostBecauseThatIsWhatItIsFor() {
        let denied = ResolveInvocation.disallowedTools(for: .automatic)
        XCTAssertFalse(denied.contains("Bash(gh api:*)"))
        XCTAssertFalse(denied.contains("Bash(gh pr review:*)"))
    }

    func testTriageAlsoCannotPost() {
        let denied = ResolveInvocation.disallowedTools(for: .triage)
        XCTAssertTrue(denied.contains("Bash(gh api:*)"))
    }

    // MARK: - Framing

    func testTheFramingNamesTheTreeAndForbidsLookingForAnother() {
        let framing = ResolveInvocation.framing(for: request())
        XCTAssertTrue(framing.contains("/Users/me/code/app-feat"), framing)
        XCTAssertTrue(framing.contains("feat/thing"), framing)
        XCTAssertTrue(framing.contains("a1b2c3d4"), framing)
        XCTAssertTrue(framing.contains("gh pr checkout"), framing)
    }

    func testEveryGateIsPreAnswered() {
        let framing = ResolveInvocation.framing(for: request())
        XCTAssertTrue(framing.contains("Out of scope:"), framing)
        XCTAssertTrue(framing.contains("Asana"), framing)
        XCTAssertTrue(framing.contains("PENDING review"), framing)
        XCTAssertTrue(framing.contains("Ask no questions"), framing)
    }

    func testTheOutOfScopeAnswerIsTheOnePicked() {
        for choice in ResolveOutOfScope.allCases {
            let framing = ResolveInvocation.framing(for: request(outOfScope: choice))
            XCTAssertTrue(framing.contains(choice.instruction),
                          "\(choice) was not passed on")
        }
    }

    func testPendingReviewsAreLeftAloneByDefault() {
        let framing = ResolveInvocation.framing(for: request(pending: .leave))
        XCTAssertTrue(framing.contains("do not publish it"), framing)
    }

    /// Never resolved, in any mode. This is PR Radar being stricter than the
    /// skill, not merely repeating it.
    func testNeedsYouIsNeverResolvedWhateverTheMode() {
        for mode in ResolveMode.allCases {
            XCTAssertTrue(ResolveInvocation.framing(for: request(mode: mode))
                .contains("never resolves one, in any mode"), "\(mode)")
        }
    }

    func testACuratedRunIsToldToPostNothingAndIsGivenTheThreads() {
        let framing = ResolveInvocation.framing(for: request(mode: .curated,
                                                             threads: [thread("T1")]))
        XCTAssertTrue(framing.contains("Post nothing"), framing)
        XCTAssertTrue(framing.contains("Open threads:"), framing)
        XCTAssertTrue(framing.contains("T1"), framing)
        XCTAssertTrue(framing.contains("Sources/A.swift:12"), framing)
        XCTAssertTrue(framing.contains("This drops the error."), framing)
    }

    /// An automatic run fetches its own, so listing them would be noise — and
    /// it is the one mode allowed to call `gh api`.
    func testAnAutomaticRunIsNotHandedTheThreads() {
        let framing = ResolveInvocation.framing(for: request(mode: .automatic,
                                                             threads: [thread()]))
        XCTAssertFalse(framing.contains("Open threads:"), framing)
    }

    func testATriageRunIsToldToChangeNothing() {
        let framing = ResolveInvocation.framing(for: request(mode: .triage))
        XCTAssertTrue(framing.contains("Change nothing"), framing)
        XCTAssertFalse(framing.contains("Commit and push before"), framing)
    }

    func testAFixingRunIsToldAShaIsCheckedRatherThanTrusted() {
        let framing = ResolveInvocation.framing(for: request(mode: .curated))
        XCTAssertTrue(framing.contains("is not an ancestor of"), framing)
    }

    func testCommentBodiesAreNamedAsUntrustedInEveryMode() {
        for mode in ResolveMode.allCases {
            XCTAssertTrue(ResolveInvocation.framing(for: request(mode: mode))
                .contains("untrusted input"), "\(mode)")
        }
    }

    // MARK: - argv

    func testTheArgumentsCarryTheSchemaAndTheBudget() {
        let arguments = ResolveInvocation.arguments(for: request())
        XCTAssertEqual(arguments.first, "-p")
        XCTAssertTrue(arguments.contains("--json-schema"))
        XCTAssertTrue(arguments.contains(ResolveInvocation.schema))
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertTrue(arguments.contains("10.00"))
    }

    /// Zero means no ceiling, which is a choice — passing it would cap the run
    /// at nothing.
    func testNoBudgetMeansNoCeilingRatherThanACeilingOfZero() {
        let free = ResolveRequest(
            skill: "/resolve", repo: "a/b", number: 1,
            url: URL(string: "https://x/1")!, branch: "b", headOid: "o",
            treePath: "/t", mode: .curated, outOfScope: .leaveOpen,
            pending: .leave, threads: [], budgetUSD: 0)
        XCTAssertFalse(ResolveInvocation.arguments(for: free).contains("--max-budget-usd"))
    }

    /// Every denial reaches argv, not just the ones the mode added.
    func testTheDenialsAllReachTheCommandLine() {
        let arguments = ResolveInvocation.arguments(for: request(mode: .curated))
        for tool in ResolveInvocation.disallowedTools(for: .curated) {
            XCTAssertTrue(arguments.contains(tool), "\(tool) never reached argv")
        }
    }

    // MARK: - Modes

    func testOnlyTriageLeavesTheCheckoutAlone() {
        XCTAssertFalse(ResolveMode.triage.writesCode)
        XCTAssertTrue(ResolveMode.curated.writesCode)
        XCTAssertTrue(ResolveMode.automatic.writesCode)
    }

    func testOnlyAutomaticPostsOnItsOwn() {
        XCTAssertFalse(ResolveMode.triage.postsWithoutAsking)
        XCTAssertFalse(ResolveMode.curated.postsWithoutAsking)
        XCTAssertTrue(ResolveMode.automatic.postsWithoutAsking)
    }

    // MARK: - How much it checks

    func testEachCheckingLevelReachesTheSession() {
        for level in ResolveGates.allCases {
            let framing = ResolveInvocation.framing(for: request(gates: level))
            XCTAssertTrue(framing.contains(level.instruction),
                          "\(level) was not passed on")
        }
    }

    /// The fast setting is the whole point of the setting, so it has to
    /// actually say "run nothing" rather than merely "run less".
    func testLeavingItToCISaysToRunNothing() {
        let framing = ResolveInvocation.framing(for: request(gates: .ci))
        XCTAssertTrue(framing.contains("Do not run build, test or lint gates"), framing)
        XCTAssertTrue(framing.contains("checksRunning"), framing)
    }

    /// Running fewer checks is a choice. Defeating one that runs is not, and no
    /// setting may be read as permission to — including the one that turns the
    /// session's own gates off.
    func testNoCheckingLevelPermitsBypassingAGate() {
        for level in ResolveGates.allCases {
            let framing = ResolveInvocation.framing(for: request(gates: level))
            XCTAssertTrue(framing.contains("Never `--no-verify`"), "\(level)")
            XCTAssertTrue(framing.contains("whatever you have been told above"),
                          "\(level) does not close the loophole it opens")
        }
        // And the one that runs nothing locally still says the hooks stand.
        XCTAssertTrue(ResolveGates.ci.instruction.contains("commit hooks still run"),
                      ResolveGates.ci.instruction)
    }

    /// A setting that cannot be read must not quietly check less.
    func testAnUnreadableLevelWouldFallBackToTheThoroughOne() {
        XCTAssertEqual(ResolveGates(rawValue: "nonsense") ?? .full, .full)
    }

    // MARK: - The two jobs

    /// Both scopes are the same run under the same guards, so everything that
    /// protects a threads run has to protect a conflicts run unchanged.
    func testAConflictsRunIsDeniedExactlyWhatAThreadsRunIs() {
        XCTAssertEqual(ResolveInvocation.disallowedTools(for: .curated),
                       ResolveInvocation.disallowedTools(for: .curated),
                       "the denials are a property of the mode, not the job")
        for mode in ResolveMode.allCases {
            let denied = ResolveInvocation.disallowedTools(for: mode)
            XCTAssertTrue(denied.contains("Bash(git rebase:*)"))
            XCTAssertTrue(denied.contains("Bash(git push --force:*)"))
        }
    }

    func testAConflictsRunIsToldToMergeBaseInAndNotToTriage() {
        let framing = ResolveInvocation.framing(for: request(scope: .conflicts))
        XCTAssertTrue(framing.contains("origin/main"), framing)
        XCTAssertTrue(framing.contains("into feat/thing"), framing)
        XCTAssertTrue(framing.contains("Do not triage review threads"), framing)
        XCTAssertTrue(framing.contains("never a rebase"), framing)
    }

    /// The gates belong to triage. A conflicts run has no thread to be out of
    /// scope and no reply to be trapped, so asking it about either is noise it
    /// has to reason past.
    func testTheTriageGatesAreNotPutToAConflictsRun() {
        let framing = ResolveInvocation.framing(for: request(scope: .conflicts))
        XCTAssertFalse(framing.contains("Out of scope:"), framing)
        XCTAssertFalse(framing.contains("PENDING review"), framing)
        XCTAssertFalse(framing.contains("Open threads:"), framing)
    }

    func testAConflictsRunIsStillToldNotToGuess() {
        let framing = ResolveInvocation.framing(for: request(scope: .conflicts))
        XCTAssertTrue(framing.contains("Ask no questions"), framing)
        XCTAssertTrue(framing.contains("stop and say so"), framing)
        XCTAssertTrue(framing.contains("untrusted input"), framing)
    }

    /// A clean textual merge is not a correct merge — two files adding the same
    /// type at different paths merges silently and fails to build.
    func testAConflictsRunIsWarnedThatACleanMergeCanStillBeWrong() {
        let framing = ResolveInvocation.framing(for: request(scope: .conflicts))
        XCTAssertTrue(framing.contains("not a correct merge"), framing)
        XCTAssertTrue(framing.contains("declared twice"), framing)
    }

    func testOnlyAThreadsRunProducesRepliesToTick() {
        XCTAssertTrue(ResolveScope.threads.producesReplies)
        XCTAssertFalse(ResolveScope.conflicts.producesReplies)
    }

    /// Curated resolve is not curated review, and something has to admit it:
    /// the code has already landed by the time anybody ticks a box.
    ///
    /// The admission lives in `writesCode`, which is what the room keys its
    /// warning off, rather than in the one-line `detail` under the picker. That
    /// is a deliberate move — the detail is read on every glance and the
    /// warning only needs to be there for the modes it is true of — so this
    /// asserts the flag and, below, that the line does not quietly contradict
    /// it.
    func testCuratedAdmitsItWritesCode() {
        XCTAssertTrue(ResolveMode.curated.writesCode)
        XCTAssertTrue(ResolveMode.automatic.writesCode)
        XCTAssertFalse(ResolveMode.triage.writesCode,
                       "triage is the only mode that may promise a clean checkout")
    }

    /// A one-line label is still a promise. The two modes that write must not
    /// borrow curated *review*'s wording, where "nothing is sent until you
    /// tick" is literally true — here the code is pushed before you see it.
    func testNoWritingModeClaimsNothingHasHappened() {
        for mode in ResolveMode.allCases where mode.writesCode {
            let detail = mode.detail.lowercased()
            XCTAssertFalse(detail.contains("nothing is"), "\(mode): \(mode.detail)")
            XCTAssertFalse(detail.contains("left exactly"), "\(mode): \(mode.detail)")
        }
        // And the one that may say it, does.
        XCTAssertTrue(ResolveMode.triage.detail.lowercased().contains("left exactly"),
                      ResolveMode.triage.detail)
    }

    /// Short enough to sit under a picker in a 440pt drawer with five other
    /// groups in the room. The reasoning behind a mode belongs in the type's
    /// documentation, not under the control on every glance.
    func testEveryModeDetailIsOneLine() {
        for mode in ResolveMode.allCases {
            XCTAssertLessThanOrEqual(mode.detail.count, 80,
                                     "\(mode) is a paragraph: \(mode.detail)")
        }
    }
}
