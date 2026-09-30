import XCTest
@testable import PRRadarCore

final class DrawerZonesTests: XCTestCase {

    let zones = DrawerZones(headerHeight: 40, resizeEdge: 6, resizeHandle: 72)
    let viewHeight: CGFloat = 360
    let width: CGFloat = 440

    /// The handle sits at 184...256 in a 440pt drawer; these are inside it and
    /// well outside it.
    let onHandle: CGFloat = 220
    let offHandle: CGFloat = 40

    private func zone(_ top: CGFloat,
                      _ left: CGFloat,
                      canResize: Bool = true,
                      controls: [CGRect] = []) -> PressTracker.Zone {
        zones.zone(distanceFromTop: top, distanceFromLeft: left,
                   width: width, canResize: canResize, controls: controls)
    }

    // MARK: - The coordinate flip that caused the first bug

    /// NSHostingView is flipped, so a small y is the visual TOP.
    func testFlippedViewMeasuresFromTopDirectly() {
        XCTAssertEqual(
            DrawerZones.distanceFromTop(pointY: 3, viewHeight: viewHeight, isFlipped: true), 3)
        XCTAssertEqual(
            DrawerZones.distanceFromTop(pointY: 350, viewHeight: viewHeight, isFlipped: true), 350)
    }

    /// A plain NSView is not flipped, where a large y is the visual top.
    func testUnflippedViewMeasuresFromTheOtherEnd() {
        XCTAssertEqual(
            DrawerZones.distanceFromTop(pointY: 357, viewHeight: viewHeight, isFlipped: false), 3)
        XCTAssertEqual(
            DrawerZones.distanceFromTop(pointY: 10, viewHeight: viewHeight, isFlipped: false), 350)
    }

    /// The regression, stated directly: a press on the footer must reach
    /// SwiftUI so the Refresh button works, and must not be read as a press on
    /// the header (which would toggle the drawer shut).
    func testFooterPressIsHandedToSwiftUIInAFlippedView() {
        let footerY: CGFloat = 350   // near the visual bottom of a flipped view
        let distance = DrawerZones.distanceFromTop(
            pointY: footerY, viewHeight: viewHeight, isFlipped: true)
        XCTAssertEqual(zone(distance, onHandle), .none, "the footer must not be a drag zone")
        XCTAssertEqual(zone(distance, onHandle, canResize: false), .none)
    }

    func testHeaderPressMovesTheWindowInAFlippedView() {
        let headerY: CGFloat = 20    // near the visual top of a flipped view
        let distance = DrawerZones.distanceFromTop(
            pointY: headerY, viewHeight: viewHeight, isFlipped: true)
        XCTAssertEqual(zone(distance, offHandle, canResize: false), .move)
    }

    // MARK: - The top edge

    /// The bug this rule exists for: the top edge of a window is where a hand
    /// goes to move it, and the whole of it used to resize. The drawer could
    /// then only be moved from the bare material beside the title, which reads
    /// as a window that cannot be moved at all.
    func testTopEdgeBesideTheHandleMovesTheWindow() {
        for left in [CGFloat(0), 8, 100, 180, 260, 400, width] {
            XCTAssertEqual(zone(0, left), .move, "x=\(left) at the very top")
            XCTAssertEqual(zone(3, left), .move, "x=\(left) inside the strip")
        }
    }

    func testTheHandleItselfResizes() {
        XCTAssertEqual(zone(0, onHandle), .resize)
        XCTAssertEqual(zone(6, onHandle), .resize)
        // Both ends of it, so the span is centred rather than merely present.
        XCTAssertEqual(zone(3, 185), .resize)
        XCTAssertEqual(zone(3, 255), .resize)
    }

    func testTheHandleIsCentredAndNoWiderThanItSays() {
        let span = zones.handleSpan(width: width)
        XCTAssertEqual(span.lowerBound, 184, accuracy: 0.001)
        XCTAssertEqual(span.upperBound, 256, accuracy: 0.001)
        XCTAssertEqual(span.upperBound - span.lowerBound, zones.resizeHandle, accuracy: 0.001)
        XCTAssertEqual((span.lowerBound + span.upperBound) / 2, width / 2, accuracy: 0.001)
    }

    /// A panel narrower than the handle must not report a strip starting at a
    /// negative column — that is the whole edge resizing again, by arithmetic.
    func testTheHandleNeverOverhangsANarrowDrawer() {
        let narrow = DrawerZones(headerHeight: 40, resizeEdge: 6, resizeHandle: 72)
        let span = narrow.handleSpan(width: 40)
        XCTAssertGreaterThanOrEqual(span.lowerBound, 0)
        XCTAssertLessThanOrEqual(span.upperBound, 40)
    }

    /// With nothing to expand into there is no handle, so even its own column
    /// falls through to the move behaviour.
    func testTopEdgeMovesEverywhereWhenNotResizable() {
        XCTAssertEqual(zone(0, onHandle, canResize: false), .move)
        XCTAssertEqual(zone(6, onHandle, canResize: false), .move)
        XCTAssertEqual(zone(3, offHandle, canResize: false), .move)
    }

