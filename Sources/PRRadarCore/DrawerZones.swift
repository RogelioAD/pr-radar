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
}
