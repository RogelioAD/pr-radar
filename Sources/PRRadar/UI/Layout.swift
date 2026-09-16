import Foundation
import PRRadarCore

enum Layout {
    /// Matches the user's Dock icon size, so the badge sits alongside the Dock
    /// as a peer rather than looking oversized. Read once at launch.
    static let dockTileSize: CGFloat = {
        let raw = UserDefaults(suiteName: "com.apple.dock")?
            .object(forKey: "tilesize") as? Double
        return CGFloat(min(max(raw ?? 48, 28), 80))
    }()

    /// The rounded-square tile the glyph sits in — a Dock-tile-sized peer.
    static var badgeTileSize: CGFloat { dockTileSize }
    /// Corner radius in Dock proportions (a squircle is ~22% of the tile).
    static var badgeCornerRadius: CGFloat { (dockTileSize * 0.24).rounded() }
    /// The glyph, deliberately smaller than the tile it sits in.
    static var badgeGlyphSize: CGFloat { (dockTileSize * 0.50).rounded() }
    /// Dock badges run just under half the tile.
    static var countBadgeSize: CGFloat { (dockTileSize * 0.46).rounded() }
    /// How far the count badge pokes out past the tile's corner. Less than its
    /// radius, so the badge's centre sits *inside* the corner and it overlaps
    /// the tile the way a Dock badge overlaps its app icon.
    static var countBadgeOverhang: CGFloat { (countBadgeSize * 0.34).rounded() }
    /// Panel footprint. One overhang's worth on the right, and one at *each*
    /// of top and bottom, because two same-sized badges now hang off the
    /// tile's corners — the review count above, the ready-to-merge count below.
    static var badgeWidth: CGFloat { badgeTileSize + countBadgeOverhang }
    static var badgeHeight: CGFloat { badgeTileSize + countBadgeOverhang * 2 }

    /// One width for both tabs. It is set by the My PRs row, which carries the
    /// most — approvals, checks, threads, blockers, stack position — and the
    /// Reviews tab simply uses the same, so switching tabs never resizes the
    /// drawer sideways.
    static let drawerWidth: CGFloat = 440
    static let tabStripHeight: CGFloat = 30
    static let headerHeight: CGFloat = 40
    static let filterBarHeight: CGFloat = 32
    static let footerHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 2
    static let listPadding: CGFloat = 12
    /// Height of the grab strip along the drawer's top edge.
    static let resizeEdge: CGFloat = 6
    /// Gap kept from the screen edges when placing the panel by default.
    static let screenInset: CGFloat = 24

    /// The drawer sizes itself to this many rows. Fewer shrink to fit; more
    /// scroll inside the same height until the user drags it taller.
    ///
    /// PRRADAR_VISIBLE_ROWS overrides it, so the "more rows than fit" path can
    /// be exercised without manufacturing extra pull requests.
    static let defaultVisibleRows: Int = {
        if let raw = ProcessInfo.processInfo.environment["PRRADAR_VISIBLE_ROWS"],
           let rows = Int(raw), rows > 0 {
            return rows
        }
        return 3
    }()
    static let maxDrawerHeight: CGFloat = 760
    /// Used only before rows report their real size.
    static let estimatedRowHeight: CGFloat = 80

    static var chromeHeight: CGFloat {
        // header + tab strip + filter bar + footer, plus four dividers.
        headerHeight + tabStripHeight + filterBarHeight + footerHeight + 4
    }

    static let sizing = DrawerSizing(
        rowSpacing: rowSpacing,
        listPadding: listPadding,
        chromeHeight: chromeHeight,
        defaultVisibleRows: defaultVisibleRows,
        maxHeight: maxDrawerHeight,
        estimatedRowHeight: estimatedRowHeight
    )

    static func drawerHeight(rowHeights: [CGFloat],
                             itemCount: Int,
                             userContentHeight: CGFloat?,
                             minimumContentHeight: CGFloat = 0) -> CGFloat {
        sizing.windowHeight(rowHeights: rowHeights,
                            itemCount: itemCount,
                            userContentHeight: userContentHeight,
                            minimumContentHeight: minimumContentHeight)
    }

    /// Height for the single-row empty/problem states.
    static func singleRowHeight() -> CGFloat {
        sizing.contentHeight(rowHeights: [], rows: 1)
    }
}
