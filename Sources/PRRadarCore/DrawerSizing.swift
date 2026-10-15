import CoreGraphics

/// Pure height math for the drawer, kept out of the view layer so the rules
/// are testable.
///
/// The rules:
/// - By default the drawer shows **every** row, so nothing is hidden until it
///   has to be.
/// - It never exceeds `maxHeight` (the screen). Past that the list scrolls.
/// - A height the user dragged to is honoured between one row and everything,
///   so the handle is always useful — dragging *shorter* is the common case
///   once the default is "fit everything".
/// - A settled height lands on a row boundary. A drawer that ends halfway
///   through a row looks broken, and hides the fact that there is more below.
///   The one exception is a row too tall to fit the screen at all, where no row
///   boundary is reachable and the screen's cap becomes a stop of its own —
///   see `stops(rowHeights:itemCount:limit:)`.
/// - While a drag is *in progress* it is clamped but **not** snapped, so the
///   edge tracks the pointer smoothly. Snapping every frame makes the drag
///   lurch from row to row instead of following the hand.
public struct DrawerSizing: Sendable {
    public let rowSpacing: CGFloat
    public let listPadding: CGFloat
    public let chromeHeight: CGFloat
    public let maxHeight: CGFloat
    public let estimatedRowHeight: CGFloat
    /// What a list with nothing in it occupies.
    ///
    /// Its own number because an empty list is not a short list: where a row
    /// would be there is a mascot, a title and a line of explanation, and that
    /// comes to more than any one row does. Sizing the panel to one row instead
    /// left the character and its caption hanging over both edges — and the
    /// worse half of that bug is that the view could not fix it alone, because
    /// the panel had already been told how tall to be.
    public let emptyHeight: CGFloat

    public init(rowSpacing: CGFloat,
                listPadding: CGFloat,
                chromeHeight: CGFloat,
                maxHeight: CGFloat,
                estimatedRowHeight: CGFloat,
                emptyHeight: CGFloat? = nil) {
        self.rowSpacing = rowSpacing
        self.listPadding = listPadding
        self.chromeHeight = chromeHeight
        self.maxHeight = maxHeight
        self.estimatedRowHeight = estimatedRowHeight
        // Defaulted so every existing construction site — the tests included —
        // keeps the behaviour it was written against.
        self.emptyHeight = emptyHeight ?? (estimatedRowHeight + listPadding)
    }

    /// Height needed to show the first `rows` rows in full. Rows that have not
    /// reported a measurement yet fall back to the estimate.
    public func contentHeight(rowHeights: [CGFloat], rows: Int) -> CGFloat {
        let rows = max(rows, 0)
        guard rows > 0 else { return 0 }
        var total: CGFloat = 0
        for index in 0..<rows {
            total += index < rowHeights.count ? rowHeights[index] : estimatedRowHeight
        }
        return total + rowSpacing * CGFloat(rows - 1) + listPadding
    }

    /// The content height for each possible number of visible rows, from one
    /// row up to all of them. These are the only heights the drawer may take,
    /// which is what stops a row being clipped in half.
    public func rowBoundaries(rowHeights: [CGFloat], itemCount: Int) -> [CGFloat] {
        // Nothing to show is its own stop, not the first row's. Treating it as
        // one row is what made the empty state overflow: the drawer was sized
        // for a row and handed a mascot.
        guard itemCount > 0 else { return [emptyHeight] }
        return (1...itemCount).map { contentHeight(rowHeights: rowHeights, rows: $0) }
    }

    /// Each row's height, with the estimate standing in for rows that have not
    /// reported one yet.
    public func heights(rowHeights: [CGFloat], itemCount: Int) -> [CGFloat] {
        guard itemCount > 0 else { return [] }
        return (0..<itemCount).map {
            $0 < rowHeights.count ? rowHeights[$0] : estimatedRowHeight
        }
    }

