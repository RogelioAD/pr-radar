import CoreGraphics

/// Maps a point in the expanded drawer onto what a press there does.
///
/// Three answers, and only the top band has any of them: the grab handle
/// resizes, the rest of the header moves the window, and everything below
/// belongs to SwiftUI so rows, menus and the footer buttons stay clickable.
///
/// The horizontal coordinate matters, which it did not always. The resize
/// strip used to run the drawer's full width, so the top edge — the one place
/// a hand goes to move a window — changed the height instead and the drawer
/// read as immovable. The strip is the handle's own column now, and the rest
/// of that edge moves like the header below it.
public struct DrawerZones: Sendable {
    public let headerHeight: CGFloat
    public let resizeEdge: CGFloat
    /// How wide the grab strip is, centred on the drawer's top edge.
    ///
    /// Wider than the capsule it is drawn as, deliberately: the visible mark
    /// is 36pt and a 36pt target is missed, which is the same lesson
    /// `resizeEdge` already learned vertically. What it must not be is the
    /// full width — that is the bug this exists to fix.
    public let resizeHandle: CGFloat

    public init(headerHeight: CGFloat, resizeEdge: CGFloat, resizeHandle: CGFloat) {
        self.headerHeight = headerHeight
        self.resizeEdge = resizeEdge
        self.resizeHandle = resizeHandle
    }

    /// Converts a view-space y into a distance measured from the visual top,
    /// which is the only frame of reference the zone rules should care about.
    public static func distanceFromTop(pointY: CGFloat,
                                       viewHeight: CGFloat,
                                       isFlipped: Bool) -> CGFloat {
        isFlipped ? pointY : viewHeight - pointY
    }

    /// The columns the grab handle answers for, centred in a drawer this wide.
    ///
    /// Clamped to the drawer rather than allowed to overhang it: a panel
    /// narrower than the handle would otherwise report a strip starting at a
    /// negative column, and the whole edge would resize again.
    public func handleSpan(width: CGFloat) -> ClosedRange<CGFloat> {
        let span = min(resizeHandle, max(0, width))
        let inset = (width - span) / 2
        return inset...(inset + span)
    }

    /// What a press at this point does.
    ///
    /// `canResize` mirrors the grab handle's visibility, so the strip only
    /// exists when the handle is actually shown — with nothing to expand into
    /// the edge moves the window like the rest of the band.
    ///
    /// `controls` are the header's own — the update chip, the collapse button,
    /// the mascot — yielded back to SwiftUI. They sit inside the drag band, and
    /// a press the view layer is tracking is never forwarded on, so a button
    /// there never saw its click: the press was instead classified as a drag on
    /// the header. The update chip's whole purpose is to open the release page,
    /// and it was collapsing the drawer.
    ///
    /// The handle is resolved before the controls, so one overlapping the grab
    /// strip cannot swallow it.
    public func zone(distanceFromTop: CGFloat,
                     distanceFromLeft: CGFloat,
                     width: CGFloat,
                     canResize: Bool,
                     controls: [CGRect] = []) -> PressTracker.Zone {
        guard distanceFromTop >= 0, distanceFromTop <= headerHeight else { return .none }
        if canResize, distanceFromTop <= resizeEdge,
           handleSpan(width: width).contains(distanceFromLeft) {
            return .resize
        }
        let point = CGPoint(x: distanceFromLeft, y: distanceFromTop)
        return controls.contains { $0.contains(point) } ? .none : .move
    }
}
