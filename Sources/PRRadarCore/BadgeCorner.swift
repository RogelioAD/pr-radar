import CoreGraphics

/// One of the badge's four corners, as a resize handle.
///
/// The `outward` direction is expressed in **screen** orientation, where y
/// grows upward — not in the flipped view space the hit test works in. Two
/// coordinate systems meet in this feature and the signs are easy to get
/// backwards, so the drag arithmetic asks here rather than re-deriving them at
/// each call site.
public enum BadgeCorner: Sendable, Equatable, CaseIterable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    public var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    public var isTop: Bool { self == .topLeft || self == .topRight }

    /// Unit direction that makes the badge *bigger*, y up.
    public var outward: CGPoint {
        CGPoint(x: isLeft ? -1 : 1, y: isTop ? 1 : -1)
    }

    /// The corner held still while this one is dragged.
    public var opposite: BadgeCorner {
        switch self {
        case .topLeft: return .bottomRight
        case .topRight: return .bottomLeft
        case .bottomLeft: return .topRight
        case .bottomRight: return .topLeft
        }
    }
}
