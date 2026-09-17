import AppKit
import PRRadarCore

enum Layout {
    /// Matches the user's Dock icon size, so the badge starts out alongside the
    /// Dock as a peer rather than looking oversized. Read once at launch.
    ///
    /// This is the *default* only. The badge can be resized from its corners,
    /// and once it has been the size comes from `AppState.badgeTileSize`, which
    /// is why every metric below is a function of a tile size rather than of
    /// this.
    static let dockTileSize: CGFloat = {
        let raw = UserDefaults(suiteName: "com.apple.dock")?
            .object(forKey: "tilesize") as? Double
        return CGFloat(min(max(raw ?? 48, 28), 80))
    }()

    /// How far the badge can be dragged. The bounds are the smallest and
    /// largest real Dock tile sizes, so it stays a believable Dock peer at
    /// either end — `dockTileSize` clamps tighter because it is following the
    /// Dock, not the user's own hand.
    static let badgeSizing = BadgeSizing(minimum: 28, maximum: 128)

    /// Grip depth at each corner of the collapsed badge. Generous for the same
    /// reason as `resizeEdge`: 6pt was missed more often than it was hit.
    /// `BadgeZones` shrinks it on a small badge so the middle stays clickable.
    static let badgeGrip: CGFloat = 12
    static let badgeZones = BadgeZones(grip: badgeGrip)

    /// Corner radius in Dock proportions (a squircle is ~22% of the tile).
    static func badgeCornerRadius(tile: CGFloat) -> CGFloat { (tile * 0.24).rounded() }
    /// The glyph, deliberately smaller than the tile it sits in.
    static func badgeGlyphSize(tile: CGFloat) -> CGFloat { (tile * 0.50).rounded() }
    /// Dock badges run just under half the tile.
    static func countBadgeSize(tile: CGFloat) -> CGFloat { (tile * 0.46).rounded() }
    /// How far the count badge pokes out past the tile's corner. Less than its
    /// radius, so the badge's centre sits *inside* the corner and it overlaps
    /// the tile the way a Dock badge overlaps its app icon.
    static func countBadgeOverhang(tile: CGFloat) -> CGFloat {
        (countBadgeSize(tile: tile) * 0.34).rounded()
    }
    /// Panel footprint with the mascot turned off: one overhang's worth on the
    /// right, and one at *each* of top and bottom, because two same-sized
    /// badges hang off the tile's corners — the review count above, the
    /// ready-to-merge count below.
    static func tileBadgeWidth(tile: CGFloat) -> CGFloat {
        tile + countBadgeOverhang(tile: tile)
    }
    static func tileBadgeHeight(tile: CGFloat) -> CGFloat {
        tile + countBadgeOverhang(tile: tile) * 2
    }
    static func tileBadgeSize(tile: CGFloat) -> CGSize {
        CGSize(width: tileBadgeWidth(tile: tile), height: tileBadgeHeight(tile: tile))
    }

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
    /// Nothing else has to change for this: `chromeHeight(for:)` is derived
    /// from it and `DrawerSizing` reads that, so the drawer re-measures on
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

    // MARK: - Achievement banner

    /// The banner's scale on a given screen. Everything about it — type,
    /// emblem, padding, the gaps — is a multiple of this one number, so the
    /// whole thing sizes itself to whatever display it lands on. The rule is in
    /// `Achievement` so it can be tested without a screen.
    static func achievementScale(on screen: NSScreen?,
                                 emblem: Sprite,
                                 title: String) -> CGFloat {
        Achievement.scale(forScreenWidth: screen?.visibleFrame.width ?? 1440,
                          emblem: emblem, title: title)
    }

    // MARK: - Trophies

    /// Trophy art is 32 cells square and draws at 2x, so a cell is 64pt.
    ///
    /// Whole, like every other sprite in the app: at a fractional scale the
    /// grid would be thirty blurry JPEGs. 2x is also what makes the room
    /// affordable — five 64pt drawings across the drawer's 440pt leaves real
    /// gaps between them, where 3x would fit three.
    static let trophyScale: CGFloat = 2
    static var trophyCell: CGFloat { CGFloat(TrophyArt.size) * trophyScale }
    /// Five across, which is what `TrophyGrid` chunks the roster into.
    static let trophyColumns = TrophyGrid.columns
    /// Air between cells, and between rows. Wider than a list's 2pt: rows in a
    /// list are separated by their own borders, and a grid has none — the gap
    /// *is* the separation.
    static let trophyGridSpacing: CGFloat = 12

