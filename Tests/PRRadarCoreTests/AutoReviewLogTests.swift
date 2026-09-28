import XCTest
@testable import PRRadarCore

final class AutoReviewLogTests: XCTestCase {

    let epoch = Date(timeIntervalSince1970: 1_789_000_000)

    private func record(_ status: AutoReviewStatus,
                        node: String? = "REV_1",
                        finishedAt: Date? = nil) -> AutoReviewRecord {
        var record = AutoReviewRecord(status: status)
        record.reviewNodeID = node
        record.finishedAt = finishedAt
        return record
    }

    // MARK: - Storage

    func testARoundTripKeepsEverything() {
        var log = AutoReviewLog()
        var record = AutoReviewRecord(status: .posted)
        record.counts = ["priority": 2, "mild": 5, "nit": 4]
        record.reviewNodeID = "REV_1"
        record.reviewURLString = "https://github.com/acme/repo/pull/1#pullrequestreview-1"
        record.threadNodeIDs = ["T_1", "T_2"]
        record.finishedAt = epoch
        record.attempts = 1
        log["acme/repo#1@2026-09-15T11:00:00Z"] = record

        XCTAssertEqual(AutoReviewLog.decoded(from: log.encoded()), log)
    }

    func testNothingStoredIsAnEmptyLog() {
        XCTAssertEqual(AutoReviewLog.decoded(from: nil), AutoReviewLog())
    }

    /// A review history is not worth failing a launch over.
    func testGarbageIsAnEmptyLogRatherThanACrash() {
        XCTAssertEqual(AutoReviewLog.decoded(from: Data("not json".utf8)), AutoReviewLog())
    }

    /// `Codable` fails a value rather than a field, so a status this build has
    /// never heard of would otherwise cost the user their entire log.
    func testAnUnknownStatusCostsOneRecordsMeaningAndNotTheWholeLog() throws {
        let json = #"{"records":{"k":{"status":"teleported","attempts":0,"counts":{},"threadNodeIDs":[]}}}"#
        let log = AutoReviewLog.decoded(from: Data(json.utf8))
        XCTAssertEqual(log["k"]?.status, .skipped)
    }

    // MARK: - Pins

    func testOnlyPostedRecordsBecomePins() {
        var log = AutoReviewLog()
        log["posted"] = record(.posted)
        log["running"] = record(.running)
        log["ready"] = record(.ready)
        log["failed"] = record(.failed)
        XCTAssertEqual(log.pins, ["posted": "REV_1"])
    }

    /// Dropping the pin is the whole of "Leave comment only": once it is gone,
    /// our own review counts as activity again and the ordinary rule hides the
    /// row without anything else being asked of it.
    func testADismissedRecordIsNoLongerAPin() {
        var log = AutoReviewLog()
        log["k"] = record(.dismissed)
        XCTAssertTrue(log.pins.isEmpty)
    }

    /// A posted record that somehow never learned its node id has nothing to
    /// pin by, and claiming otherwise would put a nil in the inbox's map.
    func testAPostedRecordWithNoNodeIDIsNotAPin() {
        var log = AutoReviewLog()
        log["k"] = record(.posted, node: nil)
        XCTAssertTrue(log.pins.isEmpty)
    }

    // MARK: - Pruning

    /// The one rule pruning must never break. A record missing for a PR still
    /// in the list reads as "never reviewed", which would review it a second
    /// time and post a second review.
    func testPruningKeepsEveryLivePingHoweverOld() {
        var log = AutoReviewLog()
        log["live"] = record(.posted, finishedAt: epoch.addingTimeInterval(-365 * 86_400))
        log.prune(liveKeys: ["live"], now: epoch)
        XCTAssertNotNil(log["live"])
    }

    func testPruningDropsFinishedRecordsPastTheAgeLimit() {
        var log = AutoReviewLog()
        log["old"] = record(.dismissed, finishedAt: epoch.addingTimeInterval(-15 * 86_400))
        log["recent"] = record(.dismissed, finishedAt: epoch.addingTimeInterval(-1 * 86_400))
        log.prune(liveKeys: [], now: epoch)
        XCTAssertNil(log["old"])
        XCTAssertNotNil(log["recent"])
    }

    /// An unfinished record has no age to judge it by, and is in flight by
    /// definition, so it is kept rather than guessed about.
    func testPruningKeepsRecordsThatHaveNotFinished() {
        var log = AutoReviewLog()
        log["running"] = record(.running, finishedAt: nil)
        log.prune(liveKeys: [], now: epoch)
        XCTAssertNotNil(log["running"])
    }

    func testPruningTrimsToTheLimitOldestFirst() {
        var log = AutoReviewLog()
        for index in 0..<10 {
            log["k\(index)"] = record(.dismissed,
                                      finishedAt: epoch.addingTimeInterval(TimeInterval(index)))
        }
        log.prune(liveKeys: [], now: epoch, maxAge: .greatestFiniteMagnitude, limit: 4)
        XCTAssertEqual(log.records.count, 4)
        XCTAssertNil(log["k0"])
        XCTAssertNotNil(log["k9"])
    }

    /// The limit must not be met by throwing away rows that are on screen.
    func testTrimmingNeverSacrificesALiveKey() {
        var log = AutoReviewLog()
        for index in 0..<10 {
            log["k\(index)"] = record(.dismissed,
                                      finishedAt: epoch.addingTimeInterval(TimeInterval(index)))
        }
        log.prune(liveKeys: ["k0", "k1"], now: epoch,
                  maxAge: .greatestFiniteMagnitude, limit: 4)
        XCTAssertNotNil(log["k0"])
        XCTAssertNotNil(log["k1"])
    }

    // MARK: - Failure text

