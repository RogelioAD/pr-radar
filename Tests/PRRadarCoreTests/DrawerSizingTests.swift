import XCTest
@testable import PRRadarCore

final class DrawerSizingTests: XCTestCase {

    // Simple numbers so expected heights are obvious by hand.
    let sizing = DrawerSizing(rowSpacing: 2, listPadding: 12, chromeHeight: 100,
                              maxHeight: 1000, estimatedRowHeight: 80)

    /// Five rows of 50pt each.
    let rows: [CGFloat] = [50, 50, 50, 50, 50]

    /// n rows of 50 = 50n + 2(n-1) + 12  →  62, 114, 166, 218, 270
    func expected(_ n: Int) -> CGFloat { 50 * CGFloat(n) + 2 * CGFloat(n - 1) + 12 }

    // MARK: - Boundaries

    func testBoundariesAreCumulativePerRow() {
        XCTAssertEqual(sizing.rowBoundaries(rowHeights: rows, itemCount: 5),
                       [62, 114, 166, 218, 270])
    }

    /// Rows differ in height (one- vs two-line titles), so boundaries must sum
    /// the actual rows rather than multiply an average.
    func testBoundariesSumActualRowHeights() {
        let mixed: [CGFloat] = [90, 50, 70]
        XCTAssertEqual(sizing.rowBoundaries(rowHeights: mixed, itemCount: 3),
                       [102, 154, 226])
    }

    func testUnmeasuredRowsFallBackToEstimate() {
        XCTAssertEqual(sizing.rowBoundaries(rowHeights: [], itemCount: 2),
                       [92, 174])   // 80+12, 160+2+12
    }

    func testEmptyListStillHasOneRowOfHeight() {
        XCTAssertEqual(sizing.rowBoundaries(rowHeights: [], itemCount: 0), [92])
    }

    // MARK: - Default: show everything

    func testDefaultShowsEveryRow() {
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: nil)
        XCTAssertEqual(height, expected(5), "no cap should hide rows")
    }

    func testDefaultForASingleRow() {
        XCTAssertEqual(
            sizing.contentHeight(rowHeights: [50], itemCount: 1, userContentHeight: nil),
            expected(1))
    }

    func testDefaultGrowsWithTheList() {
        let heights = (1...5).map {
            sizing.contentHeight(rowHeights: rows, itemCount: $0, userContentHeight: nil)
        }
        XCTAssertEqual(heights, [62, 114, 166, 218, 270])
        XCTAssertEqual(heights, heights.sorted(), "each extra row must add height")
    }

    // MARK: - The screen cap

    /// Capped, and snapped *down* to a row edge — a drawer ending mid-row looks
    /// broken and hides that there is more below.
    func testCapSnapsDownToAWholeRow() {
        // ceiling = 250 - 100 chrome = 150. Largest boundary ≤ 150 is 114 (2 rows).
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: nil, maxHeight: 250)
        XCTAssertEqual(height, expected(2))
    }

    func testCapNeverProducesAPartialRow() {
        let boundaries = Set(sizing.rowBoundaries(rowHeights: rows, itemCount: 5))
        for cap in stride(from: CGFloat(120), through: 400, by: 7) {
            let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                              userContentHeight: nil, maxHeight: cap)
            XCTAssertTrue(boundaries.contains(height),
                          "cap \(cap) produced non-boundary height \(height)")
        }
    }

    /// When not even one row fits, show one anyway rather than nothing.
    func testTooSmallACapStillShowsOneRow() {
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: nil, maxHeight: 110)
        XCTAssertEqual(height, expected(1))
    }

    func testWindowHeightAddsChrome() {
        XCTAssertEqual(
            sizing.windowHeight(rowHeights: rows, itemCount: 5, userContentHeight: nil),
            100 + expected(5))
    }

    // MARK: - Snapping a dragged height

    func testSnapsToTheNearestBoundary() {
        XCTAssertEqual(sizing.snap(160, rowHeights: rows, itemCount: 5), expected(3))
        XCTAssertEqual(sizing.snap(130, rowHeights: rows, itemCount: 5), expected(2))
        XCTAssertEqual(sizing.snap(60, rowHeights: rows, itemCount: 5), expected(1))
    }

    func testSnapRoundsUpWhenNearerTheUpperBoundary() {
        // 150 sits between 114 and 166; 166 is 16 away, 114 is 36 away.
        XCTAssertEqual(sizing.snap(150, rowHeights: rows, itemCount: 5), expected(3))
    }

    func testDraggingBelowOneRowStopsAtOneRow() {
        XCTAssertEqual(sizing.snap(0, rowHeights: rows, itemCount: 5), expected(1))
        XCTAssertEqual(sizing.snap(-500, rowHeights: rows, itemCount: 5), expected(1))
    }

    func testDraggingBeyondEverythingStopsAtEverything() {
        XCTAssertEqual(sizing.snap(5_000, rowHeights: rows, itemCount: 5), expected(5))
    }

    func testSnapRespectsTheCeiling() {
        // Ceiling of 150 leaves only the 62 and 114 boundaries reachable.
        XCTAssertEqual(sizing.snap(5_000, rowHeights: rows, itemCount: 5, limit: 150),
                       expected(2))
    }

    func testEveryDraggedHeightLandsOnARow() {
        let boundaries = Set(sizing.rowBoundaries(rowHeights: rows, itemCount: 5))
        for requested in stride(from: CGFloat(-50), through: 400, by: 3) {
            let snapped = sizing.snap(requested, rowHeights: rows, itemCount: 5)
            XCTAssertTrue(boundaries.contains(snapped),
                          "\(requested) snapped to non-boundary \(snapped)")
        }
    }

    // MARK: - User height through the main entry point

    func testUserHeightIsSnappedNotHonouredLiterally() {
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: 160)
        XCTAssertEqual(height, expected(3), "a stored odd height must still snap")
    }

    /// The point of the handle now: making the drawer shorter than the full list.
    func testUserCanShrinkBelowTheFullList() {
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: expected(2))
        XCTAssertEqual(height, expected(2))
        XCTAssertLessThan(height, expected(5))
    }

    func testUserHeightIsCappedByTheScreen() {
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: expected(5),
                                          maxHeight: 250)
        XCTAssertEqual(height, expected(2), "the screen still wins")
    }

    /// A height stored while the list was long must not strand the drawer when
    /// the list shrinks.
    func testStoredHeightFromALongerListCollapsesToWhatExists() {
        let height = sizing.contentHeight(rowHeights: [50], itemCount: 1,
                                          userContentHeight: 270)
        XCTAssertEqual(height, expected(1))
    }

    // MARK: - Mixed row heights end to end

    func testSnappingWithUnevenRows() {
        let mixed: [CGFloat] = [90, 50, 70]   // boundaries 102, 154, 226
        XCTAssertEqual(sizing.snap(120, rowHeights: mixed, itemCount: 3), 102)
        XCTAssertEqual(sizing.snap(140, rowHeights: mixed, itemCount: 3), 154)
        XCTAssertEqual(sizing.snap(200, rowHeights: mixed, itemCount: 3), 226)
    }
}
