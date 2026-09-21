import CoreGraphics

/// Lays items out left to right, wrapping to a new line rather than running
/// past the edge.
///
/// Here rather than in the view for the usual reason: it is arithmetic, and the
/// view layer already got the chip rows wrong once by leaning on `HStack`. A
/// `Chip` is `.fixedSize()`, so a stack of them reports whatever width it wants
/// and the row grows to suit — which pushed the stack marker off the end of a
/// crowded row and out of the clip.
public struct FlowRows: Sendable {
    public let spacing: CGFloat
    public let lineSpacing: CGFloat

    public init(spacing: CGFloat, lineSpacing: CGFloat) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    public struct Placement: Equatable, Sendable {
        /// Top-left of each item, in order, relative to the container.
        public let offsets: [CGPoint]
        public let size: CGSize
    }

    /// Wraps when the next item would not fit on the current line.
    ///
    /// An item wider than the whole line still gets placed, alone on its own
    /// line: dropping it would hide a chip, and a chip is there because
    /// something is true about the PR.
    public func place(_ sizes: [CGSize], within width: CGFloat) -> Placement {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var widest: CGFloat = 0

        for size in sizes {
            if x > 0, x + size.width > width {
                y += lineHeight + lineSpacing
                x = 0
                lineHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }

        guard !offsets.isEmpty else { return Placement(offsets: [], size: .zero) }
        // Never reports more than it was given, even when one item overflows:
        // the point of this type is that what contains it does not grow.
        return Placement(offsets: offsets,
                         size: CGSize(width: min(widest, width), height: y + lineHeight))
    }
}
