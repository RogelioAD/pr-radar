import XCTest
@testable import PRRadarCore

/// Whether a checkout may be moved, and the one case where it may not.
///
/// This decides whether the app touches somebody's working tree, so the rule is
/// here rather than read off a shell exit code in passing.
final class FastForwardTests: XCTestCase {

    func testBehindOnlyIsSafeToMove() {
        XCTAssertEqual(FastForward.verdict(ahead: 0, behind: 3),
                       .canFastForward(behind: 3))
    }

    func testLevelIsNothingToDo() {
        XCTAssertEqual(FastForward.verdict(ahead: 0, behind: 0), .upToDate)
    }

    /// The case the button exists to refuse. A reset would make this work and
    /// would throw away commits nobody else has — whether to rebase, push or
    /// discard them is the developer's call, not a poll's.
    func testLocalCommitsStopIt() {
        XCTAssertEqual(FastForward.verdict(ahead: 2, behind: 5),
                       .diverged(ahead: 2, behind: 5))
        XCTAssertEqual(FastForward.verdict(ahead: 1, behind: 0),
                       .diverged(ahead: 1, behind: 0))
    }

    // MARK: - Reading git

    func testCountsAreReadFromRevList() {
        XCTAssertTrue(FastForward.counts(fromRevList: "0\t3\n").map { $0 == (0, 3) } ?? false)
        XCTAssertTrue(FastForward.counts(fromRevList: "2\t5").map { $0 == (2, 5) } ?? false)
        XCTAssertTrue(FastForward.counts(fromRevList: "0 0\n").map { $0 == (0, 0) } ?? false)
    }

    /// A failure must not read as "up to date". That would leave the row
    /// insisting the checkout is behind while the button that fixes it says
    /// there is nothing to do — the two halves of the app disagreeing in a way
    /// nobody can get out of.
    func testUnreadableOutputIsNotZeroes() {
        XCTAssertNil(FastForward.counts(fromRevList: ""))
        XCTAssertNil(FastForward.counts(fromRevList: "fatal: bad revision"))
        XCTAssertNil(FastForward.counts(fromRevList: "3"))
        XCTAssertNil(FastForward.counts(fromRevList: "1\t2\t3"))
        XCTAssertNil(FastForward.counts(fromRevList: "-1\t2"))
    }
}
