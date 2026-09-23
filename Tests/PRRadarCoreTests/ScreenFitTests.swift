import XCTest
@testable import PRRadarCore

final class ScreenFitTests: XCTestCase {

    /// A laptop built-in, origin at zero, menu bar taken off the top.
    let laptop = CGRect(x: 0, y: 0, width: 1512, height: 900)
    /// An external monitor sitting to the right of it, as `NSScreen` reports
    /// the arrangement: one coordinate space, the second screen simply further
    /// along x.
    let external = CGRect(x: 1512, y: 0, width: 2560, height: 1415)

    private let badge = CGSize(width: 120, height: 115)

    private func badgeRect(x: CGFloat, y: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: badge)
    }

    // MARK: - The unplugged monitor

    /// The reported bug: the badge was parked on the external display, the
    /// monitor went away, and the widget was still being framed at coordinates
    /// only that monitor covered. Nothing is left to intersect, so it has to
    /// land on the screen that remains rather than staying where it was.
    func testABadgeOnAVanishedScreenIsBroughtBackOntoTheOneLeft() {
        let parked = badgeRect(x: 3900, y: 1200)
        let fitted = ScreenFit.fit(parked, onto: [laptop])
        XCTAssertTrue(laptop.contains(fitted), "badge landed at \(fitted)")
        XCTAssertEqual(fitted.size, parked.size, "only the position should move")
    }

    /// It should arrive at the near corner rather than the middle: the user
    /// parked it bottom-right of a screen to the right, and bottom-right of
    /// what is left is the closest thing to where they put it.
    func testItArrivesAtTheEdgeItWasPushedPast() {
        let fitted = ScreenFit.fit(badgeRect(x: 3900, y: -400), onto: [laptop])
        XCTAssertEqual(fitted.maxX, laptop.maxX, accuracy: 0.5)
        XCTAssertEqual(fitted.minY, laptop.minY, accuracy: 0.5)
    }

    // MARK: - Leaving a valid position alone

    func testABadgeAlreadyOnScreenIsNotMoved() {
        let parked = badgeRect(x: 800, y: 400)
        XCTAssertEqual(ScreenFit.fit(parked, onto: [laptop, external]), parked)
    }

    /// With both displays attached, a badge on the external one is on a screen
    /// and must stay put — the fit runs on every screen change, including ones
    /// that add a display, and it must not drag the widget home each time.
    func testABadgeOnASecondScreenStaysThere() {
        let parked = badgeRect(x: 3900, y: 1200)
        XCTAssertEqual(ScreenFit.fit(parked, onto: [laptop, external]), parked)
    }

    // MARK: - Choosing which screen

    /// Straddling the seam, mostly on the external: the rect belongs to the
    /// screen holding most of it, not to whichever comes first in the list.
    func testTheScreenHoldingMostOfTheRectWins() {
        let straddling = CGRect(x: 1482, y: 400, width: 120, height: 115)
        XCTAssertEqual(ScreenFit.host(of: straddling, among: [laptop, external]), external)
    }

    func testTheFirstFrameIsTheFallbackWhenNothingOverlaps() {
        let stranded = badgeRect(x: 9000, y: 9000)
        XCTAssertEqual(ScreenFit.host(of: stranded, among: [laptop, external]), laptop)
    }

    func testNoScreensLeavesTheRectUntouched() {
        let parked = badgeRect(x: 800, y: 400)
        XCTAssertNil(ScreenFit.host(of: parked, among: []))
        XCTAssertEqual(ScreenFit.fit(parked, onto: []), parked)
    }

    // MARK: - Size

    /// An expanded drawer sized for a tall external monitor does not fit the
    /// laptop, so the height is capped — the list scrolls instead.
    func testATallDrawerIsCappedToTheScreen() {
        let drawer = CGRect(x: 1000, y: 0, width: 440, height: 1300)
        let fitted = ScreenFit.fit(drawer, onto: [laptop])
        XCTAssertEqual(fitted.height, laptop.height, accuracy: 0.5)
        XCTAssertEqual(fitted.width, 440, accuracy: 0.5, "width is layout, not fit")
        XCTAssertTrue(laptop.contains(fitted))
    }

    /// Width is left alone, so a rect wider than the screen cannot be made to
    /// fit. Its leading edge is the one that stays on screen: pushing the left
    /// edge off to honour the right would hide the end everything is read from.
    func testATooWideRectKeepsItsLeadingEdgeOnScreen() {
        let wide = CGRect(x: -200, y: 100, width: 2000, height: 200)
        let fitted = ScreenFit.fit(wide, onto: [laptop])
        XCTAssertEqual(fitted.minX, laptop.minX, accuracy: 0.5)
        XCTAssertEqual(fitted.width, 2000, accuracy: 0.5)
    }
}
