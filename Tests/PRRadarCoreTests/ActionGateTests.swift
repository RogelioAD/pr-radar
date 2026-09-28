import XCTest
@testable import PRRadarCore

final class ActionGateTests: XCTestCase {

    private let key = "acme/app#12@2026-09-28T18:34:11Z"

    func testTheFirstPressIsLetThrough() {
        var gate = ActionGate()
        XCTAssertTrue(gate.begin(key))
    }

    /// The bug this exists for: posting is a round trip, the record still reads
    /// `ready` while it is in the air, and the row goes on offering the button.
    func testASecondPressWhileTheFirstIsInFlightIsDropped() {
        var gate = ActionGate()
        XCTAssertTrue(gate.begin(key))
        XCTAssertFalse(gate.begin(key))
    }

    func testDroppedRatherThanQueued() {
        var gate = ActionGate()
        gate.begin(key)
        XCTAssertFalse(gate.begin(key))
        gate.end(key)
        // Nothing was held back to run on release. A row that let two presses
        // through late is the same pull request with two reviews on it.
        XCTAssertFalse(gate.isActing(on: key))
    }

    func testTheRowOpensAgainOnceTheActionEnds() {
        var gate = ActionGate()
        gate.begin(key)
        gate.end(key)
        XCTAssertTrue(gate.begin(key))
    }

    /// Release is unconditional, so a failed mutation does not wedge the row.
    func testAFailedActionStillReleasesTheRow() {
        var gate = ActionGate()
        gate.begin(key)
        gate.end(key)   // the `defer`-shaped call the coordinator makes either way
        XCTAssertFalse(gate.isActing(on: key))
    }

    func testEndingARowThatWasNeverClaimedIsHarmless() {
        var gate = ActionGate()
        gate.end(key)
        XCTAssertTrue(gate.begin(key))
    }

    func testOneRowInFlightDoesNotBlockAnother() {
        var gate = ActionGate()
        gate.begin(key)
        XCTAssertTrue(gate.begin("acme/app#13@2026-09-28T18:34:11Z"))
    }

    /// Two pings on one pull request are two pieces of work, and two rows.
    func testTwoPingsOnOnePullRequestAreSeparateRows() {
        var gate = ActionGate()
        gate.begin("acme/app#12@2026-09-28T17:27:16Z")
        XCTAssertTrue(gate.begin("acme/app#12@2026-09-28T18:34:11Z"))
    }

    func testARowInFlightSaysSo() {
        var gate = ActionGate()
        XCTAssertFalse(gate.isActing(on: key))
        gate.begin(key)
        XCTAssertTrue(gate.isActing(on: key))
    }
}
