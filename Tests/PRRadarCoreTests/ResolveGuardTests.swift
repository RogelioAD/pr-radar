import XCTest
@testable import PRRadarCore

/// What stops a resolve run, and in what order.
///
/// These matter more than most tests in this package: everything below is the
/// only thing standing between an unattended Claude Code session and somebody's
/// working tree.
final class ResolveGuardTests: XCTestCase {

    // MARK: - Reading git

    private let porcelain = """
    worktree /Users/me/code/app
    HEAD a1b2c3d4
    branch refs/heads/main

    worktree /Users/me/code/app-feat
    HEAD e4f5a6b7
    branch refs/heads/feat/thing

    worktree /Users/me/code/app-detached
    HEAD 99887766
    detached

    """

    func testWorktreesAreReadBlockByBlock() {
        let entries = GitWorktrees.parse(porcelain: porcelain)
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[1].path, "/Users/me/code/app-feat")
        XCTAssertEqual(entries[1].branch, "refs/heads/feat/thing")
        XCTAssertEqual(entries[1].branchName, "feat/thing")
        XCTAssertNil(entries[2].branch, "a detached head is not a branch")
    }

    /// A branch with a slash is the case that a "take the last path component"
    /// shortcut gets wrong, and this repo's branches all have one.
    func testABranchWithSlashesMatchesItsOwnTree() throws {
        let entries = GitWorktrees.parse(porcelain: porcelain)
        let found = try GitWorktrees.holding(branch: "feat/thing", in: entries).get()
        XCTAssertEqual(found?.path, "/Users/me/code/app-feat")
    }

    func testABranchCheckedOutNowhereIsNotAFailureButIsNotATree() throws {
        let entries = GitWorktrees.parse(porcelain: porcelain)
        XCTAssertNil(try GitWorktrees.holding(branch: "feat/other", in: entries).get())
    }

    func testALockedTreeIsReportedRatherThanUsed() {
        let entries = GitWorktrees.parse(porcelain: """
        worktree /Users/me/code/app-feat
        HEAD e4f5a6b7
        branch refs/heads/feat/thing
        locked building a release

        """)
        guard case .failure(.locked(_, let reason)) =
                GitWorktrees.holding(branch: "feat/thing", in: entries) else {
            return XCTFail("a locked tree must not be offered as somewhere to work")
        }
        XCTAssertEqual(reason, "building a release")
    }

    func testBareAndPrunableAreRead() {
        let entries = GitWorktrees.parse(porcelain: """
        worktree /Users/me/code/app.git
        bare

        worktree /Users/me/gone
        HEAD aa
        branch refs/heads/gone
        prunable gitdir file points to non-existent location

        """)
        XCTAssertTrue(entries[0].isBare)
        XCTAssertTrue(entries[1].isPrunable)
    }

    // MARK: - Reading status

    /// The rule the whole guard turns on. A repository with untracked build
    /// output is every real repository, and refusing those refuses everything.
    func testUntrackedFilesDoNotCountAsWorkInProgress() {
        let status = GitStatus.parse(porcelainV2: """
        # branch.head feat/thing
        # branch.upstream origin/feat/thing
        # branch.ab +0 -0
        ? generated/bindings.swift
        ? target/debug/build
        """)
        XCTAssertEqual(status.untracked.count, 2)
        XCTAssertTrue(status.tracked.isEmpty)
        XCTAssertTrue(status.isSafeToWorkIn, "untracked build output is not somebody's work")
    }

    func testATrackedChangeIsWorkInProgress() {
        let status = GitStatus.parse(porcelainV2: """
        # branch.head feat/thing
        1 .M N... 100644 100644 100644 aaa bbb Sources/A.swift
        """)
        XCTAssertEqual(status.tracked, ["Sources/A.swift"])
        XCTAssertFalse(status.isSafeToWorkIn)
    }

    func testAPathWithSpacesSurvives() {
        let status = GitStatus.parse(porcelainV2:
            "1 .M N... 100644 100644 100644 aaa bbb Sources/My File.swift")
        XCTAssertEqual(status.tracked, ["Sources/My File.swift"])
    }

    func testARenameReportsTheNewNameOnly() {
        let status = GitStatus.parse(porcelainV2:
            "2 R. N... 100644 100644 100644 aaa bbb R100 Sources/New.swift\tSources/Old.swift")
        XCTAssertEqual(status.tracked, ["Sources/New.swift"])
    }

    func testBranchUpstreamAndDivergenceAreRead() {
        let status = GitStatus.parse(porcelainV2: """
        # branch.head feat/thing
        # branch.upstream origin/feat/thing
        # branch.ab +2 -3
        """)
        XCTAssertEqual(status.branch, "feat/thing")
        XCTAssertEqual(status.upstream, "origin/feat/thing")
        XCTAssertEqual(status.ahead, 2)
        XCTAssertEqual(status.behind, 3)
    }

    func testADetachedHeadIsNoBranchRatherThanABranchCalledDetached() {
        XCTAssertNil(GitStatus.parse(porcelainV2: "# branch.head (detached)").branch)
    }

    func testAConflictIsCountedApartFromAnOrdinaryChange() {
        let status = GitStatus.parse(porcelainV2:
            "u UU N... 100644 100644 100644 100644 aa bb cc Sources/A.swift")
        XCTAssertEqual(status.conflicted, ["Sources/A.swift"])
        XCTAssertTrue(status.tracked.isEmpty)
        XCTAssertFalse(status.isSafeToWorkIn)
    }

    // MARK: - The ordered rule

    private func pr(head: String = "feat/thing",
                    oid: String? = "e4f5a6b7",
                    owner: String? = "acme") -> MyPullRequest {
        var item = MyPullRequest(
            repo: "acme/app", number: 1, title: "t",
            url: URL(string: "https://github.com/acme/app/pull/1")!, isDraft: false,
            createdAt: Date(), updatedAt: Date(),
            headRefName: head, baseRefName: "main",
            reviewDecision: .reviewRequired, mergeBlocker: .clean,
            approvals: [], awaitingReviewers: [], unresolvedThreadCount: 1,
            totalThreadCount: 1, checks: .empty,
            additions: 1, deletions: 1, changedFiles: 1)
        item.headOid = oid
        item.headRepositoryOwner = owner
        return item
    }

    /// Everything in order, so a probe that reaches the end really has passed
    /// each one rather than skipped it.
    private func readyProbe() -> ResolveProbe {
        var probe = ResolveProbe()
        probe.claudePath = "/usr/local/bin/claude"
        probe.skill = "/resolve"
        probe.isAllowed = true
        probe.workspace = "/Users/me/code"
        probe.clone = "/Users/me/code/app"
        probe.worktrees = GitWorktrees.parse(porcelain: porcelain)
        probe.localHead = "e4f5a6b7"
        probe.status = GitStatus(branch: "feat/thing", upstream: "origin/feat/thing")
        return probe
    }

    func testAFullyReadyTreeIsNotBlocked() {
        XCTAssertNil(ResolveGuard.evaluate(readyProbe(), pr: pr()))
    }

    func testConfigurationIsAskedAboutBeforeTheDisk() {
        var probe = readyProbe()
        probe.skill = nil
        // Also broken further down, to prove the order rather than the outcome.
        probe.clone = nil
        XCTAssertEqual(ResolveGuard.evaluate(probe, pr: pr()), .noSkill)
    }

    func testAForkIsRefusedBeforeAnythingTouchesTheDisk() {
        var probe = readyProbe()
        probe.clone = nil
        XCTAssertEqual(ResolveGuard.evaluate(probe, pr: pr(owner: "someone-else")),
                       .fork(owner: "someone-else"))
    }

    func testABranchCheckedOutNowhereRefusesRatherThanCheckingItOut() {
        XCTAssertEqual(ResolveGuard.evaluate(readyProbe(), pr: pr(head: "feat/other")),
                       .notCheckedOut(branch: "feat/other", clone: "/Users/me/code/app"))
    }

    func testADirtyTreeRefusesAndSaysHowMany() {
        var probe = readyProbe()
        probe.status = GitStatus(tracked: ["A.swift", "B.swift"],
                                 upstream: "origin/feat/thing")
        XCTAssertEqual(ResolveGuard.evaluate(probe, pr: pr()),
                       .dirty(path: "/Users/me/code/app-feat", count: 2))
    }

    func testUntrackedFilesAloneDoNotRefuse() {
        var probe = readyProbe()
        probe.status = GitStatus(untracked: ["generated/x.swift"],
                                 upstream: "origin/feat/thing")
        XCTAssertNil(ResolveGuard.evaluate(probe, pr: pr()))
    }

    func testAnUnfinishedOperationRefusesBeforeTheTreeIsJudgedClean() {
        var probe = readyProbe()
        probe.operation = .rebase
        XCTAssertEqual(ResolveGuard.evaluate(probe, pr: pr()),
                       .operationInProgress(.rebase, path: "/Users/me/code/app-feat"))
    }

    /// Both directions. Ahead is the one that looks harmless and is not: those
    /// are commits nobody has seen, which a run would build on and then push.
    func testACheckoutThatDisagreesWithThePullRequestRefusesEitherWay() {
        var behind = readyProbe()
        behind.localHead = "0000000"
        XCTAssertEqual(ResolveGuard.evaluate(behind, pr: pr()),
                       .headMismatch(path: "/Users/me/code/app-feat",
                                     local: "0000000", expected: "e4f5a6b7"))

        var ahead = readyProbe()
        ahead.localHead = "ffffffff"
        XCTAssertNotNil(ResolveGuard.evaluate(ahead, pr: pr()))
    }

    func testABranchWithNoUpstreamRefusesBecauseAShaWouldNotBeTrue() {
        var probe = readyProbe()
        probe.status = GitStatus(branch: "feat/thing", upstream: nil)
        XCTAssertEqual(ResolveGuard.evaluate(probe, pr: pr()),
                       .noUpstream(branch: "feat/thing", path: "/Users/me/code/app-feat"))
    }

    func testOneRunPerTree() {
        var probe = readyProbe()
        probe.leaseHeldAt = "/Users/me/code/app-feat"
        XCTAssertEqual(ResolveGuard.evaluate(probe, pr: pr()),
                       .alreadyRunning(path: "/Users/me/code/app-feat"))
    }

    /// A run already working in the tree has usually *made* the mess this would
    /// otherwise complain about — it commits, so the head moves ahead of the
    /// pull request. Reporting that as a stale checkout sends the user off to
    /// fix a tree that is being used exactly as intended.
    func testARunInProgressIsNamedBeforeTheMessItIsMaking() {
        var probe = readyProbe()
        probe.leaseHeldAt = "/Users/me/code/app-feat"
        probe.localHead = "ffffffff"
        probe.status = GitStatus(tracked: ["A.swift"], upstream: "origin/feat/thing")
        probe.operation = .merge
        XCTAssertEqual(ResolveGuard.evaluate(probe, pr: pr()),
                       .alreadyRunning(path: "/Users/me/code/app-feat"))
    }

    /// The button's own test: it is drawn from configuration alone, because
    /// probing every row every poll would be a subprocess per row per minute.
    func testTheButtonIsDecidedWithoutTouchingTheDisk() {
        var probe = ResolveProbe()
        probe.claudePath = "/bin/claude"
        probe.skill = "/resolve"
        probe.isAllowed = true
        XCTAssertNil(ResolveGuard.configuration(probe, pr: pr()))

        probe.isAllowed = false
        XCTAssertEqual(ResolveGuard.configuration(probe, pr: pr()),
                       .notAllowed(repo: "acme/app"))
    }

    // MARK: - What the row says

    func testEveryRefusalSaysSomething() {
        let blocks: [ResolveBlock] = [
            .noClaude, .noSkill, .notAllowed(repo: "acme/app"), .fork(owner: "them"),
            .noWorkspace, .noClone(repo: "acme/app"),
            .notCheckedOut(branch: "feat/x", clone: "/c"),
            .severalTrees(branch: "feat/x", paths: ["/a", "/b"]),
            .lockedTree(path: "/a", reason: nil), .bareTree(path: "/a"),
            .operationInProgress(.merge, path: "/a"),
            .dirty(path: "/a", count: 2), .conflicted(path: "/a", count: 1),
            .headMismatch(path: "/a", local: "aaaaaaaa", expected: "bbbbbbbb"),
            .noUpstream(branch: "feat/x", path: "/a"),
            .alreadyRunning(path: "/a"),
        ]
        for block in blocks {
            XCTAssertFalse(block.reason.isEmpty, "\(block) says nothing")
            XCTAssertFalse(block.reason.hasSuffix("."), "\(block) is a chip, not a sentence")
        }
    }

    func testOneChangeIsNotPluralised() {
        XCTAssertTrue(ResolveBlock.dirty(path: "/a", count: 1).reason
            .contains("1 uncommitted change in"))
        XCTAssertTrue(ResolveBlock.dirty(path: "/a", count: 3).reason
            .contains("3 uncommitted changes in"))
    }

    func testAMismatchNamesBothCommitsShortened() {
        let reason = ResolveBlock.headMismatch(path: "/a", local: "a1b2c3d4e5",
                                               expected: "f6e5d4c3b2").reason
        XCTAssertTrue(reason.contains("a1b2c3d"), reason)
        XCTAssertTrue(reason.contains("f6e5d4c"), reason)
    }
}