    /// A runaway stderr must not be able to grow the stored blob without bound.
    func testAFailureMessageIsTruncatedBeforeItIsStored() {
        let long = String(repeating: "x", count: 5_000)
        let message = AutoReviewRecord.truncated(long)
        XCTAssertEqual(message.count, 301)
        XCTAssertTrue(message.hasSuffix("…"))
    }

    func testAShortFailureMessageIsLeftAloneApartFromItsWhitespace() {
        XCTAssertEqual(AutoReviewRecord.truncated("  no such skill\n"), "no such skill")
    }
}

// MARK: - Holding a review until it is posted

/// With automatic posting off, a review is composed on one launch and posted on
/// a button press that may come minutes later. Everything needed to send it has
/// to survive that gap.
extension AutoReviewLogTests {

    private var threads: [ReviewThread] {
        [ReviewThread(path: "Sources/Foo.swift", line: 12,
                      body: "**Priority** — leaks.\n\n```suggestion\nlet x = 1\n```"),
         ReviewThread(path: "Sources/Bar.swift", line: 40, startLine: 38, body: "**Mild** — noisy.")]
    }

    /// The bug this exists to stop coming back: storing only the body meant the
    /// Post button had nothing to attach, so a manually-posted review went out
    /// as a bare summary and every inline finding was silently thrown away.
    func testAHeldReviewKeepsItsInlineThreads() {
        var log = AutoReviewLog()
        var record = AutoReviewRecord(status: .ready)
        record.body = "**PR Radar** · automatic review"
        record.threads = threads
        log["k"] = record

        let restored = AutoReviewLog.decoded(from: log.encoded())["k"]
        XCTAssertEqual(restored?.threads.count, 2)
        XCTAssertEqual(restored?.threads.first?.path, "Sources/Foo.swift")
        XCTAssertEqual(restored?.threads.first?.line, 12)
        XCTAssertEqual(restored?.threads.last?.startLine, 38)
        XCTAssertTrue(restored?.threads.first?.body.contains("```suggestion") == true)
    }

    /// A record written by a build that did not know about threads still reads.
    func testARecordWithoutThreadsDecodesToNoneRatherThanFailing() {
        let json = #"{"records":{"k":{"status":"ready","attempts":0,"counts":{},"threadNodeIDs":[]}}}"#
        let log = AutoReviewLog.decoded(from: Data(json.utf8))
        XCTAssertEqual(log["k"]?.status, .ready)
        XCTAssertTrue(log["k"]?.threads.isEmpty == true)
    }
    // MARK: - Recovering an interrupted review

    /// The bug this exists for: `make install` pkills the app mid-review, and
    /// the record it wrote is still `running` when the next copy reads it back.
    func testAReviewInterruptedByARestartGoesBackInTheQueue() {
        var log = AutoReviewLog()
        var record = AutoReviewRecord(status: .running)
        record.startedAt = epoch
        record.attempts = 1
        log["acme/repo#1@2026-09-28T13:45:31Z"] = record

        let moved = log.reconcileInterrupted()

        XCTAssertEqual(moved, ["acme/repo#1@2026-09-28T13:45:31Z"])
        XCTAssertEqual(log["acme/repo#1@2026-09-28T13:45:31Z"]?.status, .queued)
        XCTAssertNil(log["acme/repo#1@2026-09-28T13:45:31Z"]?.startedAt)
    }

    /// A run that produced nothing must not spend one of the two attempts a
    /// ping gets — two interrupted installs would otherwise exhaust a PR's
    /// budget without anybody having read a word of a review.
    func testAnInterruptedAttemptIsNotChargedToTheRetryBudget() {
        var log = AutoReviewLog()
        var record = AutoReviewRecord(status: .running)
        record.attempts = 1
        log["k"] = record

        log.reconcileInterrupted()

        XCTAssertEqual(log["k"]?.attempts, 0)
    }

    /// Never below zero, whatever a hand-edited or older record claims.
    func testRollingBackAnAttemptNeverGoesNegative() {
        var log = AutoReviewLog()
        log["k"] = AutoReviewRecord(status: .running)   // attempts defaults to 0

        log.reconcileInterrupted()

        XCTAssertEqual(log["k"]?.attempts, 0)
    }

    /// Finished work is not reopened. Only `running` is an orphan by
    /// construction; every other status belongs to somebody.
    func testNoOtherStatusIsDisturbed() {
        var log = AutoReviewLog()
        for status in AutoReviewStatus.allCases where status != .running {
            log[status.rawValue] = record(status, finishedAt: epoch)
        }
        let before = log

        XCTAssertTrue(log.reconcileInterrupted().isEmpty)
        XCTAssertEqual(log, before)
    }

    /// Two interrupted at once — the queue picks them up oldest ping first, so
    /// both have to come back, not just the one that happened to be found.
    func testEveryInterruptedReviewComesBackNotJustTheFirst() {
        var log = AutoReviewLog()
        log["b"] = AutoReviewRecord(status: .running)
        log["a"] = AutoReviewRecord(status: .running)
        log["done"] = record(.posted, finishedAt: epoch)

        XCTAssertEqual(log.reconcileInterrupted(), ["a", "b"])
        XCTAssertEqual(log["a"]?.status, .queued)
        XCTAssertEqual(log["b"]?.status, .queued)
        XCTAssertEqual(log["done"]?.status, .posted)
    }

    /// Running it twice must not undo a real attempt made in between.
    func testReconcilingAgainWithNothingInFlightChangesNothing() {
        var log = AutoReviewLog()
        log["k"] = AutoReviewRecord(status: .running)
        log.reconcileInterrupted()
        let afterFirst = log

        XCTAssertTrue(log.reconcileInterrupted().isEmpty)
        XCTAssertEqual(log, afterFirst)
    }

}
