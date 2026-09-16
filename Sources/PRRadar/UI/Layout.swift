import AppKit
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

    /// Used only before rows report their real size.
    static let estimatedRowHeight: CGFloat = 80

    static var chromeHeight: CGFloat {
        // header + tab strip + filter bar + footer, plus four dividers.
        headerHeight + tabStripHeight + filterBarHeight + footerHeight + 4
    }

    /// Fallback ceiling, only used if no screen can be determined. The real
    /// limit is the screen height, passed in per call.
    static let fallbackMaxHeight: CGFloat = 900

    static let sizing = DrawerSizing(
        rowSpacing: rowSpacing,
        listPadding: listPadding,
        chromeHeight: chromeHeight,
        maxHeight: fallbackMaxHeight,
        estimatedRowHeight: estimatedRowHeight
    )

    static func drawerHeight(rowHeights: [CGFloat],
                             itemCount: Int,
                             userContentHeight: CGFloat?,
                             maxHeight: CGFloat,
                             snapping: Bool = true) -> CGFloat {
        sizing.windowHeight(rowHeights: rowHeights,
                            itemCount: itemCount,
                            userContentHeight: userContentHeight,
                            maxHeight: maxHeight,
                            snapping: snapping)
    }

    /// Height for the single-row empty/problem states.
    static func singleRowHeight() -> CGFloat {
        sizing.contentHeight(rowHeights: [], rows: 1)
    }

    /// The drawer may grow to the height of the screen it is on.
    static func maxHeight(on screen: NSScreen?) -> CGFloat {
        screen?.visibleFrame.height ?? fallbackMaxHeight
    }
}
