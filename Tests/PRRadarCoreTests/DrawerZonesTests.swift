import XCTest
@testable import PRRadarCore

final class DrawerZonesTests: XCTestCase {

    let zones = DrawerZones(headerHeight: 40, resizeEdge: 6)
    let viewHeight: CGFloat = 360

    // MARK: - The coordinate flip that caused the bug

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
        XCTAssertEqual(zones.zone(distanceFromTop: distance, canResize: true), .none,
                       "the footer must not be a drag zone")
        XCTAssertEqual(zones.zone(distanceFromTop: distance, canResize: false), .none)
    }

    func testHeaderPressMovesTheWindowInAFlippedView() {
        let headerY: CGFloat = 20    // near the visual top of a flipped view
        let distance = DrawerZones.distanceFromTop(
            pointY: headerY, viewHeight: viewHeight, isFlipped: true)
        XCTAssertEqual(zones.zone(distanceFromTop: distance, canResize: false), .move)
    }

    // MARK: - Zone boundaries

    func testTopEdgeResizesWhenResizable() {
        XCTAssertEqual(zones.zone(distanceFromTop: 0, canResize: true), .resize)
        XCTAssertEqual(zones.zone(distanceFromTop: 6, canResize: true), .resize)
    }

    /// With nothing to expand into there is no handle, so the strip must fall
    /// through to the header's move behaviour rather than resizing.
    func testTopEdgeMovesWhenNotResizable() {
        XCTAssertEqual(zones.zone(distanceFromTop: 0, canResize: false), .move)
        XCTAssertEqual(zones.zone(distanceFromTop: 6, canResize: false), .move)
    }

    func testJustBelowTheEdgeIsTheHeader() {
        XCTAssertEqual(zones.zone(distanceFromTop: 6.5, canResize: true), .move)
        XCTAssertEqual(zones.zone(distanceFromTop: 40, canResize: true), .move)
    }

    func testBelowTheHeaderBelongsToSwiftUI() {
        XCTAssertEqual(zones.zone(distanceFromTop: 41, canResize: true), .none)
        XCTAssertEqual(zones.zone(distanceFromTop: 200, canResize: true), .none)
    }

    /// The filter bar sits directly under the header and holds two menus, so
    /// it must not be swallowed by the drag zone either.
    func testFilterBarBelongsToSwiftUI() {
        XCTAssertEqual(zones.zone(distanceFromTop: 45, canResize: true), .none)
        XCTAssertEqual(zones.zone(distanceFromTop: 70, canResize: true), .none)
    }

    func testNegativeDistanceIsIgnored() {
        XCTAssertEqual(zones.zone(distanceFromTop: -5, canResize: true), .none)
    }

    // MARK: - Controls inside the drag band

    /// Roughly where the update chip and the collapse button sit: inside the
    /// header, over on the trailing side.
    let chip = CGRect(x: 300, y: 12, width: 92, height: 20)
    let collapse = CGRect(x: 404, y: 14, width: 16, height: 16)

    /// The bug, stated directly: a press on the update chip must reach SwiftUI.
    /// Taken as a drag it never reaches the button, and the press ends up read
    /// as a click on the header — collapsing the drawer instead of opening the
    /// release page the chip exists to link to.
    func testPressOnTheUpdateChipIsHandedToSwiftUI() {
        XCTAssertEqual(zones.zone(distanceFromTop: 22, distanceFromLeft: 340,
                                  canResize: true, controls: [chip, collapse]), .none)
    }

    func testPressOnTheCollapseButtonIsHandedToSwiftUI() {
        XCTAssertEqual(zones.zone(distanceFromTop: 22, distanceFromLeft: 410,
                                  canResize: true, controls: [chip, collapse]), .none)
    }

    /// The rest of the header still drags, or the drawer could not be moved.
    func testHeaderBesideTheControlsStillMoves() {
        XCTAssertEqual(zones.zone(distanceFromTop: 22, distanceFromLeft: 40,
                                  canResize: true, controls: [chip, collapse]), .move)
        // Between the two controls.
        XCTAssertEqual(zones.zone(distanceFromTop: 22, distanceFromLeft: 396,
                                  canResize: true, controls: [chip, collapse]), .move)
    }

    /// With no update published there is no chip, so that same point drags.
    func testHeaderDragsWhereAChipIsAbsent() {
        XCTAssertEqual(zones.zone(distanceFromTop: 22, distanceFromLeft: 340,
                                  canResize: true, controls: [collapse]), .move)
    }

    /// A control overlapping the grab strip must not eat it: resize is resolved
    /// first, or the drawer would lose its handle wherever a chip reached up.
    func testResizeStripWinsOverAnOverlappingControl() {
        let overlapping = CGRect(x: 300, y: 0, width: 92, height: 30)
        XCTAssertEqual(zones.zone(distanceFromTop: 3, distanceFromLeft: 340,
                                  canResize: true, controls: [overlapping]), .resize)
    }

    /// Below the header nothing changes — it already belonged to SwiftUI.
    func testControlsDoNotAffectTheAreaBelowTheHeader() {
        XCTAssertEqual(zones.zone(distanceFromTop: 200, distanceFromLeft: 340,
                                  canResize: true, controls: [chip]), .none)
    }

    /// Every point in a realistic drawer resolves to exactly one zone, and the
    /// drag zones together never exceed the header's height.
    func testDragZonesNeverExtendPastTheHeader() {
        for y in stride(from: CGFloat(0), through: viewHeight, by: 1) {
            let zone = zones.zone(distanceFromTop: y, canResize: true)
            if zone != .none {
                XCTAssertLessThanOrEqual(y, zones.headerHeight,
                                         "zone \(zone) leaked past the header at y=\(y)")
            }
        }
    }
}
