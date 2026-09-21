import Foundation

/// The shelf's arithmetic: how the roster is laid out, and what the drawer
/// measures when it is showing one.
///
/// Here rather than in the view for the same reason `MyPRGrouping.stopHeights`
/// is: the drawer settles on row boundaries, so *what counts as a row* is a
/// rule the layout depends on, and a rule the layout depends on is worth being
/// able to test without a window.
public enum TrophyGrid {

    /// Five across.
    ///
    /// Set by the art and the drawer between them, not chosen: a trophy is 32
    /// cells drawn at 2x, so five of them and their gaps come to 368pt inside
    /// a 440pt drawer. Six would need either a narrower drawer or a smaller
    /// scale, and the scale has to stay whole.
    public static let columns = 5

    /// The roster in rows.
    ///
    /// A row is what the drawer snaps its height to, so a short final row is a
    /// legal stop like any other — the grid does not pad itself out to keep
    /// the arithmetic tidy. It happens that the roster divides exactly, and a
    /// test says so, but nothing here depends on that staying true.
    public static func rows(_ trophies: [Trophy] = Trophy.all,
                            columns: Int = columns) -> [[Trophy]] {
        precondition(columns > 0, "a grid needs at least one column")
        return stride(from: 0, to: trophies.count, by: columns).map { start in
            Array(trophies[start..<min(start + columns, trophies.count)])
        }
    }

    /// Identifies a row for the row-height machinery.
    ///
    /// The index, not the contents: the roster is fixed at build time, so row
    /// three is row three for the life of the app — and keying on contents
    /// would invent a new row every time a trophy was earned, throwing away
    /// the measurement for the row that had just changed.
    public static func rowID(_ index: Int) -> String { "row\(index)" }

    /// How many rows the drawer is snapping to right now.
    public static func rowCount(_ trophies: [Trophy] = Trophy.all,
                                columns: Int = columns) -> Int {
        rows(trophies, columns: columns).count
    }
}

extension TrophyGrid {

    /// What the room's footer says.
    ///
    /// The hidden count is reported as *found*, never as outstanding: saying
    /// "3 of 7 hidden" would give away how many there are to look for, which
    /// is most of what makes them hidden. Once they are all found it says so,
    /// because at that point there is nothing left to give away.
    public static func progress(unlocked: Set<TrophyID>) -> String {
        let total = Trophy.all.count
        let earned = Trophy.all.filter { unlocked.contains($0.id) }
        let hiddenFound = earned.filter(\.isHidden).count
        let hiddenTotal = Trophy.hidden.count

        var text = "\(earned.count) / \(total)"
        if hiddenFound == hiddenTotal {
            text += " · every hidden one found"
        } else if hiddenFound > 0 {
            text += " · \(hiddenFound) hidden found"
        }
        return text
    }
}
