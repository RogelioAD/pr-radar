import XCTest
@testable import PRRadarCore

final class BadgeSizingTests: XCTestCase {

    /// The shipping bounds: the smallest and largest real Dock tile sizes.
    let sizing = BadgeSizing(minimum: 28, maximum: 128)

    // MARK: - Caps

    func testClampsToTheBounds() {
        XCTAssertEqual(sizing.clamp(10), 28)
        XCTAssertEqual(sizing.clamp(48), 48)
        XCTAssertEqual(sizing.clamp(400), 128)
    }

    func testDraggingPastALimitStopsThere() {
        XCTAssertEqual(
            sizing.tileSize(from: 48, corner: .bottomRight, delta: CGPoint(x: 900, y: -900)),
            128)
        XCTAssertEqual(
            sizing.tileSize(from: 48, corner: .bottomRight, delta: CGPoint(x: -900, y: 900)),
            28)
    }

    // MARK: - Direction

    /// Every corner has to grow when pulled away from the badge's centre, and
    /// shrink when pushed towards it. Deltas are in screen coordinates, y up.
    func testEachCornerGrowsWhenPulledOutward() {
        let outward: [(BadgeCorner, CGPoint)] = [
            (.topLeft, CGPoint(x: -10, y: 10)),
            (.topRight, CGPoint(x: 10, y: 10)),
            (.bottomLeft, CGPoint(x: -10, y: -10)),
            (.bottomRight, CGPoint(x: 10, y: -10)),
        ]
        for (corner, delta) in outward {
            XCTAssertEqual(sizing.tileSize(from: 48, corner: corner, delta: delta), 58,
                           "\(corner) should grow")
            let inward = CGPoint(x: -delta.x, y: -delta.y)
            XCTAssertEqual(sizing.tileSize(from: 48, corner: corner, delta: inward), 38,
                           "\(corner) should shrink")
        }
    }

    /// A diagonal drag moves the corner exactly as far as the hand. The
    /// averaging this relies on looks like a missing `sqrt(2)`; it is not, and
    /// the projection it is often mistaken for would run the badge out about
    /// 1.4x ahead of the pointer.
    func testDiagonalDragTracksTheHandOneToOne() {
        XCTAssertEqual(
            sizing.tileSize(from: 48, corner: .bottomRight, delta: CGPoint(x: 20, y: -20)),
            68)
    }

    /// Dragging along one axis only still resizes, at half rate — the square
    /// has to follow both axes and neither may be ignored.
    func testSingleAxisDragMovesAtHalfRate() {
        XCTAssertEqual(
            sizing.tileSize(from: 48, corner: .bottomRight, delta: CGPoint(x: 20, y: 0)),
            58)
    }

    // MARK: - Anchoring

    /// The corner opposite the one under the hand must not move. Everything
    /// else about the badge anchors bottom-right; a drag is the one case where
    /// that is wrong.
    func testOppositeCornerStaysStillForEveryCorner() {
        let frame = CGRect(x: 100, y: 200, width: 56, height: 64)
        let grown = CGSize(width: 76, height: 84)

        let topLeft = BadgeSizing.origin(dragging: .topLeft, in: frame, newSize: grown)
        XCTAssertEqual(CGPoint(x: topLeft.x + grown.width, y: topLeft.y),
                       CGPoint(x: frame.maxX, y: frame.minY),
                       "bottom-right holds")

        let topRight = BadgeSizing.origin(dragging: .topRight, in: frame, newSize: grown)
        XCTAssertEqual(topRight, CGPoint(x: frame.minX, y: frame.minY),
                       "bottom-left holds")

        let bottomLeft = BadgeSizing.origin(dragging: .bottomLeft, in: frame, newSize: grown)
        XCTAssertEqual(CGPoint(x: bottomLeft.x + grown.width, y: bottomLeft.y + grown.height),
                       CGPoint(x: frame.maxX, y: frame.maxY),
                       "top-right holds")

        let bottomRight = BadgeSizing.origin(dragging: .bottomRight, in: frame, newSize: grown)
        XCTAssertEqual(CGPoint(x: bottomRight.x, y: bottomRight.y + grown.height),
                       CGPoint(x: frame.minX, y: frame.maxY),
                       "top-left holds")
    }

    func testEveryCornerIsItsOppositesOpposite() {
        for corner in BadgeCorner.allCases {
            XCTAssertEqual(corner.opposite.opposite, corner)
            XCTAssertNotEqual(corner.opposite.isLeft, corner.isLeft)
            XCTAssertNotEqual(corner.opposite.isTop, corner.isTop)
        }
    }
}
