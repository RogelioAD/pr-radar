import CoreGraphics

/// What a corner drag does to the badge's size, and where the badge has to sit
/// for the corner opposite the one being dragged to stay still.
///
/// The badge is always a square: one tile size drives the tile, the glyph, the
/// counter chips and the mascot's sprite scale alike, so there is a single
/// number to clamp and a single number to drag.
public struct BadgeSizing: Sendable {
    /// The smallest and largest real Dock tile sizes. Below the floor the
    /// counter's 3x5 digits stop being legible; above the ceiling the badge
    /// stops reading as a Dock peer and starts reading as a window.
    public let minimum: CGFloat
    public let maximum: CGFloat

    public init(minimum: CGFloat, maximum: CGFloat) {
        self.minimum = minimum
        self.maximum = maximum
    }

    public func clamp(_ tile: CGFloat) -> CGFloat {
        min(max(tile, minimum), maximum)
    }

    /// The smallest and largest tile a drag can actually settle on.
    ///
    /// Not the same as `minimum` and `maximum` whenever a character is drawn.
    /// Pixel art only draws at whole device pixels, so a committed size is the
    /// sprite's width times a *snapped* scale — on a 1x screen an 18-cell
    /// character settles on 36, 54, 72 … 126, inside bounds of 28 and 128. A
    /// badge dragged hard against either stop therefore never reports the
    /// number the bounds name, and anything comparing against those bounds is
    /// asking for a size that cannot occur.
    ///
    /// `spriteWidth` is nil when no character is drawn. The plain tile is not
    /// snapped to anything, so it reaches both bounds exactly.
    public func reachableRange(spriteWidth: Int?,
                               backingScale: CGFloat,
                               minimumScale: CGFloat) -> (minimum: CGFloat, maximum: CGFloat) {
        guard let spriteWidth, spriteWidth > 0 else { return (minimum, maximum) }
        func settled(_ tile: CGFloat) -> CGFloat {
            let scale = SpriteScale.snapped(targetPoints: tile,
                                            spriteWidth: spriteWidth,
                                            backingScale: backingScale,
                                            minimum: minimumScale)
            return clamp(CGFloat(spriteWidth) * scale)
        }
        return (settled(minimum), settled(maximum))
    }

    /// Tile size the pointer is asking for, from a delta measured against the
    /// press rather than the previous frame — the same rule the window drag
    /// uses, and what keeps the gesture stable while the badge moves under the
    /// hand.
    ///
    /// The growth is the **average** of the two axes along the corner's
    /// outward direction, not the projection onto the unit diagonal. It looks
    /// like a missing `sqrt(2)` and is not: averaging makes a diagonal drag
    /// move the corner exactly as far as the hand, where the true projection
    /// runs it out about 1.4x ahead of the pointer.
    public func tileSize(from initial: CGFloat,
                         corner: BadgeCorner,
                         delta: CGPoint) -> CGFloat {
        let direction = corner.outward
        let growth = (delta.x * direction.x + delta.y * direction.y) / 2
        return clamp(initial + growth)
    }

    /// Origin, in screen coordinates, that holds the dragged corner's opposite
    /// still while the square changes size.
    ///
    /// Everything else about the badge anchors bottom-right, because that is
    /// the corner the drawer unfolds from. A drag is the one case where that is
    /// wrong: grabbing the top-left and watching the bottom-right move is the
    /// opposite of what a resize handle promises.
    public static func origin(dragging corner: BadgeCorner,
                              in frame: CGRect,
                              newSize: CGSize) -> CGPoint {
        CGPoint(
            x: corner.isLeft ? frame.maxX - newSize.width : frame.minX,
            y: corner.isTop ? frame.minY : frame.maxY - newSize.height
        )
    }
}
