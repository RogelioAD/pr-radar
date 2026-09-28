import SwiftUI
import PRRadarCore

/// The shelf: every trophy at once, earned ones in colour.
///
/// A grid rather than a list, and deliberately without labels under the art.
/// Thirty captions is thirty lines of text competing with thirty drawings, and
/// the drawings are the point — the name lives in the tooltip, where it costs
/// nothing until it is asked for.
struct TrophyRoomView: View {
    @ObservedObject var state: AppState
    let onRowHeights: ([String: CGFloat]) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.trophyGridSpacing) {
                ForEach(Array(state.trophyRows.enumerated()), id: \.offset) { index, row in
                    shelf(row)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: RowHeightsKey.self,
                                    value: [state.rowKey(.trophies, TrophyGrid.rowID(index)):
                                                geometry.size.height])
                            }
                        )
                }
            }
            .padding(.horizontal, Layout.trophyGridInset)
            .padding(.vertical, Layout.listPadding / 2)
        }
        .onPreferenceChange(RowHeightsKey.self, perform: onRowHeights)
    }

    /// One row of the grid.
    ///
    /// The last row can be short, and is left-aligned rather than spread: a
    /// row of three spaced out to the width of a row of five reads as a
    /// different grid, not as the end of this one.
    private func shelf(_ row: [Trophy]) -> some View {
        HStack(spacing: Layout.trophyGridSpacing) {
            ForEach(row) { trophy in
                TrophyCell(trophy: trophy,
                           unlocked: state.trophyState.isUnlocked(trophy.id),
                           isNew: state.isNew(trophy.id))
            }
            if row.count < Layout.trophyColumns {
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One trophy on the shelf.
struct TrophyCell: View {
    let trophy: Trophy
    let unlocked: Bool
    /// Earned since the shelf was last looked at.
    var isNew = false

    var body: some View {
        SpriteCanvas(layout: .trophy(trophy.art(unlocked: unlocked)),
                     scale: Layout.trophyScale,
                     locked: !unlocked)
            // Bottom-right, where the same dot on the room's own button is
            // top-right. Thirty drawings is a lot to scan for the one that
            // changed, and the button that brought you here has already stopped
            // saying which — it goes quiet the moment the room opens.
            .overlay(alignment: .bottomTrailing) {
                if isNew {
                    Circle()
                        .fill(Health.good.tint)
                        .frame(width: Layout.noticeDot, height: Layout.noticeDot)
                        // A ring in the room's own material, so the dot reads
                        // as sitting on the trophy rather than painted into it.
                        .overlay(Circle().strokeBorder(.background, lineWidth: 1.5))
                        .offset(x: 2, y: 2)
                }
            }
            .help(trophy.tooltip(unlocked: unlocked))
            .accessibilityLabel(trophy.name(unlocked: unlocked))
            .accessibilityValue(unlocked ? "Unlocked" : "Locked")
            .accessibilityAddTraits(isNew ? [.isSelected] : [])
    }
}
