import XCTest
@testable import PRRadarCore

final class MyPRInboxTests: XCTestCase {

    let inbox = MyPRInbox(leadLogins: ["ec-boston", "ulises-codes",
                                       "mattiatelevation", "ec-danjocha"])

    func decode(_ json: String) throws -> MyPRSearchResult {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MyPRPayload.self, from: Data(json.utf8)).mine
    }

    /// Builds one PR node. `reviews` are (login, state) pairs.
    func node(number: Int = 736,
              head: String = "feat/a",
              base: String = "main",
              decision: String = "REVIEW_REQUIRED",
              mergeState: String = "BLOCKED",
              draft: Bool = false,
              created: String = "2026-09-02T18:58:51Z",
              updated: String = "2026-09-16T16:24:42Z",
              reviews: [(String, String)] = [],
              requested: [String] = [],
              threads: [Bool] = [],          // isResolved per thread
              checkRuns: [(String, String)] = [],   // (name, conclusion|status)
              statuses: [(String, String)] = [],    // (context, state)
              additions: Int = 3080,
              deletions: Int = 98,
              files: Int = 22) -> String {
        let reviewNodes = reviews.map { login, state in
            #"{"author":{"login":"\#(login)"},"state":"\#(state)","submittedAt":"2026-09-10T00:00:00Z"}"#
        }.joined(separator: ",")
        let requestNodes = requested.map {
            #"{"requestedReviewer":{"__typename":"User","login":"\#($0)"}}"#
        }.joined(separator: ",")
        let threadNodes = threads.map {
            #"{"isResolved":\#($0),"isOutdated":false}"#
        }.joined(separator: ",")
        let runNodes = checkRuns.map { name, verdict in
            #"{"__typename":"CheckRun","name":"\#(name)","conclusion":"\#(verdict)","status":"COMPLETED"}"#
        }
        let statusNodes = statuses.map { context, state in
            #"{"__typename":"StatusContext","context":"\#(context)","state":"\#(state)"}"#
        }
        let contexts = (runNodes + statusNodes).joined(separator: ",")

        return """
        {
          "number": \(number), "title": "a pull request",
          "url": "https://github.com/elevationchurch/repo/pull/\(number)",
          "isDraft": \(draft),
          "createdAt": "\(created)", "updatedAt": "\(updated)",
          "headRefName": "\(head)", "baseRefName": "\(base)",
          "reviewDecision": "\(decision)", "mergeStateStatus": "\(mergeState)",
          "mergeable": "MERGEABLE",
          "additions": \(additions), "deletions": \(deletions), "changedFiles": \(files),
          "repository": { "nameWithOwner": "elevationchurch/repo" },
          "latestReviews": { "nodes": [\(reviewNodes)] },
          "reviewRequests": { "nodes": [\(requestNodes)] },
          "reviewThreads": { "totalCount": \(threads.count), "nodes": [\(threadNodes)] },
          "commits": { "nodes": [ { "commit": {
            "oid": "abc",
            "statusCheckRollup": {
              "state": "PENDING",
              "contexts": { "totalCount": \(runNodes.count + statusNodes.count),
                            "nodes": [\(contexts)] }
            } } } ] }
        }
        """
    }

    func payload(_ nodes: [String]) -> String {
        """
        {"mine":{"issueCount":\(nodes.count),"nodes":[\(nodes.joined(separator: ","))]}}
        """
    }

    func build(_ nodes: [String]) throws -> [MyPullRequest] {
        inbox.build(from: try decode(payload(nodes)))
    }

    // MARK: - The lead rule

    /// The live shape of PR #736: a lead approved, then the approval was
    /// dismissed by a later commit. GitHub does not count it, so neither do we.
    func testDismissedLeadApprovalDoesNotSatisfyTheLeadGate() throws {
        let items = try build([node(reviews: [("ec-boston", "DISMISSED"),
                                              ("james-wall-elevation", "DISMISSED")])])
        let pr = items[0]
        XCTAssertTrue(pr.needsLead, "a dismissed lead approval must not unblock")
        XCTAssertNil(pr.approvingLead)
        XCTAssertTrue(pr.liveApprovals.isEmpty)
        XCTAssertEqual(pr.dismissedApprovals.count, 2)
    }

    /// The live shape of PR #734: the same lead, but the approval still stands.
    func testLiveLeadApprovalSatisfiesTheLeadGate() throws {
        let items = try build([node(reviews: [("ec-boston", "APPROVED"),
                                              ("benjaminrevelo", "DISMISSED")])])
        let pr = items[0]
        XCTAssertFalse(pr.needsLead)
        XCTAssertEqual(pr.approvingLead?.login, "ec-boston")
        XCTAssertEqual(pr.approvingLead?.shortName, "Boston")
        XCTAssertEqual(pr.dismissedApprovals.map(\.login), ["benjaminrevelo"])
    }

    func testNonLeadApprovalDoesNotSatisfyTheLeadGate() throws {
        let items = try build([node(reviews: [("samiesmlz", "APPROVED"),
                                              ("benjaminrevelo", "APPROVED")])])
        let pr = items[0]
        XCTAssertTrue(pr.needsLead)
        XCTAssertEqual(pr.liveApprovals.count, 2, "they still count as approvals")
        XCTAssertTrue(pr.liveApprovals.allSatisfy { !$0.isLead })
    }

    func testEveryConfiguredLeadCounts() throws {
        for lead in ["ec-boston", "ulises-codes", "mattiatelevation", "ec-danjocha"] {
            let items = try build([node(reviews: [(lead, "APPROVED")])])
            XCTAssertFalse(items[0].needsLead, "\(lead) should satisfy the gate")
        }
    }

    func testChangesRequestedIsSurfaced() throws {
        let items = try build([node(decision: "CHANGES_REQUESTED",
                                    reviews: [("ulises-codes", "CHANGES_REQUESTED")])])
        let pr = items[0]
        XCTAssertEqual(pr.changesRequestedBy.map(\.shortName), ["Ulises"])
        XCTAssertEqual(pr.reviewDecision, .changesRequested)
    }

    /// Bot "COMMENTED" reviews are noise — github-actions comments on every PR.
    func testCommentedReviewsAreDropped() throws {
        let items = try build([node(reviews: [("github-actions", "COMMENTED"),
                                              ("ec-boston", "APPROVED")])])
        XCTAssertEqual(items[0].approvals.map(\.login), ["ec-boston"])
    }

    // MARK: - Checks

    func testChecksTallyAcrossBothContextKinds() throws {
        let items = try build([node(
            checkRuns: [("build", "SUCCESS"), ("test", "FAILURE"),
                        ("lint", "IN_PROGRESS"), ("docs", "SKIPPED")],
            statuses: [("ci/legacy", "SUCCESS"), ("ci/flaky", "PENDING")])])
        let checks = items[0].checks
        XCTAssertEqual(checks.passing, 2)
        XCTAssertEqual(checks.failing, 1)
        XCTAssertEqual(checks.running, 2)
        XCTAssertEqual(checks.skipped, 1)
        XCTAssertEqual(checks.total, 6)
        XCTAssertEqual(checks.failingNames, ["test"])
    }

    func testFailingChecksOutrankRunningAndPassing() throws {
        let items = try build([node(checkRuns: [("a", "SUCCESS"), ("b", "IN_PROGRESS"),
                                                ("c", "FAILURE")])])
        XCTAssertEqual(items[0].checks.health, .bad)
    }

    func testRunningOutranksPassing() throws {
        let items = try build([node(checkRuns: [("a", "SUCCESS"), ("b", "IN_PROGRESS")])])
        XCTAssertEqual(items[0].checks.health, .running)
    }

    func testAllPassingIsGood() throws {
        let items = try build([node(checkRuns: [("a", "SUCCESS"), ("b", "SUCCESS")])])
        XCTAssertEqual(items[0].checks.health, .good)
    }

    func testCancelledAndTimedOutCountAsFailures() throws {
        let items = try build([node(checkRuns: [("a", "CANCELLED"), ("b", "TIMED_OUT")])])
        XCTAssertEqual(items[0].checks.failing, 2)
    }

    func testNeutralAndStaleCountAsSkipped() throws {
        let items = try build([node(checkRuns: [("a", "NEUTRAL"), ("b", "STALE")])])
        XCTAssertEqual(items[0].checks.skipped, 2)
        XCTAssertEqual(items[0].checks.health, .neutral)
    }

    // MARK: - Threads

    func testUnresolvedThreadsAreCounted() throws {
        let items = try build([node(threads: [true, false, false, true, true])])
        XCTAssertEqual(items[0].unresolvedThreadCount, 2)
        XCTAssertEqual(items[0].totalThreadCount, 5)
    }

    /// The live PRs both have every thread resolved, which must read as zero
    /// open rather than as "no threads".
    func testAllResolvedThreadsReportZeroOpen() throws {
        let items = try build([node(threads: Array(repeating: true, count: 14))])
        XCTAssertEqual(items[0].unresolvedThreadCount, 0)
        XCTAssertEqual(items[0].totalThreadCount, 14)
    }

    // MARK: - Merge blockers

    func testMergeBlockerMapping() throws {
        let cases: [(String, MergeBlocker, Health)] = [
            ("CLEAN", .clean, .good),
            ("BLOCKED", .blocked, .attention),
            ("BEHIND", .behind, .attention),
            ("DIRTY", .dirty, .bad),
            ("UNSTABLE", .unstable, .bad),
            ("DRAFT", .draft, .neutral),
        ]
        for (raw, expected, health) in cases {
            let items = try build([node(mergeState: raw)])
            XCTAssertEqual(items[0].mergeBlocker, expected, raw)
            XCTAssertEqual(items[0].mergeBlocker.health, health, raw)
        }
    }

    func testUnknownMergeStateDegradesRatherThanFailing() throws {
        let items = try build([node(mergeState: "SOMETHING_NEW")])
        XCTAssertEqual(items[0].mergeBlocker, .unknown)
    }

    func testOnlyBehindAndDirtyWantARebase() {
        XCTAssertTrue(MergeBlocker.behind.wantsRebase)
        XCTAssertTrue(MergeBlocker.dirty.wantsRebase)
        XCTAssertFalse(MergeBlocker.blocked.wantsRebase)
        XCTAssertFalse(MergeBlocker.clean.wantsRebase)
    }

    // MARK: - Stacks

    /// The live shape: #736's base is #734's head branch.
    func testStackIsLinkedInBothDirections() throws {
        let items = try build([
            node(number: 736, head: "feat/detail", base: "feat/feed"),
            node(number: 734, head: "feat/feed", base: "feat/sprint-18"),
        ])
        let detail = items.first { $0.number == 736 }!
        let feed = items.first { $0.number == 734 }!
        XCTAssertEqual(detail.stackedOn, 734)
        XCTAssertTrue(detail.isStacked)
        XCTAssertEqual(detail.blocksRestackOf, [])
        XCTAssertNil(feed.stackedOn)
        XCTAssertEqual(feed.blocksRestackOf, [736],
                       "rebasing 734 strands 736, and the row must say so")
    }

    func testUnstackedPRHasNoStackLinks() throws {
        let items = try build([node(number: 700, head: "feat/a", base: "main")])
        XCTAssertNil(items[0].stackedOn)
        XCTAssertTrue(items[0].blocksRestackOf.isEmpty)
    }

    /// Two repos can share branch names; they must not cross-link.
    func testStacksDoNotCrossRepositories() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let other = node(number: 900, head: "feat/feed", base: "main")
            .replacingOccurrences(of: "elevationchurch/repo", with: "elevationchurch/other")
        let items = inbox.build(from: try decoder.decode(
            MyPRPayload.self,
            from: Data(payload([node(number: 736, head: "feat/detail", base: "feat/feed"),
                                other]).utf8)).mine)
        let detail = items.first { $0.number == 736 }!
        XCTAssertNil(detail.stackedOn, "a same-named branch in another repo is not the parent")
    }

    // MARK: - Compare phase

    func testComparesFillBehindBy() throws {
        var items = try build([node(number: 1), node(number: 2)])
        items = MyPRInbox.applyCompares([
            "c0": try JSONDecoder().decode(CompareResult.self, from: Data(
                #"{"ref":{"compare":{"aheadBy":12,"behindBy":3,"status":"DIVERGED"}}}"#.utf8)),
        ], to: items)
        XCTAssertEqual(items[0].behindBy, 3)
        XCTAssertNil(items[1].behindBy, "a missing alias must stay unknown, not become 0")
    }

    func testMissingCompareLeavesBehindByUnknown() throws {
        let items = MyPRInbox.applyCompares([:], to: try build([node()]))
        XCTAssertNil(items[0].behindBy)
    }

    // MARK: - Branch state (what the chip says)

    func testBehindBranchNeedsRebaseWithTheCount() throws {
        var items = try build([node(mergeState: "BEHIND")])
        items[0].behindBy = 7
        XCTAssertEqual(items[0].branchState, .needsRebase(behindBy: 7))
    }

    func testLevelBranchIsUpToDate() throws {
        var items = try build([node(mergeState: "BLOCKED")])
        items[0].behindBy = 0
        XCTAssertEqual(items[0].branchState, .upToDate,
                       "both live PRs are in this state today")
    }

    /// Conflicts win over the count: a branch can be level and still conflict.
    func testConflictsOutrankTheBehindCount() throws {
        var items = try build([node(mergeState: "DIRTY")])
        items[0].behindBy = 0
        XCTAssertEqual(items[0].branchState, .conflicts)
    }

    /// Without a count, GitHub's own BEHIND verdict is enough to say so.
    func testFallsBackToMergeStateWhenCountIsMissing() throws {
        let items = try build([node(mergeState: "BEHIND")])
        XCTAssertNil(items[0].behindBy)
        XCTAssertEqual(items[0].branchState, .needsRebase(behindBy: nil))
    }

    /// A failed compare must read as unknown, never as up to date — claiming a
    /// branch is current when we never checked is the one wrong answer here.
    func testMissingCountAndNoBehindVerdictIsUnknown() throws {
        let items = try build([node(mergeState: "BLOCKED")])
        XCTAssertEqual(items[0].branchState, .unknown)
        XCTAssertNotEqual(items[0].branchState, .upToDate)
    }

    // MARK: - Ready to merge (what the badge dot means)

    func testCleanPRIsReadyToMerge() throws {
        let items = try build([node(mergeState: "CLEAN")])
        XCTAssertTrue(items[0].isReadyToMerge)
    }

    /// HAS_HOOKS is the same green state on a repo with pre-receive hooks.
    func testRepoWithHooksIsStillReadyToMerge() throws {
        let items = try build([node(mergeState: "HAS_HOOKS")])
        XCTAssertTrue(items[0].isReadyToMerge)
    }

    /// A draft is never something to go and merge, however green it looks.
    func testDraftIsNeverReadyToMerge() throws {
        let items = try build([node(mergeState: "CLEAN", draft: true)])
        XCTAssertFalse(items[0].isReadyToMerge)
    }

    func testNothingElseIsReadyToMerge() throws {
        for state in ["BLOCKED", "BEHIND", "DIRTY", "UNSTABLE", "DRAFT", "UNKNOWN"] {
            let items = try build([node(mergeState: state)])
            XCTAssertFalse(items[0].isReadyToMerge, "\(state) must not read as mergeable")
        }
    }

    /// Both live PRs are BLOCKED on reviews, so the dot stays dark today.
    func testBlockedOnReviewIsNotReadyToMerge() throws {
        let items = try build([node(mergeState: "BLOCKED",
                                    reviews: [("ec-boston", "APPROVED")])])
        XCTAssertFalse(items[0].needsLead)
        XCTAssertFalse(items[0].isReadyToMerge,
                       "a lead approval alone does not make it mergeable")
    }

    /// Soft signals still colour the row even though the dot is about merging.
    func testHealthStillReflectsSoftSignals() throws {
        let items = try build([node(mergeState: "BLOCKED", threads: [false, false])])
        let pr = items[0]
        XCTAssertTrue(pr.needsLead)
        XCTAssertEqual(pr.unresolvedThreadCount, 2)
        XCTAssertEqual(pr.health, .attention)
    }
}
