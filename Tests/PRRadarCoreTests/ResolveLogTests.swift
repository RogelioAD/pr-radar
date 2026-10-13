import XCTest
@testable import PRRadarCore

/// What a resolve run that did not finish becomes, and what the log refuses to
/// forget.
final class ResolveLogTests: XCTestCase {

    private func running(tree: String = "/t", before: String? = "aaaa") -> ResolveRecord {
        var record = ResolveRecord(status: .running)
        record.treePath = tree
        record.preRunOid = before
        record.startedAt = Date()
        return record
    }

    // MARK: - Abandonment

    /// The whole reason this is a separate type from `AutoReviewLog`: that one
    /// puts an interrupted run back in the queue, and this one must never.
    func testAnAbandonedRunIsNeverPutBackInAQueue() {
        var log = ResolveLog()
        log["acme/app#1"] = running()
        log.reconcileAbandoned(headOf: { _ in "aaaa" })

        let record = log["acme/app#1"]
        XCTAssertEqual(record?.status, .interrupted)
        XCTAssertTrue(record?.status.isTerminal == true)
        XCTAssertNotEqual(record?.status, .running)
    }

    /// Nothing moved, so a second press is safe to offer.
    func testARunThatLandedNothingMayBeTriedAgain() {
        var log = ResolveLog()
        log["acme/app#1"] = running(before: "aaaa")
        log.reconcileAbandoned(headOf: { _ in "aaaa" })
        XCTAssertTrue(log["acme/app#1"]?.status.mayRerun == true)
    }

    /// Commits exist that nobody has read a table about. A second run would
    /// layer fixes on a half-finished first set, on a branch others can see.
    func testARunThatCommittedAndDiedSaysSoAndRefusesARetry() {
        var log = ResolveLog()
        log["acme/app#1"] = running(before: "aaaa")
        log.reconcileAbandoned(headOf: { _ in "bbbb" })

        let record = log["acme/app#1"]
        XCTAssertEqual(record?.status, .landedUnreported)
        XCTAssertFalse(record?.status.mayRerun == true)
        XCTAssertEqual(record?.failure, "Interrupted after it had already committed.")
    }

    func testARunStillGoingOutsideTheAppIsOrphanedRatherThanInterrupted() {
        var log = ResolveLog()
        log["acme/app#1"] = running()
        log.reconcileAbandoned(headOf: { _ in "aaaa" }, isAlive: { _ in true })

        XCTAssertEqual(log["acme/app#1"]?.status, .orphaned)
        XCTAssertFalse(log["acme/app#1"]?.status.mayRerun == true)
    }

    func testAFinishedRunIsLeftAlone() {
        var log = ResolveLog()
        var done = ResolveRecord(status: .posted)
        done.finishedAt = Date()
        log["acme/app#1"] = done
        log.reconcileAbandoned(headOf: { _ in "zzzz" })
        XCTAssertEqual(log["acme/app#1"]?.status, .posted)
    }

    /// Without a `preRunOid` there is no way to tell whether anything landed,
    /// and the safe reading of that doubt is the one that does not invite a
    /// retry over work that may exist.
    func testARunWithNoBeforeCommitIsNotDeclaredHarmless() {
        var log = ResolveLog()
        log["acme/app#1"] = running(before: nil)
        log.reconcileAbandoned(headOf: { _ in "bbbb" })
        XCTAssertEqual(log["acme/app#1"]?.status, .interrupted)
    }

    // MARK: - The evidence

    func testForensicsNamesTheCommandThatShowsWhatHappened() {
        var record = running(tree: "/Users/me/code/app-feat", before: "a1b2c3d")
        record.status = .landedUnreported
        XCTAssertEqual(record.forensics,
                       "git -C /Users/me/code/app-feat log --oneline a1b2c3d..HEAD")
    }

    /// A record that quietly expires takes with it the only evidence that code
    /// reached somebody's branch without a table to explain it.
    func testEvidenceIsNeverPrunedByAge() {
        var log = ResolveLog()
        let longAgo = Date(timeIntervalSinceNow: -400 * 24 * 3_600)

        for (key, status) in [("a#1", ResolveStatus.landedUnreported),
                              ("a#2", .orphaned),
                              ("a#3", .posted)] {
            var record = ResolveRecord(status: status)
            record.finishedAt = longAgo
            log[key] = record
        }
        log.prune(liveKeys: [], now: Date())

        XCTAssertNotNil(log["a#1"], "landedUnreported must outlive the pruner")
        XCTAssertNotNil(log["a#2"], "orphaned must outlive the pruner")
        XCTAssertNil(log["a#3"], "an ordinary finished record may go")
    }

    func testEvidenceSurvivesTheCountLimitToo() {
        var log = ResolveLog()
        var evidence = ResolveRecord(status: .landedUnreported)
        evidence.finishedAt = Date(timeIntervalSinceNow: -1_000)
        log["keep/me#1"] = evidence

        for index in 0..<40 {
            var record = ResolveRecord(status: .posted)
            record.finishedAt = Date()
            log["noise/x#\(index)"] = record
        }
        log.prune(liveKeys: [], now: Date(), limit: 10)

        XCTAssertNotNil(log["keep/me#1"])
        XCTAssertLessThanOrEqual(log.records.count, 10)
    }

    // MARK: - Shape

    func testThereIsNoQueuedState() {
        // A queue state nothing can reach is a state something will eventually
        // be made to reach. Resolve is pressed, never scheduled.
        XCTAssertNil(ResolveStatus(rawValue: "queued"))
    }

