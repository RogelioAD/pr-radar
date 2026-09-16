import CoreGraphics

/// Maps a point in the drawer onto what a press there should do.
///
/// Extracted and tested because the view layer got this wrong once already:
/// `NSHostingView.isFlipped` is `true`, so its coordinates run top-left
/// origin, the opposite of a plain `NSView`. The original code compared
/// against `bounds.height - inset` as though y grew upward, which inverted
/// every zone — the drawer's *footer* became the drag handle, so clicking
/// Refresh registered as a click on the header and collapsed the drawer,
/// while the real header and resize edge did nothing at all.
public struct DrawerZones: Sendable {
    public let headerHeight: CGFloat
    public let resizeEdge: CGFloat

    public init(headerHeight: CGFloat, resizeEdge: CGFloat) {
        self.headerHeight = headerHeight
        self.resizeEdge = resizeEdge
    }

    /// Converts a view-space y into a distance measured from the visual top,
    /// which is the only frame of reference the zone rules should care about.
    public static func distanceFromTop(pointY: CGFloat,
                                       viewHeight: CGFloat,
                                       isFlipped: Bool) -> CGFloat {
        isFlipped ? pointY : viewHeight - pointY
    }

    /// `canResize` mirrors the grab handle's visibility, so the resize strip
    /// only exists when the handle is actually shown.
    public func zone(distanceFromTop: CGFloat, canResize: Bool) -> PressTracker.Zone {
        if distanceFromTop < 0 { return .none }
        if canResize && distanceFromTop <= resizeEdge { return .resize }
        if distanceFromTop <= headerHeight { return .move }
        return .none
    }

    /// As above, but yielding the controls the header carries — the update
    /// chip, the collapse button — back to SwiftUI.
    ///
    /// They sit inside the drag band, and a press the view layer is tracking is
    /// never forwarded on. So a button there never saw its click: the press was
    /// instead classified as a plain click on the header, which toggles. The
    /// update chip's whole purpose is to open the release page, and it was
    /// collapsing the drawer.
    ///
    /// The resize strip is resolved first, so a control overlapping the grab
    /// edge cannot swallow it.
    public func zone(distanceFromTop: CGFloat,
                     distanceFromLeft: CGFloat,
                     canResize: Bool,
                     controls: [CGRect]) -> PressTracker.Zone {
        let base = zone(distanceFromTop: distanceFromTop, canResize: canResize)
        guard base == .move else { return base }
        let point = CGPoint(x: distanceFromLeft, y: distanceFromTop)
        return controls.contains { $0.contains(point) } ? .none : base
    }
}