    /// The heights the drawer may actually settle at, given a ceiling.
    ///
    /// The row boundaries that fit — **plus the ceiling itself, but only when
    /// some single row is too tall to be shown inside it at all.**
    ///
    /// That qualification is the whole of this method. Snapping to row edges is
    /// the behaviour to keep: a drawer ending halfway through a row looks
    /// broken, and giving up a few points of screen to land on an edge is the
    /// trade that buys it. What is *not* acceptable is giving up most of the
    /// screen.
    ///
    /// The failure this fixes: a pull request with six comments open makes one
    /// row around 900 points tall. With rows of 80, 900 and 80 under a
    /// 700-point ceiling the boundaries are 86, 990 and 1074, and only the
    /// first fits. The drawer defaulted to 86 — one row — and a drag out to 690
    /// snapped all the way back to it on release. Six comments were reachable
    /// only by scrolling a drawer one row high.
    ///
    /// The test is whether a row could *ever* be landed on, not whether it
    /// happens to fit right now. A row taller than the entire ceiling can never
    /// be shown whole however far the drawer opens, so no boundary past it is
    /// reachable and scrolling is already the only way to read it. Admitting
    /// the ceiling there lets the drawer open as far as the screen allows,
    /// which is what the cap was always for.
    ///
    /// Where every row *can* fit, this is the boundary list unchanged — so a
    /// list of ordinary rows still lands on edges exactly as before, including
    /// when the ceiling falls between two of them.
    public func stops(rowHeights: [CGFloat],
                      itemCount: Int,
                      limit: CGFloat) -> [CGFloat] {
        let boundaries = rowBoundaries(rowHeights: rowHeights, itemCount: itemCount)
        let fitting = boundaries.filter { $0 <= limit }
        // Not even the first row fits. One clipped row beats a sliver of
        // drawer, and the window is capped to the screen downstream anyway.
        guard !fitting.isEmpty else { return [boundaries[0]] }
        // Showing a row on its own still costs the list's padding, so that is
        // what "could this row ever be landed on" has to measure against.
        let tallest = heights(rowHeights: rowHeights, itemCount: itemCount).max() ?? 0
        guard tallest + listPadding > limit else { return fitting }
        return fitting + [limit]
    }

    /// Largest height that fits inside `limit`, which is the default: show
    /// everything the screen can hold.
    public func largestBoundary(within limit: CGFloat,
                                rowHeights: [CGFloat],
                                itemCount: Int) -> CGFloat {
        stops(rowHeights: rowHeights, itemCount: itemCount, limit: limit).last
            ?? rowBoundaries(rowHeights: rowHeights, itemCount: itemCount)[0]
    }

    /// Snaps to whichever stop is closest, so a drag settles on a row edge —
    /// or, where no row edge is reachable, on the screen's cap.
    public func snap(_ requested: CGFloat,
                     rowHeights: [CGFloat],
                     itemCount: Int,
                     limit: CGFloat? = nil) -> CGFloat {
        let ceiling = limit ?? (maxHeight - chromeHeight)
        let candidates = stops(rowHeights: rowHeights, itemCount: itemCount,
                               limit: ceiling)
        guard let first = candidates.first else {
            // A ceiling of zero or less, which nothing on screen can honour.
            return rowBoundaries(rowHeights: rowHeights, itemCount: itemCount)[0]
        }
        return candidates.min { abs($0 - requested) < abs($1 - requested) } ?? first
    }

    /// Clamps a height to between one row and the whole list, without snapping.
    /// Used while dragging, where the edge should follow the pointer.
    ///
    /// Deliberately *not* routed through `stops`. Mid-drag the edge tracks the
    /// hand, so every height in the range is legal — the stops only decide
    /// where it settles on release. Clamping to them made the edge stick at the
    /// last whole row and fight the pointer for the rest of the screen.
    public func clamp(_ requested: CGFloat,
                      rowHeights: [CGFloat],
                      itemCount: Int,
                      limit: CGFloat? = nil) -> CGFloat {
        let ceiling = limit ?? (maxHeight - chromeHeight)
        let boundaries = rowBoundaries(rowHeights: rowHeights, itemCount: itemCount)
        let lowest = boundaries[0]
        // Never below one row; never past the list or the screen, whichever
        // comes first. If one row already overflows the screen, that wins.
        let highest = max(lowest, min(boundaries[boundaries.count - 1], ceiling))
        return min(max(requested, lowest), highest)
    }

    /// The row-list height the drawer should use.
    ///
    /// `snapping` is false only mid-drag; see the note on smoothness above.
    public func contentHeight(rowHeights: [CGFloat],
                              itemCount: Int,
                              userContentHeight: CGFloat?,
                              maxHeight overrideMax: CGFloat? = nil,
                              snapping: Bool = true) -> CGFloat {
        let ceiling = (overrideMax ?? maxHeight) - chromeHeight
        // Default: everything, as far as the screen allows.
        let fitAll = largestBoundary(within: ceiling,
                                     rowHeights: rowHeights,
                                     itemCount: itemCount)
        guard let requested = userContentHeight else { return fitAll }
        guard snapping else {
            return clamp(requested, rowHeights: rowHeights,
                         itemCount: itemCount, limit: ceiling)
        }
        return snap(requested, rowHeights: rowHeights,
                    itemCount: itemCount, limit: ceiling)
    }

    /// Total window height, chrome included.
    public func windowHeight(rowHeights: [CGFloat],
                             itemCount: Int,
                             userContentHeight: CGFloat?,
                             maxHeight overrideMax: CGFloat? = nil,
                             snapping: Bool = true) -> CGFloat {
        chromeHeight + contentHeight(rowHeights: rowHeights,
                                     itemCount: itemCount,
                                     userContentHeight: userContentHeight,
                                     maxHeight: overrideMax,
                                     snapping: snapping)
    }
}
