import SwiftUI
import PRRadarCore

/// Chips laid out left to right, wrapping to a second line rather than pushing
/// the row wider than it was given.
///
/// `SwiftUI.Layout` spelled out because this file also sees the app's own
/// `Layout` enum, and the bare name resolves to that one.
struct ChipFlow: SwiftUI.Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    private var rows: FlowRows {
        FlowRows(spacing: spacing, lineSpacing: lineSpacing)
    }

    /// `.unspecified` so each chip reports its own ideal width — which is what
    /// `.fixedSize()` on a `Chip` is for, and what makes wrapping the right
    /// answer rather than squeezing.
    private func sizes(_ subviews: Subviews) -> [CGSize] {
        subviews.map { $0.sizeThatFits(.unspecified) }
    }

    func sizeThatFits(proposal: ProposedViewSize,
                      subviews: Subviews,
                      cache: inout Void) -> CGSize {
        rows.place(sizes(subviews), within: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect,
                       proposal: ProposedViewSize,
                       subviews: Subviews,
                       cache: inout Void) {
        let sizes = sizes(subviews)
        let placement = rows.place(sizes, within: bounds.width)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + placement.offsets[index].x,
                            y: bounds.minY + placement.offsets[index].y),
                proposal: ProposedViewSize(sizes[index]))
        }
    }
}
