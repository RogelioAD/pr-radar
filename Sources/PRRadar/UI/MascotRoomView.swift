import SwiftUI
import PRRadarCore

/// The cast, on shelves, to be picked from.
///
/// A room rather than a longer pop-up menu. Twelve names in a list is a list
/// you read; twelve faces in a grid is a set you recognise — and recognising
/// them is the entire transaction. The Settings picker still exists for
/// anyone who already knows which one they want.
///
/// Four to a row, one shelf per cohort, oldest first and yours last.
struct MascotRoomView: View {
    @ObservedObject var state: AppState
    let onRowHeights: ([String: CGFloat]) -> Void
    let onPick: (MascotID?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Layout.mascotGridSpacing) {
                ForEach(MascotGrid.shelves) { shelf in
                    section(shelf)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: RowHeightsKey.self,
                                    value: [state.rowKey(.mascots,
                                                         MascotGrid.shelfID(shelf.cohort)):
                                                geometry.size.height])
                            }
                        )
                }
                offRow
            }
            .padding(.horizontal, Layout.settingsInset)
            .padding(.vertical, Layout.listPadding / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onPreferenceChange(RowHeightsKey.self, perform: onRowHeights)
    }

    // MARK: - A shelf

    private func section(_ shelf: MascotGrid.Shelf) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // The custom shelf borrows its title from whoever is signed in.
            // `MascotCohort` has no business knowing that, so it returns nil
            // and the room fills it in.
            Text((shelf.cohort.title ?? state.customCohortTitle).uppercased())
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            ForEach(Array(shelf.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: Layout.mascotGridSpacing) {
                    ForEach(row) { mascot in
                        MascotCell(mascot: mascot,
                                   chosen: state.mascot == mascot.id,
                                   scale: scale,
                                   onPick: { onPick(mascot.id) })
                    }
                    // Left-aligned rather than spread: a short last row
                    // spaced out to the full width reads as a different grid.
                    if row.count < MascotGrid.columns { Spacer(minLength: 0) }
                }
            }
        }
    }

    private var scale: CGFloat {
        Layout.mascotRoomScale(backingScale: state.backingScale)
    }

    /// Turning the character off belongs here too, or the room is a picker
    /// you cannot pick "none" from and the context menu stays the only way.
    private var offRow: some View {
        Button { onPick(nil) } label: {
            HStack(spacing: 6) {
                Image(systemName: state.mascot == nil ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(state.mascot == nil ? Color.accentColor : .secondary)
                Text("No mascot — use the plain tile")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .modifier(Pressable())
        .accessibilityLabel("No mascot")
        .accessibilityAddTraits(state.mascot == nil ? [.isSelected] : [])
    }
}

/// One character in the room: the art, its name, and whether it is the one on.
private struct MascotCell: View {
    let mascot: Mascot
    let chosen: Bool
    let scale: CGFloat
    let onPick: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: onPick) {
            VStack(spacing: 3) {
                // Whole, not cropped to the head: a room is the one surface
                // with the space for it, and half a character is a poor way
                // to be asked to choose between twelve.
                //
                // Framed to the character's *own* columns rather than the
                // perch's. A perch reserves a mood-mark gutter on its right
                // — 18 of its 66 cells — and `Mood.idle` draws no mark, so
                // that is dead space the layout was still counting. Centring
                // a name under it put every label a third of a gutter left
                // of the character it belongs to.
                MascotView(mascot: mascot,
                           style: Mood.idle.style,
                           scale: scale,
                           tempo: .still)
                    .frame(width: CGFloat(mascot.sprite.width) * scale,
                           alignment: .leading)
                    .clipped()
                Text(mascot.name)
                    .font(.system(size: 9.5, weight: chosen ? .semibold : .regular))
                    .foregroundStyle(chosen ? Color.accentColor : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(chosen ? Color.accentColor.opacity(0.14)
                                 : (hovering ? Color.primary.opacity(0.06) : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(chosen ? Color.accentColor.opacity(0.55) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // The blurb, which is the one place it is still read: the header
        // tooltip only ever had room for a name.
        .help("\(mascot.name) — \(mascot.blurb) Tell: \(mascot.tellName).")
        .accessibilityLabel(mascot.name)
        .accessibilityHint(mascot.blurb)
        .accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
}