    func testARecordRoundTripsThroughTheStore() throws {
        var log = ResolveLog()
        var record = ResolveRecord(status: .ready, mode: .triage)
        record.table = ResolveTable(scope: "a scope", threads: [
            ResolveRow(threadId: "T1", disposition: .fix, reply: "done"),
        ])
        record.pushedShas = ["a1b2c3d"]
        log["acme/app#1"] = record

        let restored = ResolveLog.decoded(from: log.encoded())
        XCTAssertEqual(restored["acme/app#1"]?.mode, .triage)
        XCTAssertEqual(restored["acme/app#1"]?.table?.threads.first?.threadId, "T1")
        XCTAssertEqual(restored["acme/app#1"]?.pushedShas, ["a1b2c3d"])
    }

    /// A record this build cannot fully read must not come back claiming to be
    /// running, which would draw a stopwatch over nothing.
    func testAnUnreadableRecordDoesNotComeBackRunning() throws {
        let legacy = Data(#"{"pushedShas":["a1b2c3d"]}"#.utf8)
        let record = try JSONDecoder().decode(ResolveRecord.self, from: legacy)
        XCTAssertEqual(record.status, .dismissed)
    }

    func testACorruptStoreReadsAsAnEmptyLogRatherThanThrowing() {
        XCTAssertTrue(ResolveLog.decoded(from: Data("not json".utf8)).records.isEmpty)
        XCTAssertTrue(ResolveLog.decoded(from: nil).records.isEmpty)
    }

    // MARK: - Stopping

    /// Stopped is not failed. One is the feature not working and the other is
    /// it doing as it was told, and the row has to read differently.
    func testAStoppedRunIsNotAFailureAndMayBeTriedAgain() {
        XCTAssertTrue(ResolveStatus.stopped.isTerminal)
        XCTAssertTrue(ResolveStatus.stopped.mayRerun)
        XCTAssertNotEqual(ResolveStatus.stopped, .failed)
    }

    /// A run stopped after it had already pushed is not simply stopped: there
    /// are commits on the branch nobody has read a table about, which is the
    /// state that must never offer a retry.
    func testStoppingAfterAPushIsStillEvidence() {
        XCTAssertFalse(ResolveStatus.landedUnreported.mayRerun)
    }

    // MARK: - Scope

    /// Only a threads run has drafts to pick over. A conflicts run produced a
    /// merge, so the row reports rather than waiting — and must not draw a
    /// "Choose replies" disclosure onto an empty table.
    func testOnlyAThreadsRunWaitsToBePickedOver() {
        var threads = ResolveRecord(status: .ready, mode: .curated, scope: .threads)
        threads.table = ResolveTable(threads: [
            ResolveRow(threadId: "T1", disposition: .fix, reply: "done"),
        ])
        XCTAssertTrue(threads.isAwaitingSelection)

        var conflicts = ResolveRecord(status: .ready, mode: .curated, scope: .conflicts)
        conflicts.table = ResolveTable(merge: MergeReport(conflicted: true))
        XCTAssertFalse(conflicts.isAwaitingSelection)
    }

    func testARecordWrittenBeforeScopeExistedReadsAsAThreadsRun() throws {
        let legacy = Data(#"{"status":"ready","mode":"curated"}"#.utf8)
        let record = try JSONDecoder().decode(ResolveRecord.self, from: legacy)
        XCTAssertEqual(record.scope, .threads)
    }

    // MARK: - The lease

    func testALeaseIsNamedAfterATreeWithoutContainingItsPath() {
        let name = ResolveLease.filename(forTree: "/Users/me/secret-project/app")
        XCTAssertFalse(name.contains("secret-project"))
        XCTAssertTrue(name.hasSuffix(".json"))
        XCTAssertEqual(name, ResolveLease.filename(forTree: "/Users/me/secret-project/app"),
                       "the same tree must give the same name every launch")
        XCTAssertNotEqual(name, ResolveLease.filename(forTree: "/Users/me/other/app"))
    }

    /// Our own lease is not somebody else holding the tree — otherwise the
    /// run that wrote it would refuse to be the run that wrote it.
    func testOurOwnLeaseIsNotSomebodyElse() {
        let lease = ResolveLease(appPID: 42, repo: "a/b", number: 1,
                                 branch: "x", treePath: "/t", mode: .curated)
        XCTAssertEqual(lease.holder(alive: { _ in true }, selfPID: 42), .none)
    }

    func testAnotherLivingProcessHoldsTheTree() {
        let lease = ResolveLease(appPID: 42, repo: "a/b", number: 1,
                                 branch: "x", treePath: "/t", mode: .curated)
        XCTAssertEqual(lease.holder(alive: { _ in true }, selfPID: 7), .live)
        XCTAssertEqual(lease.holder(alive: { _ in false }, selfPID: 7), .abandoned)
    }

    /// The session's own pid when it is known, and the app that started it
    /// otherwise — which is what makes a previous launch read as gone.
    func testTheSessionsPIDOutranksTheApps() {
        var lease = ResolveLease(appPID: 42, repo: "a/b", number: 1,
                                 branch: "x", treePath: "/t", mode: .curated)
        XCTAssertEqual(lease.owningPID, 42)
        lease.claudePID = 99
        XCTAssertEqual(lease.owningPID, 99)
    }

    func testALeaseRoundTripsWithTheCommitItStartedFrom() throws {
        let lease = ResolveLease(appPID: 42, claudePID: 99, repo: "acme/app",
                                 number: 1, branch: "feat/x", treePath: "/t",
                                 preRunOid: "a1b2c3d", mode: .curated)
        let restored = try XCTUnwrap(ResolveLease.decoded(from: lease.encoded()))
        XCTAssertEqual(restored.claudePID, 99)
        XCTAssertEqual(restored.preRunOid, "a1b2c3d")
        XCTAssertEqual(restored.mode, .curated)
    }
}
