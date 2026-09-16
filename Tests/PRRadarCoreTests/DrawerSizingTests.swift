import XCTest
@testable import PRRadarCore

final class DrawerSizingTests: XCTestCase {

    // Simple numbers so expected heights are obvious by hand.
    let sizing = DrawerSizing(rowSpacing: 2, listPadding: 12, chromeHeight: 100,
                              defaultVisibleRows: 3, maxHeight: 1000,
                              estimatedRowHeight: 80)

    /// Five rows of 50pt each.
    let rows: [CGFloat] = [50, 50, 50, 50, 50]

    /// n rows of 50 = 50n + 2(n-1) + 12
    func expected(_ n: Int) -> CGFloat { 50 * CGFloat(n) + 2 * CGFloat(n - 1) + 12 }

    // MARK: - Shrinking below the default

    func testOneRowShrinksToFit() {
        let height = sizing.contentHeight(rowHeights: [50], itemCount: 1, userContentHeight: nil)
        XCTAssertEqual(height, expected(1))
    }

    func testTwoRowsShrinkToFit() {
        let height = sizing.contentHeight(rowHeights: [50, 50], itemCount: 2,
                                          userContentHeight: nil)
        XCTAssertEqual(height, expected(2))
    }

    func testEachStepDownIsSmaller() {
        let three = sizing.contentHeight(rowHeights: rows, itemCount: 3, userContentHeight: nil)
        let two = sizing.contentHeight(rowHeights: rows, itemCount: 2, userContentHeight: nil)
        let one = sizing.contentHeight(rowHeights: rows, itemCount: 1, userContentHeight: nil)
        XCTAssertGreaterThan(three, two)
        XCTAssertGreaterThan(two, one)
    }

    // MARK: - The three-row default and cap

    func testThreeRowsIsTheDefault() {
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 3, userContentHeight: nil)
        XCTAssertEqual(height, expected(3))
    }

    func testMoreThanThreeRowsStaysAtThreeRowHeight() {
        for count in 4...5 {
            let height = sizing.contentHeight(rowHeights: rows, itemCount: count,
                                              userContentHeight: nil)
            XCTAssertEqual(height, expected(3), "\(count) items should still show 3 rows")
        }
    }

    // MARK: - User resizing

    func testUserHeightIsHonouredBetweenTheLimits() {
        let midpoint = (expected(3) + expected(5)) / 2
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: midpoint)
        XCTAssertEqual(height, midpoint)
    }

    func testUserHeightCannotGoBelowThreeRows() {
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: 10)
        XCTAssertEqual(height, expected(3), "three rows is the floor")
    }

    func testUserHeightCannotExceedAllRows() {
        let height = sizing.contentHeight(rowHeights: rows, itemCount: 5,
                                          userContentHeight: 5_000)
        XCTAssertEqual(height, expected(5), "no empty space past the last row")
    }

    /// With everything already visible there is nothing to expand into, so a
    /// height left over from a longer list must not pad the drawer out.
    func testUserHeightIgnoredWhenAllRowsAlreadyFit() {
        let height = sizing.contentHeight(rowHeights: [50, 50], itemCount: 2,
                                          userContentHeight: 600)
        XCTAssertEqual(height, expected(2))
    }

    // MARK: - Chrome and bounds

    func testWindowHeightAddsChrome() {
        let height = sizing.windowHeight(rowHeights: rows, itemCount: 3,
                                         userContentHeight: nil)
        XCTAssertEqual(height, 100 + expected(3))
    }

    func testWindowHeightRespectsMaximum() {
        let tall = DrawerSizing(rowSpacing: 2, listPadding: 12, chromeHeight: 100,
                                defaultVisibleRows: 3, maxHeight: 200,
                                estimatedRowHeight: 80)
        let height = tall.windowHeight(rowHeights: rows, itemCount: 5,
                                       userContentHeight: 5_000)
        XCTAssertEqual(height, 200)
    }

    func testUnmeasuredRowsFallBackToEstimate() {
        // No measurements yet: three rows at the 80pt estimate.
        let height = sizing.contentHeight(rowHeights: [], itemCount: 3, userContentHeight: nil)
        XCTAssertEqual(height, 80 * 3 + 2 * 2 + 12)
    }

    func testEmptyListStillHasOneRowOfHeight() {
        let height = sizing.contentHeight(rowHeights: [], itemCount: 0, userContentHeight: nil)
        XCTAssertEqual(height, sizing.contentHeight(rowHeights: [], rows: 1))
    }

    /// Rows vary in height (one- vs two-line titles), so the cap has to sum
    /// the actual first three rather than multiply an average.
    func testCapSumsTheActualFirstThreeRows() {
        let mixed: [CGFloat] = [90, 50, 70, 200, 200]
        let height = sizing.contentHeight(rowHeights: mixed, itemCount: 5,
                                          userContentHeight: nil)
        XCTAssertEqual(height, 90 + 50 + 70 + 2 * 2 + 12)
    }
}

final class ReviewSortOrderTests: XCTestCase {

    func item(_ number: Int, _ author: String, _ iso: String) -> ReviewItem {
        ReviewItem(repo: "o/r", number: number, title: "t",
                   url: URL(string: "https://example.com/\(number)")!, isDraft: false,
                   authorLogin: author, authorAvatarURL: nil,
                   pingedAt: ISO8601DateFormatter().date(from: iso)!)
    }

    var items: [ReviewItem] {
        [item(1, "carmynatt", "2026-09-03T19:32:15Z"),
         item(2, "benjaminrevelo", "2026-09-15T13:37:09Z"),
         item(3, "mattiatelevation", "2026-09-15T11:01:40Z")]
    }

    func testOldestFirst() {
        XCTAssertEqual(ReviewSortOrder.oldestFirst.apply(to: items).map(\.number), [1, 3, 2])
    }

    func testNewestFirst() {
        XCTAssertEqual(ReviewSortOrder.newestFirst.apply(to: items).map(\.number), [2, 3, 1])
    }

    func testAuthorAZ() {
        XCTAssertEqual(ReviewSortOrder.authorAZ.apply(to: items).map(\.authorLogin),
                       ["benjaminrevelo", "carmynatt", "mattiatelevation"])
    }

    func testAuthorAZTiesBreakOnOldestFirst() {
        let sameAuthor = [item(1, "dana", "2026-09-15T00:00:00Z"),
                          item(2, "dana", "2026-09-03T00:00:00Z")]
        XCTAssertEqual(ReviewSortOrder.authorAZ.apply(to: sameAuthor).map(\.number), [2, 1])
    }

    func testEveryOrderIsStableInCount() {
        for order in ReviewSortOrder.allCases {
            XCTAssertEqual(order.apply(to: items).count, 3, "\(order) dropped items")
        }
    }
}
