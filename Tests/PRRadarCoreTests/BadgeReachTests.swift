import XCTest
@testable import PRRadarCore

/// What the badge can actually be dragged to, which is what the "biggest" and
/// "smallest" trophies have to be measured against.
final class BadgeReachTests: XCTestCase {

    private let sizing = BadgeSizing(minimum: 28, maximum: 128)
    /// The badge's character is 18 cells wide and never drawn below 2x — the
    /// same two numbers `Layout` uses.
    private let cells = 18
    private let minimumScale: CGFloat = 2

    /// The bug this exists for: on a 1x screen an 18-cell character settles on
    /// 36 and 126, so a badge dragged hard against either stop never reports
    /// the 28 or 128 the bounds name — and a trophy asking for those was
    /// asking for a size that cannot occur.
    func testACharacterStopsShortOfBothBounds() {
        let reach = sizing.reachableRange(spriteWidth: cells,
                                          backingScale: 1,
                                          minimumScale: minimumScale)
        XCTAssertEqual(reach.minimum, 36)
        XCTAssertEqual(reach.maximum, 126)
        XCTAssertGreaterThan(reach.minimum, sizing.minimum)
        XCTAssertLessThan(reach.maximum, sizing.maximum)
    }

    /// A Retina screen snaps in half steps, so it gets closer — and still does
    /// not land on either bound.
    func testRetinaSnapsFinerAndStillStopsShort() {
        let reach = sizing.reachableRange(spriteWidth: cells,
                                          backingScale: 2,
                                          minimumScale: minimumScale)
        XCTAssertEqual(reach.minimum, 36)
        XCTAssertEqual(reach.maximum, 126)
        XCTAssertLessThan(reach.maximum, sizing.maximum)
    }

    /// With the character off the badge is a plain tile, snapped to nothing, so
    /// both bounds are reachable exactly.
    func testAPlainTileReachesBothBounds() {
        let reach = sizing.reachableRange(spriteWidth: nil,
                                          backingScale: 1,
                                          minimumScale: minimumScale)
        XCTAssertEqual(reach.minimum, sizing.minimum)
        XCTAssertEqual(reach.maximum, sizing.maximum)
    }

    /// The range is never inverted or outside the bounds, whatever it is asked.
    func testTheRangeStaysInsideTheBounds() {
        for scale in [CGFloat(1), 2, 3] {
            let reach = sizing.reachableRange(spriteWidth: cells,
                                              backingScale: scale,
                                              minimumScale: minimumScale)
            XCTAssertLessThanOrEqual(reach.minimum, reach.maximum, "backing \(scale)")
            XCTAssertGreaterThanOrEqual(reach.minimum, sizing.minimum, "backing \(scale)")
            XCTAssertLessThanOrEqual(reach.maximum, sizing.maximum, "backing \(scale)")
        }
    }

    /// A shelf that has already been established, so a rule that matches
    /// unlocks rather than being backfilled in silence.
    private var settled: TrophyState {
        var state = TrophyState()
        state.established = true
        return state
    }

    private func unlocks(tile: CGFloat, in reach: (minimum: CGFloat, maximum: CGFloat))
        -> Set<TrophyID> {
        var snapshot = TrophySnapshot()
        snapshot.badgeMinimum = reach.minimum
        snapshot.badgeMaximum = reach.maximum
        snapshot.badgeTileSize = tile
        return Set(TrophyEvaluator.evaluate(snapshot, state: settled).unlocked)
    }

    /// The whole point: dragged as far as it goes, with a character on, both
    /// trophies are now actually awarded.
    func testTheTrophiesAreReachableWithACharacterOn() {
        let reach = sizing.reachableRange(spriteWidth: cells,
                                          backingScale: 1,
                                          minimumScale: minimumScale)
        XCTAssertTrue(unlocks(tile: reach.maximum, in: reach).contains(.bigBadge))
        XCTAssertTrue(unlocks(tile: reach.minimum, in: reach).contains(.tinyBadge))
    }

    /// And measured against the raw bounds, as it was, neither is — which is
    /// the bug, stated as a test so it cannot come back.
    func testNeitherIsReachableWhenMeasuredAgainstTheBounds() {
        let bounds = (minimum: sizing.minimum, maximum: sizing.maximum)
        let reach = sizing.reachableRange(spriteWidth: cells,
                                          backingScale: 1,
                                          minimumScale: minimumScale)
        XCTAssertFalse(unlocks(tile: reach.maximum, in: bounds).contains(.bigBadge))
        XCTAssertFalse(unlocks(tile: reach.minimum, in: bounds).contains(.tinyBadge))
    }
}
