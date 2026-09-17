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
    /// Panel footprint with the mascot turned off: one overhang's worth on the
    /// right, and one at *each* of top and bottom, because two same-sized
    /// badges hang off the tile's corners — the review count above, the
    /// ready-to-merge count below.
    static var tileBadgeWidth: CGFloat { badgeTileSize + countBadgeOverhang }
    static var tileBadgeHeight: CGFloat { badgeTileSize + countBadgeOverhang * 2 }

    /// One width for both tabs. It is set by the My PRs row, which carries the
    /// most — approvals, checks, threads, blockers, stack position — and the
    /// Reviews tab simply uses the same, so switching tabs never resizes the
    /// drawer sideways.
    static let drawerWidth: CGFloat = 440
    static let tabStripHeight: CGFloat = 30
    /// Sized for the mascot lockup: 12pt resize strip plus a 36pt row, which is
    /// exactly what a 2x character with its bob room needs. Was 40 when the
    /// header carried only a 12pt SF Symbol.
    ///
    /// Nothing else has to change for this: `chromeHeight` is derived from it
    /// and `DrawerSizing` reads `chromeHeight`, so the drawer re-measures on
    /// its own.
    static let headerHeight: CGFloat = 48
    static let filterBarHeight: CGFloat = 32
    static let footerHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 2
    static let listPadding: CGFloat = 12
    /// Height of the grab strip along the drawer's top edge. Generous on
    /// purpose: at 6pt the pointer missed it more often than it hit it.
    static let resizeEdge: CGFloat = 12
    /// Gap kept from the screen edges when placing the panel by default.
    static let screenInset: CGFloat = 24

    // MARK: - Mascot

    /// The header lockup: a full 16-row bust at 2x, mark gutter included.
    static let headerMascotScale: CGFloat = 2
    /// The empty states already reserve a whole row's height for a 20pt SF
    /// Symbol, so this costs no layout at all.
    static let emptyStateMascotScale: CGFloat = 3

    /// The character plus its halo is 18 cells wide, and that is what should
    /// match the Dock tile — the counters hang off it rather than shrinking it.
    private static let badgeCharacterCells = 18

    /// Never below 2x, whatever the Dock is doing. Not because the character
    /// breaks, but because the counter's 3x5 digits stop being a number: at
    /// 1.5x a digit is seven and a half points tall.
    private static let badgeMinimumScale: CGFloat = 2

    static func badgeScale(backingScale: CGFloat) -> CGFloat {
        SpriteScale.snapped(targetPoints: dockTileSize,
                            spriteWidth: badgeCharacterCells,
                            backingScale: backingScale,
                            minimum: badgeMinimumScale)
    }

    /// Padding `SpriteCanvas` adds around a haloed, shadowed composition:
    /// one cell of halo on the leading edge, one of halo plus one of shadow on
    /// the trailing one.
    private static let badgePadCells = 3

    static func badgeSize(for layout: SpriteLayout, scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(layout.width + badgePadCells) * scale,
               height: CGFloat(layout.height + badgePadCells) * scale)
    }

    /// Used only before rows report their real size — which is exactly the
    /// first open on a fresh install, when nothing has been measured yet.
    ///
    /// Per tab, because a My PRs row carries far more than a review row does:
    /// approvals, checks, blockers, stack position. Estimating both at the
    /// review row's height opened that tab well short of a row boundary, and
    /// it only squared up once the rows reported and the layout ran again.
    static func estimatedRowHeight(for tab: DrawerTab) -> CGFloat {
        switch tab {
        case .reviews: return 80
        case .mine: return 130
        }
    }

    static let estimatedRowHeight: CGFloat = estimatedRowHeight(for: .reviews)

    /// The account strip's own row. Shorter than the tab strip: it carries no
    /// icons, and it is a scope selector rather than the drawer's main control.
    static let accountStripHeight: CGFloat = 26

    /// Chrome above and below the row list.
    ///
    /// Takes whether the account strip is showing rather than assuming, because
    /// the strip appears only on a machine with more than one account. Assuming
    /// it away would clip the last row by exactly its height on the machines
    /// that have it, and assuming it present would leave a gap on the ones that
    /// do not.
    static func chromeHeight(accountStrip: Bool) -> CGFloat {
        // header + tab strip + filter bar + footer, plus four dividers,
        // plus the account strip and its own divider when it is there.
        headerHeight + tabStripHeight + filterBarHeight + footerHeight + 4
            + (accountStrip ? accountStripHeight + 1 : 0)
    }

    static var chromeHeight: CGFloat { chromeHeight(accountStrip: false) }

    /// Fallback ceiling, only used if no screen can be determined. The real
    /// limit is the screen height, passed in per call.
    static let fallbackMaxHeight: CGFloat = 900

    static let sizing = sizing(for: .reviews)

    static func sizing(for tab: DrawerTab, accountStrip: Bool = false) -> DrawerSizing {
        DrawerSizing(
            rowSpacing: rowSpacing,
            listPadding: listPadding,
            chromeHeight: chromeHeight(accountStrip: accountStrip),
            maxHeight: fallbackMaxHeight,
            estimatedRowHeight: estimatedRowHeight(for: tab)
        )
    }

    static func drawerHeight(rowHeights: [CGFloat],
                             itemCount: Int,
                             userContentHeight: CGFloat?,
                             maxHeight: CGFloat,
                             snapping: Bool = true,
                             tab: DrawerTab = .reviews,
                             accountStrip: Bool = false) -> CGFloat {
        sizing(for: tab, accountStrip: accountStrip).windowHeight(rowHeights: rowHeights,
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
