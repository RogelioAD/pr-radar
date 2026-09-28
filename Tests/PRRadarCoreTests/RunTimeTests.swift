import XCTest
@testable import PRRadarCore

final class RunTimeTests: XCTestCase {

    let epoch = Date(timeIntervalSince1970: 1_789_000_000)

    // MARK: - Reading as a clock

    /// Seconds at every length. A review takes minutes, and a number that only
    /// moves once a minute does not look like it is measuring anything.
    func testADurationReadsAsAClock() {
        XCTAssertEqual(RunTime.clock(0), "0:00")
        XCTAssertEqual(RunTime.clock(7), "0:07")
        XCTAssertEqual(RunTime.clock(59), "0:59")
        XCTAssertEqual(RunTime.clock(60), "1:00")
        XCTAssertEqual(RunTime.clock(252), "4:12")
        XCTAssertEqual(RunTime.clock(531), "8:51")
    }

    func testAnHourGrowsTheClockRatherThanRollingOver() {
        XCTAssertEqual(RunTime.clock(3_600), "1:00:00")
        XCTAssertEqual(RunTime.clock(3_753), "1:02:33")
        XCTAssertEqual(RunTime.clock(86_399), "23:59:59")
    }

    /// Part-seconds round down, so a stopwatch never shows a second it has not
    /// finished counting.
    func testPartSecondsRoundDown() {
        XCTAssertEqual(RunTime.clock(7.9), "0:07")
    }

    /// A machine whose clock went backwards shows nothing, not a negative.
    func testAClockPutBackShowsZeroRatherThanANegative() {
        XCTAssertEqual(RunTime.clock(-41), "0:00")
    }

    // MARK: - Spoken, for the tooltip

    func testTheSpokenFormPluralisesAndDegradesByUnit() {
        XCTAssertEqual(RunTime.spoken(1), "1 second")
        XCTAssertEqual(RunTime.spoken(42), "42 seconds")
        XCTAssertEqual(RunTime.spoken(60), "1 minute")
        XCTAssertEqual(RunTime.spoken(531), "8 minutes")
        XCTAssertEqual(RunTime.spoken(3_600), "1 hour")
        XCTAssertEqual(RunTime.spoken(3_780), "1 hour 3 minutes")
    }

    // MARK: - What the row measures

    func testARunningReviewIsMeasuredToNow() {
        let seconds = RunTime.elapsed(startedAt: epoch, finishedAt: nil,
                                      now: epoch.addingTimeInterval(90))
        XCTAssertEqual(seconds, 90)
    }

    /// A finished run measures to its own finish, so a four-minute review still
    /// says four minutes a week later — the age pill says how long ago it was.
    func testAFinishedReviewIsMeasuredToItsFinishNotToTheClock() {
        let seconds = RunTime.elapsed(startedAt: epoch,
                                      finishedAt: epoch.addingTimeInterval(252),
                                      now: epoch.addingTimeInterval(86_400))
        XCTAssertEqual(seconds, 252)
    }

    func testAReviewThatNeverStartedHasNoRunTime() {
        XCTAssertNil(RunTime.elapsed(startedAt: nil, finishedAt: nil, now: epoch))
    }

    // MARK: - The record's own answer

    func testARunningRecordKeepsClimbing() {
        var record = AutoReviewRecord(status: .running)
        record.startedAt = epoch

        XCTAssertEqual(record.runTime(now: epoch.addingTimeInterval(30)), 30)
    }

    /// The bug this guards: posting a curated review rewrites `finishedAt`, so
    /// an eight-minute run that waited two hours to be posted would otherwise
    /// report two hours.
    func testPostingLaterDoesNotInflateWhatTheRunTook() {
        var record = AutoReviewRecord(status: .posted)
        record.startedAt = epoch
        record.runSeconds = 531
        record.finishedAt = epoch.addingTimeInterval(7_200)   // posted two hours on

        XCTAssertEqual(record.runTime(now: epoch.addingTimeInterval(9_000)), 531)
    }

    /// Records written before runs were timed still show something sensible.
    func testAnUntimedRecordFallsBackToItsTimestamps() {
        var record = AutoReviewRecord(status: .failed)
        record.startedAt = epoch
        record.finishedAt = epoch.addingTimeInterval(42)

        XCTAssertEqual(record.runTime(now: epoch.addingTimeInterval(9_000)), 42)
    }

    func testARecordThatNeverRanShowsNoStopwatch() {
        XCTAssertNil(AutoReviewRecord(status: .queued).runTime(now: epoch))
    }

    /// The run time rides along in the stored blob.
    func testTheRunTimeSurvivesARoundTrip() {
        var log = AutoReviewLog()
        var record = AutoReviewRecord(status: .posted)
        record.runSeconds = 531
        log["k"] = record

        XCTAssertEqual(AutoReviewLog.decoded(from: log.encoded())["k"]?.runSeconds, 531)
    }
}