    /// Padding at each side of the grid, so it sits centred in the drawer.
    ///
    /// Derived rather than picked, because the cells and the gaps are both
    /// fixed: whatever is left over is the margin, and splitting it is the only
    /// way the row lands centred at every width this drawer might take.
    static var trophyGridInset: CGFloat {
        let content = CGFloat(trophyColumns) * trophyCell
            + CGFloat(trophyColumns - 1) * trophyGridSpacing
        return max(0, (drawerWidth - content) / 2)
    }

    // MARK: - Pancakes

    /// The stack marker on a My PRs row. 2x puts a five-deep stack at 26pt,
    /// which fits a row that is already carrying four lines of chips; 3x does
    /// not.
    static let pancakeRowScale: CGFloat = 2
    /// How much room a row keeps for its marker, whatever the depth: the sprite
    /// is a fixed width and only grows downward.
    static var pancakeMarkerWidth: CGFloat { CGFloat(Pancakes.width) * pancakeRowScale }
    /// The filter bar's toggle, which has to sit inside a capsule barely 17pt
    /// tall. 1x is the only scale that does, and the shape still reads.
    static let pancakeChipScale: CGFloat = 1
    /// Width a row actually gets in the list: the drawer less the 6pt the list
    /// insets on each side.
    ///
    /// Definite rather than `maxWidth: .infinity`, because a `Chip` is
    /// `.fixedSize()` — a row carrying five of them reports a wider ideal than
    /// it was offered, and `maxWidth` sets a floor, not a ceiling. Nothing drew
    /// attention to that while rows had no border of their own; a stack card
    /// wrapped around one promptly grew 14pt past the drawer and had its
    /// corners clipped off.
    static var listContentWidth: CGFloat { drawerWidth - listPadding }

    /// Breathing room inside a stack group's outline.
    static let stackGroupPadding: CGFloat = 6
    /// What a row gets inside a stack card, which is the above less the card's
    /// own padding — so the card lands at exactly `listContentWidth`.
    static var stackRowWidth: CGFloat { listContentWidth - stackGroupPadding * 2 }
    /// Rounder than a row's 7, so the card reads as holding the rows rather
    /// than as one more of them.
    static let stackGroupRadius: CGFloat = 12


    /// The character plus its halo is 18 cells wide, and that is what should
    /// match the Dock tile — the counters hang off it rather than shrinking it.
    private static let badgeCharacterCells = 18

    /// Never below 2x, whatever the Dock is doing. Not because the character
    /// breaks, but because the counter's 3x5 digits stop being a number: at
    /// 1.5x a digit is seven and a half points tall.
    private static let badgeMinimumScale: CGFloat = 2

    static func badgeScale(tile: CGFloat, backingScale: CGFloat) -> CGFloat {
        SpriteScale.snapped(targetPoints: tile,
                            spriteWidth: badgeCharacterCells,
                            backingScale: backingScale,
                            minimum: badgeMinimumScale)
    }

    /// The tile size a snapped scale actually represents.
    ///
    /// A mascot badge can only be drawn at whole device pixels, so a dragged
    /// size lands between two of them. Storing what was *drawn* rather than
    /// what was asked for is what stops the badge drifting a few points every
    /// time it is resized and reopened.
    static func tileSize(forBadgeScale scale: CGFloat) -> CGFloat {
        CGFloat(badgeCharacterCells) * scale
    }

    /// Padding `SpriteCanvas` adds around a haloed, shadowed composition:
    /// one cell of halo on the leading edge, one of halo plus one of shadow on
    /// the trailing one.
    private static let badgeLeadPadCells = 1
    private static let badgeTrailPadCells = 2
    private static let badgePadCells = badgeLeadPadCells + badgeTrailPadCells

    static func badgeSize(for layout: SpriteLayout, scale: CGFloat) -> CGSize {
        CGSize(width: CGFloat(layout.width + badgePadCells) * scale,
               height: CGFloat(layout.height + badgePadCells) * scale)
    }

