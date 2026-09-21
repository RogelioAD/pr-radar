import XCTest
@testable import PRRadarCore

final class BadgeZonesTests: XCTestCase {

    let zones = BadgeZones(grip: 12)

    /// A mascot badge at 3x: a 120x115 panel carrying art that fills only part
    /// of it — the widget reserves a mark gutter on the right and bob room
    /// under the character's feet, so with no counts showing the art stops
    /// well short of the bottom.
    let panelHeight: CGFloat = 115
    let art = CGRect(x: 5, y: 0, width: 105, height: 90)

    private func corner(_ x: CGFloat, _ y: CGFloat, flipped: Bool = true) -> BadgeCorner? {
        zones.corner(at: CGPoint(x: x, y: y), art: art,
                     viewHeight: panelHeight, isFlipped: flipped)
    }

    // MARK: - The coordinate flip

    /// NSHostingView is flipped, so a small y is the visual TOP. The badge's
    /// grips have to agree with that or grabbing the top-left resizes from the
    /// bottom-left — the same inversion the drawer's zones were built to
    /// prevent.
    func testTopCornersAreAtSmallYInAFlippedView() {
        XCTAssertEqual(corner(8, 3), .topLeft)
        XCTAssertEqual(corner(107, 3), .topRight)
    }

    func testBottomCornersAreAtLargeYInAFlippedView() {
        XCTAssertEqual(corner(8, 87), .bottomLeft)
        XCTAssertEqual(corner(107, 87), .bottomRight)
    }

    /// A plain NSView is not flipped, where a large y is the visual top. The
    /// art rect is always stated visually, so only the point flips.
    func testCornersInvertInAnUnflippedView() {
        XCTAssertEqual(corner(8, panelHeight - 3, flipped: false), .topLeft)
        XCTAssertEqual(corner(8, panelHeight - 87, flipped: false), .bottomLeft)
    }

    // MARK: - The art, not the panel
    //
    // The bug this replaced: grips anchored to the panel sat out in transparent
    // space, a different distance from the visible badge for every mascot, so
    // the resize cursor appeared somewhere different each time you switched
    // character.

    /// The panel's own bottom-right corner is empty bob room, 25pt below the
    /// art. Grabbing there must do nothing but move the badge.
    func testPanelCornerOutsideTheArtIsNotAGrip() {
        XCTAssertNil(corner(119, 114), "panel bottom-right, far below the character")
        XCTAssertNil(corner(2, 3), "panel left edge, outside the art")
    }

    /// Two mascots whose art starts at a different column must each put their
    /// grip on their own edge, not on a shared panel edge.
    func testGripFollowsWhereTheArtActuallyStarts() {
        let inset = CGRect(x: 10, y: 0, width: 100, height: 90)   // Widget / Nimbus
        XCTAssertNil(zones.corner(at: CGPoint(x: 7, y: 3), art: inset,
                                  viewHeight: panelHeight, isFlipped: true),
                     "7pt is inside Pip's art but outside this one's")
        XCTAssertEqual(zones.corner(at: CGPoint(x: 13, y: 3), art: inset,
                                    viewHeight: panelHeight, isFlipped: true),
                       .topLeft)
    }

    // MARK: - The middle stays move-and-click

    /// The badge's whole job is to be dragged around and clicked open. Corners
    /// must not take that away from the middle.
    func testMiddleIsNotAGrip() {
        XCTAssertNil(corner(art.midX, art.midY))
    }

    /// Corners only, deliberately: the badge resizes as a square, and one edge
    /// cannot say which way.
    func testEdgeMidpointsAreNotGrips() {
        XCTAssertNil(corner(art.midX, 2), "top edge, between the two grips")
        XCTAssertNil(corner(7, art.midY), "left edge, between the two grips")
    }

    func testEmptyArtHasNoGrips() {
        XCTAssertNil(zones.corner(at: .zero, art: .zero,
                                  viewHeight: panelHeight, isFlipped: true))
    }

    // MARK: - The smallest badge

    /// At the 28pt floor, four 12pt grips would meet in the middle and leave
    /// nothing to drag or click. Each is capped at a third of the art so the
    /// middle third always survives.
    func testGripShrinksSoTheMiddleSurvivesOnASmallBadge() {
        XCTAssertEqual(zones.grip(for: 28), 28 / 3, accuracy: 0.001)
        XCTAssertEqual(zones.grip(for: 120), 12, "full grip once there is room for it")

        let small = CGRect(x: 0, y: 7, width: 28, height: 28)
        XCTAssertNil(zones.corner(at: CGPoint(x: 14, y: 21), art: small,
                                  viewHeight: 42, isFlipped: true),
                     "the centre of the smallest badge must still move and click")
        XCTAssertEqual(zones.corner(at: CGPoint(x: 1, y: 8), art: small,
                                    viewHeight: 42, isFlipped: true),
                       .topLeft)
        XCTAssertEqual(zones.corner(at: CGPoint(x: 27, y: 34), art: small,
                                    viewHeight: 42, isFlipped: true),
                       .bottomRight)
    }
}
