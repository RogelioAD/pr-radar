import XCTest
@testable import PRRadarCore

final class PressTrackerTests: XCTestCase {

    /// The regression: a press that never moves must be a click, not a drag.
    func testStationaryPressIsAClick() {
        var tracker = PressTracker()
        tracker.begin(zone: .move)
        XCTAssertEqual(tracker.end(), .click)
    }

    func testTinyJitterIsStillAClick() {
        var tracker = PressTracker(threshold: 4)
        tracker.begin(zone: .move)
        XCTAssertNil(tracker.update(distance: 1.5), "under threshold must not drag")
        XCTAssertNil(tracker.update(distance: 3.9))
        XCTAssertEqual(tracker.end(), .click)
    }

    /// The other half of the regression: a real drag must move the window and
    /// must NOT also register as a click that opens the drawer.
    func testTravelBeyondThresholdIsAMove() {
        var tracker = PressTracker(threshold: 4)
        tracker.begin(zone: .move)
        XCTAssertEqual(tracker.update(distance: 12), .move)
        XCTAssertEqual(tracker.end(), .moved)
    }

    func testThresholdIsInclusiveAtTheBoundary() {
        var tracker = PressTracker(threshold: 4)
        tracker.begin(zone: .move)
        XCTAssertEqual(tracker.update(distance: 4), .move)
        XCTAssertEqual(tracker.end(), .moved)
    }

    /// Easing back toward the press point mid-drag must not turn it into a click.
    func testThresholdIsStickyOncePassed() {
        var tracker = PressTracker(threshold: 4)
        tracker.begin(zone: .move)
        XCTAssertEqual(tracker.update(distance: 30), .move)
        XCTAssertEqual(tracker.update(distance: 0.5), .move, "must stay a drag")
        XCTAssertEqual(tracker.end(), .moved)
    }

    func testResizeZoneReportsResize() {
        var tracker = PressTracker(threshold: 4)
        tracker.begin(zone: .resize)
        XCTAssertEqual(tracker.update(distance: 20), .resize)
        XCTAssertEqual(tracker.end(), .resized)
    }

    /// A press on the resize edge that never moves is a click, so tapping the
    /// drawer's top edge still collapses rather than doing nothing.
    func testStationaryPressOnResizeEdgeIsAClick() {
        var tracker = PressTracker()
        tracker.begin(zone: .resize)
        XCTAssertEqual(tracker.end(), .click)
    }

    func testPressOutsideTrackedZonesIsIgnored() {
        var tracker = PressTracker()
        tracker.begin(zone: .none)
        XCTAssertNil(tracker.update(distance: 100), "untracked zone must not drag")
        XCTAssertEqual(tracker.end(), .ignored)
    }

    func testTrackerResetsBetweenPresses() {
        var tracker = PressTracker(threshold: 4)
        tracker.begin(zone: .move)
        _ = tracker.update(distance: 50)
        XCTAssertEqual(tracker.end(), .moved)

        // A fresh stationary press must not inherit the previous drag.
        tracker.begin(zone: .move)
        XCTAssertEqual(tracker.end(), .click)
        XCTAssertFalse(tracker.isDragging)
    }

    func testIsTrackingReflectsState() {
        var tracker = PressTracker()
        XCTAssertFalse(tracker.isTracking)
        tracker.begin(zone: .move)
        XCTAssertTrue(tracker.isTracking)
        _ = tracker.end()
        XCTAssertFalse(tracker.isTracking)
    }
}
