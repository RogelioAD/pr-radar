import SwiftUI
import PRRadarCore

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
        .padding(.vertical, 2)
        .background(
            Capsule().fill(filled ? AnyShapeStyle(health.tint)
                                  : AnyShapeStyle(health.tint.opacity(0.15)))
        )
        .fixedSize()
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
            .padding(.vertical, 3)
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