    // MARK: - Zone boundaries

    func testJustBelowTheEdgeIsTheHeader() {
        XCTAssertEqual(zone(6.5, onHandle), .move)
        XCTAssertEqual(zone(40, onHandle), .move)
    }

    func testBelowTheHeaderBelongsToSwiftUI() {
        XCTAssertEqual(zone(41, offHandle), .none)
        XCTAssertEqual(zone(200, offHandle), .none)
    }

    /// The filter bar sits directly under the header and holds two menus, so
    /// it must not be swallowed by the drag zone either.
    func testFilterBarBelongsToSwiftUI() {
        XCTAssertEqual(zone(45, offHandle), .none)
        XCTAssertEqual(zone(70, offHandle), .none)
    }

    func testNegativeDistanceIsIgnored() {
        XCTAssertEqual(zone(-5, onHandle), .none)
    }

    // MARK: - Controls inside the drag band

    /// Roughly where the update chip and the collapse button sit: inside the
    /// header, over on the trailing side.
    let chip = CGRect(x: 300, y: 12, width: 92, height: 20)
    let collapse = CGRect(x: 404, y: 14, width: 16, height: 16)
    /// The header mascot, which is a button too — and, at 66pt, the widest
    /// thing in the band.
    let mascot = CGRect(x: 12, y: 11, width: 66, height: 38)

    /// The bug, stated directly: a press on the update chip must reach SwiftUI.
    /// Taken as a drag it never reaches the button, and the press ends up read
    /// as a click on the header — collapsing the drawer instead of opening the
    /// release page the chip exists to link to.
    func testPressOnTheUpdateChipIsHandedToSwiftUI() {
        XCTAssertEqual(zone(22, 340, controls: [chip, collapse]), .none)
    }

    func testPressOnTheCollapseButtonIsHandedToSwiftUI() {
        XCTAssertEqual(zone(22, 410, controls: [chip, collapse]), .none)
    }

    func testPressOnTheHeaderMascotIsHandedToSwiftUI() {
        XCTAssertEqual(zone(30, 45, controls: [mascot]), .none)
    }

    /// The rest of the header still drags, or the drawer could not be moved.
    func testHeaderBesideTheControlsStillMoves() {
        XCTAssertEqual(zone(22, 120, controls: [mascot, chip, collapse]), .move)
        // Between the two trailing controls.
        XCTAssertEqual(zone(22, 396, controls: [chip, collapse]), .move)
    }

    /// With no update published there is no chip, so that same point drags.
    func testHeaderDragsWhereAChipIsAbsent() {
        XCTAssertEqual(zone(22, 340, controls: [collapse]), .move)
    }

    /// A control overlapping the grab strip must not eat it: the handle is
    /// resolved first, or the drawer would lose it wherever a chip reached up.
    func testTheHandleWinsOverAnOverlappingControl() {
        let overlapping = CGRect(x: 180, y: 0, width: 92, height: 30)
        XCTAssertEqual(zone(3, onHandle, controls: [overlapping]), .resize)
    }

    /// Off the handle it is a control like any other, though — the top edge
    /// moves the window there, so a button reaching up into it still owns its
    /// click rather than being handed a drag it cannot use.
    func testAControlOnTheEdgeBesideTheHandleKeepsItsClick() {
        let reachesTheEdge = CGRect(x: 12, y: 0, width: 66, height: 38)
        XCTAssertEqual(zone(3, 45, controls: [reachesTheEdge]), .none)
        // And the header mascot, which stops just short of it, does not claim
        // the edge above itself.
        XCTAssertEqual(zone(3, 45, controls: [mascot]), .move)
    }

    /// Below the header nothing changes — it already belonged to SwiftUI.
    func testControlsDoNotAffectTheAreaBelowTheHeader() {
        XCTAssertEqual(zone(200, 340, controls: [chip]), .none)
    }

    /// Every point in a realistic drawer resolves to exactly one zone, and the
    /// drag zones together never exceed the header's height.
    func testDragZonesNeverExtendPastTheHeader() {
        for y in stride(from: CGFloat(0), through: viewHeight, by: 1) {
            for x in stride(from: CGFloat(0), through: width, by: 20) {
                let zone = zone(y, x)
                if zone != .none {
                    XCTAssertLessThanOrEqual(y, zones.headerHeight,
                                             "zone \(zone) leaked past the header at (\(x), \(y))")
                }
            }
        }
    }

    /// Most of the top edge has to move the window, or the fix is nominal.
    /// Stated as a proportion rather than as a list of columns so it keeps
    /// meaning something if the handle is ever widened.
    func testTheTopEdgeIsOverwhelminglyAHandleForMoving() {
        let columns = Array(stride(from: CGFloat(0), through: width, by: 1))
        let moving = columns.filter { zone(2, $0) == .move }.count
        let total = columns.count
        XCTAssertGreaterThan(Double(moving) / Double(total), 0.8,
                             "only \(moving)/\(total) of the top edge moves the window")
    }
}
