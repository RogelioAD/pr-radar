import CoreGraphics

/// Maps a point in the collapsed badge onto the corner it would resize from,
/// or nil for the middle, which stays move-and-click.
///
/// Measured against the badge's *art*, not its panel — see `corner(at:...)`.
///
/// Separate from `DrawerZones` because the two answer different questions: the
/// drawer has one horizontal grab strip along its top, the badge has four
/// corner grips and no edges. What they share is the coordinate trap —
/// `NSHostingView.isFlipped` is `true`, so y runs top-down — and this reuses
/// `DrawerZones.distanceFromTop` rather than keeping a second copy of the
/// conversion that has already been got wrong once.
public struct BadgeZones: Sendable {
    /// Desired grip size along each edge. The effective grip is smaller on a
    /// small badge; see `grip(for:)`.
    public let grip: CGFloat

    public init(grip: CGFloat) {
        self.grip = grip
    }

    /// The badge can be dragged down to 28pt, where four 12pt grips would meet
    /// in the middle and leave nothing to move or click. Capping each grip at a
    /// third of the art keeps the middle third always move-and-click, whatever
    /// the size.
    public func grip(for extent: CGFloat) -> CGFloat {
        min(grip, extent / 3)
    }

    /// `point` is in view coordinates; `isFlipped` says which way its y runs.
    /// `art` is the rect the badge is actually *drawn* in, measured from the
    /// view's visual top-left, and `viewHeight` is the whole view's.
    ///
    /// The distinction is the whole point. The panel is bigger than the art it
    /// carries: a mascot reserves a mark gutter it may not be using and bob
    /// room under its feet, and how much of its 16x16 cell the character
    /// actually fills differs from one character to the next. Anchoring the
    /// grips to the panel put them out in transparent space, a different
    /// distance from the visible badge for every mascot — which reads as the
    /// resize cursor appearing in a different place each time you switch.
    ///
    /// Corners only, deliberately. An edge grip would be the larger target,
    /// but the badge resizes as a square — one edge cannot say which way, and
    /// a grip that resizes both axes while pointing at one reads as broken.
    public func corner(at point: CGPoint,
                       art: CGRect,
                       viewHeight: CGFloat,
                       isFlipped: Bool) -> BadgeCorner? {
        guard art.width > 0, art.height > 0 else { return nil }
        let fromTop = DrawerZones.distanceFromTop(pointY: point.y,
                                                  viewHeight: viewHeight,
                                                  isFlipped: isFlipped)
        guard point.x >= art.minX, point.x <= art.maxX,
              fromTop >= art.minY, fromTop <= art.maxY else { return nil }

        let gx = grip(for: art.width)
        let gy = grip(for: art.height)

        let left = point.x <= art.minX + gx
        let right = point.x >= art.maxX - gx
        let top = fromTop <= art.minY + gy
        let bottom = fromTop >= art.maxY - gy

        switch (top, bottom, left, right) {
        case (true, _, true, _): return .topLeft
        case (true, _, _, true): return .topRight
        case (_, true, true, _): return .bottomLeft
        case (_, true, _, true): return .bottomRight
        default: return nil
        }
    }
}
