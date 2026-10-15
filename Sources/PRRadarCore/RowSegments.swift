import CoreGraphics

/// Splits one measured row into the pieces the drawer may stop between.
///
/// A row with its threads open is one row to the layout and several rows to the
/// eye — the same thing a stack card is, and solved the same way: flatten it
/// into one entry per visible piece and let the existing boundary arithmetic do
/// the rest. Without this, a pull request with six comments showing is a single
/// 900-point stop, so the drag has nothing to land on between "collapsed" and
/// "all six".
///
/// **The sum is the whole trick.** `DrawerSizing` reads a positional array of
/// row heights and inserts `rowSpacing` between every pair, so a row split into
/// *n* pieces would otherwise gain *n − 1* spacings the real layout never drew
/// — the drawer would size itself taller than its own content, by a few points
/// per comment, and the bottom row would never quite reach the edge. Each piece
/// after the first therefore gives back one `spacing`, so the flattened run
/// sums to exactly what the single measurement did. `MyPRStack.stopHeights`
/// folds a card's chrome into its first member for the same reason.
public enum RowSegments {

    /// One entry per stop, summing (with `spacing` between them) to `height`.
    ///
    /// `cuts` are offsets from the row's top at which stopping makes sense —
    /// the bottom edge of each comment. Cuts at or outside the row are dropped
    /// rather than clamped: a measurement taken mid-animation can report a
    /// stale edge past the row's own bottom, and clamping one would add a
    /// zero-height stop that the drag can land on and appear stuck at.
    ///
    /// No cuts, or a row too short to divide, yields the row itself — which is
    /// what every collapsed row is.
    public static func split(height: CGFloat,
                             cuts: [CGFloat],
                             spacing: CGFloat) -> [CGFloat] {
        guard height > 0 else { return [] }

        let usable = cuts
            .filter { $0 > 0 && $0 < height }
            .sorted()
            .reduce(into: [CGFloat]()) { kept, cut in
                // A piece has to be worth stopping at. Two cuts a point apart
                // are one stop, and admitting both gives the drag two targets
                // it cannot tell apart.
                if kept.last.map({ cut - $0 >= minimumPiece }) ?? (cut >= minimumPiece) {
                    kept.append(cut)
                }
            }
        guard let last = usable.last, height - last >= minimumPiece else { return [height] }

        var pieces: [CGFloat] = []
        var previous: CGFloat = 0
        for cut in usable {
            pieces.append(piece(cut - previous, isFirst: pieces.isEmpty, spacing: spacing))
            previous = cut
        }
        pieces.append(piece(height - previous, isFirst: false, spacing: spacing))
        return pieces
    }

    /// Smallest piece worth offering as a stop. Below this the drag gains a
    /// target it cannot be aimed at.
    static let minimumPiece: CGFloat = 12

    /// Every piece but the first gives back the spacing the sizing will add in
    /// front of it, so the run still sums to the row's measured height.
    ///
    /// Floored at one point rather than allowed to go negative: a comment
    /// shorter than `rowSpacing` would otherwise subtract height from the row
    /// it belongs to, and a list that shrinks when you open something is worse
    /// than one that is a couple of points out.
    private static func piece(_ raw: CGFloat, isFirst: Bool, spacing: CGFloat) -> CGFloat {
        isFirst ? raw : max(1, raw - spacing)
    }
}
