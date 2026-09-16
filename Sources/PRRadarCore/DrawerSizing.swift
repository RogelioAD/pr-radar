import CoreGraphics

/// Pure height math for the drawer, kept out of the view layer so the rules
/// are testable.
///
/// The rules:
/// - Fewer rows than `defaultVisibleRows` shrink to fit exactly.
/// - At or above that, the drawer defaults to exactly that many rows and the
///   rest scroll.
/// - A height the user dragged to is honoured, but never below the default
///   and never beyond what it takes to show every row.
/// - An optional floor keeps one tab from rendering shorter than another, so
///   switching tabs never makes the drawer jump upward.
public struct DrawerSizing: Sendable {
    public let rowSpacing: CGFloat
    public let listPadding: CGFloat
    public let chromeHeight: CGFloat
    public let defaultVisibleRows: Int
    public let maxHeight: CGFloat
    public let estimatedRowHeight: CGFloat

    public init(rowSpacing: CGFloat,
                listPadding: CGFloat,
                chromeHeight: CGFloat,
                defaultVisibleRows: Int,
                maxHeight: CGFloat,
                estimatedRowHeight: CGFloat) {
        self.rowSpacing = rowSpacing
        self.listPadding = listPadding
        self.chromeHeight = chromeHeight
        self.defaultVisibleRows = defaultVisibleRows
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

    /// The row-list height the drawer should use, before chrome.
    ///
    /// `minimum` is applied last, after every other rule. It deliberately wins
    /// over the "no taller than all the rows" cap: a tab with one row may end
    /// up with empty space below it, which is the price of the drawer never
    /// shrinking when you switch tabs.
    public func contentHeight(rowHeights: [CGFloat],
                              itemCount: Int,
                              userContentHeight: CGFloat?,
                              minimum: CGFloat = 0) -> CGFloat {
        let visible = min(max(itemCount, 1), defaultVisibleRows)
        let floorHeight = contentHeight(rowHeights: rowHeights, rows: visible)

        // With everything already visible there is nothing to expand into, so
        // a stored user height is ignored rather than padding empty space.
        guard itemCount > defaultVisibleRows else {
            return max(floorHeight, minimum)
        }

        let fullHeight = contentHeight(rowHeights: rowHeights, rows: itemCount)
        guard let requested = userContentHeight else {
            return max(floorHeight, minimum)
        }
        return max(min(max(requested, floorHeight), fullHeight), minimum)
    }

    /// Total window height, chrome included.
    public func windowHeight(rowHeights: [CGFloat],
                             itemCount: Int,
                             userContentHeight: CGFloat?,
                             minimumContentHeight: CGFloat = 0) -> CGFloat {
        let content = contentHeight(rowHeights: rowHeights,
                                    itemCount: itemCount,
                                    userContentHeight: userContentHeight,
                                    minimum: minimumContentHeight)
        return min(chromeHeight + content, maxHeight)
    }
}
