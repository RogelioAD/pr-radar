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
