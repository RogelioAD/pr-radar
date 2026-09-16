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
/// - Every height, dragged or capped, lands on a row boundary. A drawer that
///   ends halfway through a row looks broken, and hides the fact that there is
///   more below.
public struct DrawerSizing: Sendable {
    public let rowSpacing: CGFloat
    public let listPadding: CGFloat
    public let chromeHeight: CGFloat
    public let maxHeight: CGFloat
    public let estimatedRowHeight: CGFloat

    public init(rowSpacing: CGFloat,
                listPadding: CGFloat,
                chromeHeight: CGFloat,
                maxHeight: CGFloat,
                estimatedRowHeight: CGFloat) {
        self.rowSpacing = rowSpacing
        self.listPadding = listPadding
        self.chromeHeight = chromeHeight
        self.maxHeight = maxHeight
        self.estimatedRowHeight = estimatedRowHeight
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
        let count = max(itemCount, 1)
        return (1...count).map { contentHeight(rowHeights: rowHeights, rows: $0) }
    }

    /// Largest boundary that fits inside `limit`, or the smallest boundary when
    /// even one row will not fit — one clipped row beats an empty drawer.
    public func largestBoundary(within limit: CGFloat,
                                rowHeights: [CGFloat],
                                itemCount: Int) -> CGFloat {
        let boundaries = rowBoundaries(rowHeights: rowHeights, itemCount: itemCount)
        return boundaries.last { $0 <= limit } ?? boundaries[0]
    }

    /// Snaps to whichever boundary is closest, so a drag settles on a row edge.
    public func snap(_ requested: CGFloat,
                     rowHeights: [CGFloat],
                     itemCount: Int,
                     limit: CGFloat? = nil) -> CGFloat {
        let ceiling = limit ?? (maxHeight - chromeHeight)
        let boundaries = rowBoundaries(rowHeights: rowHeights, itemCount: itemCount)
            .filter { $0 <= ceiling }
        guard let first = boundaries.first else {
            // Not even one row fits; the cap is all there is.
            return rowBoundaries(rowHeights: rowHeights, itemCount: itemCount)[0]
        }
        return boundaries.min { abs($0 - requested) < abs($1 - requested) } ?? first
    }

    /// The row-list height the drawer should use.
    public func contentHeight(rowHeights: [CGFloat],
                              itemCount: Int,
                              userContentHeight: CGFloat?,
                              maxHeight overrideMax: CGFloat? = nil) -> CGFloat {
        let ceiling = (overrideMax ?? maxHeight) - chromeHeight
        // Default: everything, as far as the screen allows.
        let fitAll = largestBoundary(within: ceiling,
                                     rowHeights: rowHeights,
                                     itemCount: itemCount)
        guard let requested = userContentHeight else { return fitAll }
        return snap(requested, rowHeights: rowHeights,
                    itemCount: itemCount, limit: ceiling)
    }

    /// Total window height, chrome included.
    public func windowHeight(rowHeights: [CGFloat],
                             itemCount: Int,
                             userContentHeight: CGFloat?,
                             maxHeight overrideMax: CGFloat? = nil) -> CGFloat {
        chromeHeight + contentHeight(rowHeights: rowHeights,
                                     itemCount: itemCount,
                                     userContentHeight: userContentHeight,
                                     maxHeight: overrideMax)
    }
}