    /// Where the mascot badge is actually *drawn* inside its panel, measured
    /// from the panel's visual top-left.
    ///
    /// The panel is deliberately bigger than this: a widget reserves the mark
    /// gutter whether or not a mark is showing, and keeps bob room under the
    /// character's feet, so with no counts the art fills barely two thirds of
    /// the height. How much of its 16x16 cell each character fills differs too.
    /// Anything that has to line up with what the eye sees — the corner grips —
    /// needs this rather than the panel.
    ///
    /// The halo and the shadow are drawn and so are counted: `contentBounds` is
    /// the tight box around the lit cells, and both extend exactly one cell
    /// past it.
    static func badgeArtRect(for layout: SpriteLayout, scale: CGFloat) -> CGRect? {
        guard let content = layout.contentBounds else { return nil }
        // Cell (x, y) lands at (x + lead) * scale; the halo starts one cell
        // before that, which cancels the lead exactly.
        return CGRect(x: CGFloat(content.origin.x) * scale,
                      y: CGFloat(content.origin.y) * scale,
                      width: CGFloat(content.width + 2) * scale,
                      height: CGFloat(content.height + 2) * scale)
    }

    /// The same, for the plain tile.
    ///
    /// The tile's square body, not the count badges that overhang its corners:
    /// the body is always drawn, so the grips keep still when a count appears
    /// or goes away — and the badges sit centred on the very corners the grips
    /// already cover.
    static func tileArtRect(tile: CGFloat) -> CGRect {
        CGRect(x: 0, y: countBadgeOverhang(tile: tile), width: tile, height: tile)
    }

    /// Used only before rows report their real size — which is exactly the
    /// first open on a fresh install, when nothing has been measured yet.
    ///
    /// Per tab, because a My PRs row carries far more than a review row does:
    /// approvals, checks, blockers, stack position. Estimating both at the
    /// review row's height opened that tab well short of a row boundary, and
    /// it only squared up once the rows reported and the layout ran again.
    static func estimatedRowHeight(for surface: DrawerSurface) -> CGFloat {
        switch surface {
        case .reviews: return 80
        case .mine: return 130
        // Not an estimate at all: every grid row is one cell tall, and a cell
        // is a fixed sprite at a fixed scale. The trophy room is the one
        // surface that knows its row height before a row has measured itself.
        case .trophies: return trophyCell
        }
    }

    static let estimatedRowHeight: CGFloat = estimatedRowHeight(for: .reviews)

    /// The account strip's own row. Shorter than the tab strip: it carries no
    /// icons, and it is a scope selector rather than the drawer's main control.
    static let accountStripHeight: CGFloat = 26

    /// What the drawer carries above and below the scrolling part.
    ///
    /// Two axes, because two separate things move it. The *surface* decides
    /// whether the tab strip and filter bar are drawn at all — the trophy room
    /// hides both. `accountStrip` decides whether a further row sits above
    /// them, and it is only ever true on a machine with more than one account:
    /// assuming it away would clip the last row by exactly its height on the
    /// machines that have it, and assuming it present would leave a band of
    /// empty material on the ones that do not.
    ///
    /// A room ignores `accountStrip` rather than asking callers not to pass it.
    /// The strip is a scope selector, and a room hides the scope controls for
    /// the same reason it hides the tab strip: there is nothing below them for
    /// them to act on.
    static func chromeHeight(for surface: DrawerSurface,
                             accountStrip: Bool = false) -> CGFloat {
        switch surface {
        // header + tab strip + filter bar + footer, plus four dividers, and
        // the account strip with its own divider when it is there.
        case .reviews, .mine:
            return headerHeight + tabStripHeight + filterBarHeight + footerHeight + 4
                + (accountStrip ? accountStripHeight + 1 : 0)
        // header + progress footer, plus two dividers.
        case .trophies:
            return headerHeight + footerHeight + 2
        }
    }

    /// Fallback ceiling, only used if no screen can be determined. The real
    /// limit is the screen height, passed in per call.
    static let fallbackMaxHeight: CGFloat = 900

    static let sizing = sizing(for: .reviews)

    static func sizing(for surface: DrawerSurface,
                       accountStrip: Bool = false) -> DrawerSizing {
        DrawerSizing(
            rowSpacing: surface == .trophies ? trophyGridSpacing : rowSpacing,
            listPadding: listPadding,
            chromeHeight: chromeHeight(for: surface, accountStrip: accountStrip),
            maxHeight: fallbackMaxHeight,
            estimatedRowHeight: estimatedRowHeight(for: surface)
        )
    }

    static func drawerHeight(rowHeights: [CGFloat],
                             itemCount: Int,
                             userContentHeight: CGFloat?,
                             maxHeight: CGFloat,
                             snapping: Bool = true,
                             surface: DrawerSurface = .reviews,
                             accountStrip: Bool = false) -> CGFloat {
        sizing(for: surface, accountStrip: accountStrip)
            .windowHeight(rowHeights: rowHeights,
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
