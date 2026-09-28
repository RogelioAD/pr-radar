import SwiftUI
import PRRadarCore

/// The single height every pill on a row is drawn at.
///
/// Shared rather than arrived at. A chip and a button sit side by side in one
/// `ChipFlow` line, and `ChipFlow` places each subview at its own ideal size —
/// so the two points by which their vertical paddings happened to differ read
/// as a misalignment rather than as a style, and "review failed" sat visibly
/// shorter than the Retry button beside it.
///
/// A fixed height rather than matched padding, because matched padding is only
/// equal by coincidence: the moment one of them changes a font, they drift
/// apart again with nothing to say they should not have.
enum ChipMetrics {
    /// Sized to the taller of the two it replaces, so buttons keep the hit area
    /// they had and the chips grow into it.
    static let height: CGFloat = 18
}

/// One chip style for every signal on a row, so approvals, checks, threads and
/// blockers all read as members of the same system.
struct Chip: View {
    let text: String
    var symbol: String?
    var health: Health = .neutral
    /// Filled chips carry a verdict; outlined ones carry a count.
    var filled = false

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 8.5, weight: .bold))
            }
            Text(text).font(.system(size: 10, weight: filled ? .semibold : .medium))
        }
        .foregroundStyle(filled ? .white : health.tint)
        .padding(.horizontal, 5)
        .frame(height: ChipMetrics.height)
        .background(
            Capsule().fill(filled ? AnyShapeStyle(health.tint)
                                  : AnyShapeStyle(health.tint.opacity(0.15)))
        )
        // Width only: the ideal width is what `ChipFlow` wraps on, and the
        // height is now the frame's business rather than the content's.
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// A compact action button sized for a row.
struct RowButton: View {
    let title: String
    var symbol: String?
    var health: Health = .running
    var enabled = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 8.5, weight: .bold))
                }
                Text(title).font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(enabled ? health.tint : Color.secondary)
            .padding(.horizontal, 7)
            .frame(height: ChipMetrics.height)
            .background(
                Capsule().fill(health.tint.opacity(enabled ? (hovering ? 0.28 : 0.16) : 0.07))
            )
            .overlay(Capsule().strokeBorder(health.tint.opacity(enabled ? 0.45 : 0.15),
                                            lineWidth: 0.8))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}
