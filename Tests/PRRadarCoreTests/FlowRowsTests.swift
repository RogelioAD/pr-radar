import XCTest
@testable import PRRadarCore

/// Wrapping is arithmetic, and the view layer already got chip rows wrong once
/// by leaning on `HStack` — so the rule is pinned here.
final class FlowRowsTests: XCTestCase {

    let flow = FlowRows(spacing: 4, lineSpacing: 4)

    private func chips(_ widths: [CGFloat], height: CGFloat = 18) -> [CGSize] {
        widths.map { CGSize(width: $0, height: height) }
    }

    // MARK: - Fitting

    func testItemsThatFitStayOnOneLine() {
        let placement = flow.place(chips([50, 50, 50]), within: 200)
        XCTAssertEqual(placement.offsets.map(\.y), [0, 0, 0])
        XCTAssertEqual(placement.offsets.map(\.x), [0, 54, 108])
        XCTAssertEqual(placement.size.height, 18, "one line tall")
    }

    /// The reported width is the run's, not the container's, so a short row
    /// does not claim space it is not using.
    func testWidthIsTheLongestRunWithoutTrailingSpacing() {
        XCTAssertEqual(flow.place(chips([50, 50]), within: 200).size.width, 104)
    }

    // MARK: - Wrapping

    func testTheItemThatWillNotFitStartsANewLine() {
        let placement = flow.place(chips([80, 80, 80]), within: 200)
        XCTAssertEqual(placement.offsets.map(\.y), [0, 0, 22], "third wraps")
        XCTAssertEqual(placement.offsets.map(\.x), [0, 84, 0])
        XCTAssertEqual(placement.size.height, 18 + 4 + 18, "two lines and the gap")
    }

    /// A line's height is its tallest item, so a wrapped line clears whatever
    /// was on the one above it.
    func testLineHeightIsTheTallestItemOnThatLine() {
        let sizes = [CGSize(width: 80, height: 30), CGSize(width: 80, height: 18),
                     CGSize(width: 80, height: 18)]
        let placement = flow.place(sizes, within: 200)
        XCTAssertEqual(placement.offsets[2].y, 34, "cleared the 30pt item above")
        XCTAssertEqual(placement.size.height, 30 + 4 + 18)
    }

    // MARK: - The edges

    /// Dropping it would hide a chip, and a chip is on a row because something
    /// is true about the PR.
    func testAnItemWiderThanTheLineIsStillPlaced() {
        let placement = flow.place(chips([300]), within: 200)
        XCTAssertEqual(placement.offsets, [.zero])
        XCTAssertEqual(placement.size.width, 200, "but it never reports more than it was given")
    }

    /// The whole point of this type: what contains it does not grow.
    func testAnOverflowingRunNeverReportsMoreThanTheWidthItWasGiven() {
        let placement = flow.place(chips([150, 150, 150]), within: 200)
        XCTAssertLessThanOrEqual(placement.size.width, 200)
    }

    func testNoItemsIsNoSize() {
        let placement = flow.place([], within: 200)
        XCTAssertEqual(placement.size, .zero)
        XCTAssertTrue(placement.offsets.isEmpty)
    }

    /// An unconstrained proposal is how SwiftUI asks "how wide would you like
    /// to be" — nothing should wrap.
    func testAnInfiniteWidthNeverWraps() {
        let placement = flow.place(chips([80, 80, 80]), within: .infinity)
        XCTAssertEqual(placement.offsets.map(\.y), [0, 0, 0])
        XCTAssertEqual(placement.size.width, 80 * 3 + 4 * 2)
    }

    /// Every item gets an offset, whatever happens — the view places subviews
    /// by index and would trap on a short array.
    func testEveryItemGetsAnOffset() {
        for count in 0...12 {
            let placement = flow.place(chips(Array(repeating: 70, count: count)), within: 200)
            XCTAssertEqual(placement.offsets.count, count)
        }
    }
}
