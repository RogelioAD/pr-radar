import XCTest
@testable import PRRadarCore

final class RowSegmentsTests: XCTestCase {

    /// What the sizing does with a flattened row, so the sum invariant can be
    /// checked the way the drawer actually experiences it.
    private func laidOut(_ pieces: [CGFloat], spacing: CGFloat) -> CGFloat {
        pieces.reduce(0, +) + spacing * CGFloat(max(pieces.count - 1, 0))
    }

    // MARK: - The invariant that keeps the drawer honest

    /// **A split row must occupy exactly what the unsplit row measured.**
    ///
    /// `DrawerSizing` inserts `rowSpacing` between every entry, so pieces that
    /// did not give that spacing back would make the drawer believe its own
    /// content is taller than it is — by a few points per comment. The last row
    /// would never reach the bottom edge, and the error would grow with every
    /// thread opened.
    func testASplitRowLaysOutToExactlyItsMeasuredHeight() {
        let pieces = RowSegments.split(height: 300, cuts: [60, 140, 220], spacing: 4)
        XCTAssertEqual(pieces.count, 4)
        XCTAssertEqual(laidOut(pieces, spacing: 4), 300, accuracy: 0.001)
    }

    func testTheInvariantHoldsAcrossManyShapes() {
        for height in stride(from: CGFloat(80), through: 900, by: 37) {
            for count in 1...6 {
                let cuts = (1...count).map { height * CGFloat($0) / CGFloat(count + 1) }
                let pieces = RowSegments.split(height: height, cuts: cuts, spacing: 4)
                XCTAssertEqual(laidOut(pieces, spacing: 4), height, accuracy: 0.001,
                               "height \(height) with \(count) cuts")
            }
        }
    }

    // MARK: - Splitting

    func testTheFirstPieceKeepsItsFullHeight() {
        // Only the pieces after the first give a spacing back; the first one
        // has no gap in front of it to give.
        XCTAssertEqual(RowSegments.split(height: 300, cuts: [60], spacing: 4),
                       [60, 236])
    }

    func testARowWithNoCutsIsASingleStop() {
        XCTAssertEqual(RowSegments.split(height: 120, cuts: [], spacing: 4), [120])
    }

    func testCutsAreSortedBeforeTheyAreUsed() {
        XCTAssertEqual(RowSegments.split(height: 300, cuts: [220, 60, 140], spacing: 4),
                       RowSegments.split(height: 300, cuts: [60, 140, 220], spacing: 4))
    }

    /// A measurement taken mid-animation can report an edge outside the row.
    /// Dropped rather than clamped: clamping makes a zero-height stop, which
    /// the drag can land on and appear stuck at.
    func testCutsOutsideTheRowAreDropped() {
        XCTAssertEqual(RowSegments.split(height: 120, cuts: [-10, 0, 120, 300],
                                         spacing: 4),
                       [120])
    }

    /// Two cuts a point apart are one stop. Admitting both gives the drag two
    /// targets it cannot be aimed at separately.
    func testCutsTooCloseTogetherCollapseToOne() {
        let pieces = RowSegments.split(height: 300, cuts: [60, 62, 64], spacing: 4)
        XCTAssertEqual(pieces, [60, 236])
    }

    /// A cut so near the bottom that the last piece would be a sliver leaves
    /// the row whole instead.
    func testACutAgainstTheBottomEdgeIsNotAStop() {
        XCTAssertEqual(RowSegments.split(height: 120, cuts: [118], spacing: 4), [120])
    }

    func testAZeroHeightRowHasNoStops() {
        XCTAssertTrue(RowSegments.split(height: 0, cuts: [10], spacing: 4).isEmpty)
    }

    /// A piece must never be negative, or opening a thread would *shrink* the
    /// list it is on.
    func testNoPieceIsEverNegative() {
        let pieces = RowSegments.split(height: 100, cuts: [20, 34, 48], spacing: 30)
        XCTAssertTrue(pieces.allSatisfy { $0 > 0 }, "\(pieces)")
    }

    // MARK: - Through the sizing

    /// The point of the whole thing: a tall row with comments on it offers a
    /// stop per comment, so the drag can settle between them.
    func testCommentsBecomeStopsTheDrawerCanSnapTo() {
        let sizing = DrawerSizing(rowSpacing: 2, listPadding: 12, chromeHeight: 100,
                                  maxHeight: 1000, estimatedRowHeight: 80)
        // One ordinary row, then a row with four comments open.
        let pieces = RowSegments.split(height: 420, cuts: [120, 220, 320],
                                       spacing: 2)
        let heights = [50] + pieces

        let boundaries = sizing.rowBoundaries(rowHeights: heights,
                                              itemCount: heights.count)
        XCTAssertEqual(boundaries.count, 5, "one stop per comment, plus the row above")

        // Dragging to roughly the second comment settles on it rather than
        // snapping back past the whole row.
        let nearSecond = boundaries[2]
        XCTAssertEqual(sizing.snap(nearSecond + 8, rowHeights: heights,
                                   itemCount: heights.count, limit: 900),
                       nearSecond)

        // And the last boundary still equals the unsplit list's total, so the
        // drawer can still open to exactly everything.
        let unsplit = sizing.rowBoundaries(rowHeights: [50, 420], itemCount: 2).last
        XCTAssertEqual(boundaries.last!, unsplit!, accuracy: 0.001)
    }
}
