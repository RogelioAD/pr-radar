import CoreGraphics

/// Fits a window rect onto the displays that exist *right now*.
///
/// The widget's position is stored as a rect in global screen coordinates, and
/// those coordinates are only meaningful while the display they were measured
/// against is attached. Unplug a monitor and the stored rect keeps pointing at
/// a region of the coordinate space nothing draws any more — the widget is not
/// gone, it is parked where no screen is. Everything that sets the panel's
/// frame runs through here so that cannot happen.
///
/// Pure arithmetic on rects rather than `NSScreen` so the cases that matter —
/// the screen vanishing, the rect straddling two of them — can be tested
/// without a second monitor to plug in.
public enum ScreenFit {

    /// The visible area a rect belongs to: the one it overlaps most.
    ///
    /// Overlap *area* rather than the first screen it touches, because a rect
    /// nudged a few points across a shared edge is still, to the eye, on the
    /// screen holding the rest of it — and which screen comes first in the
    /// list is an ordering nobody chose.
    ///
    /// A rect overlapping nothing at all falls back to the first frame, so
    /// callers should pass the main screen first. That is the unplugged case,
    /// and it is the one that has to land somewhere rather than nowhere.
    public static func host(of rect: CGRect, among visibleFrames: [CGRect]) -> CGRect? {
        guard let fallback = visibleFrames.first else { return nil }
        var best = fallback
        var bestArea: CGFloat = 0
        for frame in visibleFrames {
            let overlap = frame.intersection(rect)
            guard !overlap.isNull else { continue }
            let area = overlap.width * overlap.height
            if area > bestArea {
                bestArea = area
                best = frame
            }
        }
        return best
    }

    /// Clamps `rect` inside the visible area it belongs to.
    ///
    /// Height is capped — a drawer taller than the screen is worse than a
    /// scrolling one — but width is left alone: the drawer's width is a fixed
    /// part of its layout, and shrinking the frame without reflowing the
    /// content would clip it. Instead the origin is clamped in an order that
    /// keeps the rect's *leading* edge on screen even when it is too wide,
    /// which is the edge everything is read from.
    public static func fit(_ rect: CGRect, onto visibleFrames: [CGRect]) -> CGRect {
        guard let visible = host(of: rect, among: visibleFrames),
              visible.width > 0, visible.height > 0 else { return rect }
        var result = rect
        result.size.height = min(result.height, visible.height)
        result.origin.x = max(visible.minX, min(rect.minX, visible.maxX - result.width))
        result.origin.y = max(visible.minY, min(rect.minY, visible.maxY - result.height))
        return result
    }
}
