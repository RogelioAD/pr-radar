import Foundation

/// The pancake stack a stacked PR wears, and the plate its group sits on.
///
/// Built procedurally rather than as a literal, the way `Counter.chip` is: the
/// height is the whole point — one pancake per PR below this one — so the art
/// has to be a function of a number, not sixteen fixed strings.
public enum Pancakes {

    /// Cells across. Odd, so the stack has a true centre column to taper
    /// towards and the plate can overhang it evenly on both sides.
    public static let width = 9

    /// Rows one pancake adds: an edge and a body. Two is the smallest that
    /// still reads as a *stack* rather than a barcode — at one row per pancake
    /// the outlines touch and five pancakes are a grey block.
    public static let pancakeRows = 2

    /// The syrup poured over the top: its own little narrow disc, outlined like
    /// the pancakes under it.
    ///
    /// A garnish, deliberately *not* a layer. A stack of one is one whole
    /// pancake with syrup on it; counting the syrup would leave the base of
    /// every stack drawn as the one member that is not a pancake.
    public static let syrupRows = 2

    /// The plate: a rim and the foot under it.
    public static let plateRows = 2

    /// Beyond this the marker is taller than the row carrying it, and the
    /// column of them stops lining up. Deeper stacks draw this many and say the
    /// real number in the tooltip — the same bargain `Counter` makes at `99+`.
    public static let maxDrawn = 6

    /// A stack of `count` pancakes on a plate.
    ///
    /// Bottom-up, because that is how a stack is built and how it is read: the
    /// plate is the last rows, and every extra pancake is added on top, so two
    /// markers of different depth share the same baseline and the difference
    /// shows as height rather than as a shift.
    public static func stack(of count: Int) -> Sprite {
        let drawn = max(1, min(count, maxDrawn))
        // Narrower than the pancakes under it, which gives the silhouette a
        // shoulder — uniform bands draw a rectangle of stripes and stop reading
        // as a stack of anything.
        var rows: [String] = ["...kkk...", "..ksssk.."]
        for _ in 0..<drawn {
            rows.append("..kkkkk..")
            rows.append(".kbbbbbk.")
        }
        // Closes the bottom pancake. Without it the lowest body sits directly on
        // the plate rim and the two merge into one thick line.
        rows.append("..kkkkk..")
        // The rim runs the full width and the foot is inset one cell at each
        // end, which is what gives the flat ellipse a lip rather than a border.
        rows.append("k" + String(repeating: "w", count: width - 2) + "k")
        rows.append("." + String(repeating: "k", count: width - 2) + ".")
        return Sprite(rows)
    }
}

extension SpriteLayout {
    /// One pancake stack, ready for `SpriteCanvas`.
    ///
    /// A layout rather than a bare `Sprite` because `SpriteCanvas` draws layouts
    /// and `Layer`'s init is internal to this module — the same reason `perch`
    /// and `widget` live here.
    public static func pancakeStack(of count: Int) -> SpriteLayout {
        single(Pancakes.stack(of: count))
    }

    /// A composition of exactly one sprite at the origin, sized to it.
    static func single(_ sprite: Sprite, accent: Health = .neutral) -> SpriteLayout {
        SpriteLayout(layers: [Layer(sprite: sprite, origin: Point(0, 0), accent: accent)],
                     width: sprite.width,
                     height: sprite.height)
    }
}
