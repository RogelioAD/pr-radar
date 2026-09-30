import XCTest
@testable import PRRadarCore

/// Whether a badge can actually be dragged to the sizes its bounds name.
///
/// It could not, for one release. A mascot badge was drawn at a snapped
/// scale, so its size was the character's cell height times a whole number of
/// device pixels — 54 and 108 on a 1x screen, inside bounds of 28 and 128.
/// Both ends were unreachable, which made the badge-size trophies unwinnable
/// and the drag itself feel broken. The badge rests where it is let go now.
final class BadgeReachTests: XCTestCase {

    /// A 48-cell character in its widget block.
    private let cells = 54
    /// Below this the counter's digits stop being a number.
    private let floor = CGFloat(10) / 21

    private func tile(_ points: CGFloat) -> CGFloat {
        CGFloat(cells) * SpriteScale.continuous(targetPoints: points,
                                                spriteWidth: cells, minimum: floor)
    }

    func testBothBoundsAreReachableExactly() {
        let sizing = BadgeSizing(minimum: 28, maximum: 128)
        XCTAssertEqual(tile(sizing.minimum), sizing.minimum, accuracy: 0.001)
        XCTAssertEqual(tile(sizing.maximum), sizing.maximum, accuracy: 0.001)
    }

    /// And so is everything between them, which is the whole point: a drag
    /// that can only stop at two places is not a drag.
    func testEverySizeBetweenTheBoundsIsReachable() {
        for points in stride(from: CGFloat(28), through: 128, by: 0.5) {
            XCTAssertEqual(tile(points), points, accuracy: 0.001, "\(points)")
        }
    }

    /// The one limit that survives, and it is a legibility limit rather than
    /// a pixel-grid one.
    func testTheDigitFloorStillHolds() {
        XCTAssertEqual(SpriteScale.continuous(targetPoints: 4, spriteWidth: cells,
                                              minimum: floor), floor)
    }
}
