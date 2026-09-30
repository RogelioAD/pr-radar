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

    /// The "something in here changed" dot, wherever one is drawn.
    ///
    /// One number rather than three. The same signal appears on the footer's
    /// room buttons, on the tab strip and on a newly-won trophy, and the
    /// trophy's was a point larger than the other two for no reason anybody
    /// could have named — which reads as two different marks rather than one
    /// mark in two places.
    static let noticeDot: CGFloat = 5

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

    /// Twice that, for reading a diff. See `DrawerWidth` for when it applies —
    /// which is only ever while a findings list is open, and never as a setting
    /// anybody has to put back.
    static let wideDrawerWidth: CGFloat = drawerWidth * 2
    static let tabStripHeight: CGFloat = 30

    /// The band the scope and narrowing controls sit in.
    ///
    /// Its own band, and it has to be. Folding it into the tab strip was tried:
    /// the two looked half empty, and they are — but only when nothing is
    /// selected. With a real repository picked the pills come to 406pt on their
    /// own, and the merged band overflowed 440 by 334. What looked like wasted
    /// space was the *empty* state of a bar that fills right up.
    static let filterBarHeight: CGFloat = 32
    /// Sized for the mascot lockup: 12pt resize strip plus a 36pt row, which is
    /// exactly what a 2x character with its bob room needs. Was 40 when the
    /// header carried only a 12pt SF Symbol.
    ///
    /// Nothing else has to change for this: `chromeHeight(for:)` is derived
    /// from it and `DrawerSizing` reads that, so the drawer re-measures on
    /// its own.
    /// Not reduced when the header emptied out, and that is deliberate.
    ///
    /// Forty was tried: the band's inner height is `headerHeight - resizeEdge`,
    /// and the mascot is twelve sprite rows at `headerMascotScale` plus its
    /// padding — about 28pt. Forty leaves exactly 28, so the character sat
    /// flush against both edges with nowhere to breathe. The header has room to
    /// spare now; the mascot is what decides how much it needs.
    static let headerHeight: CGFloat = 48
    static let footerHeight: CGFloat = 28
    static let rowSpacing: CGFloat = 2
    static let listPadding: CGFloat = 12
    /// Height of the grab strip along the drawer's top edge. Generous on
    /// purpose: at 6pt the pointer missed it more often than it hit it.
    static let resizeEdge: CGFloat = 12
    /// The capsule drawn in that strip, as wide as it looks.
    static let resizeHandleMark: CGFloat = 36
    /// What the strip actually answers for, centred: the capsule plus 18pt of
    /// slop each side.
    ///
    /// Not the drawer's full width, which is what it used to be. The top edge
    /// of a window is the one place a hand goes to move it, and the whole of
    /// it resizing meant the drawer could only be moved from the bare material
    /// beside the title — so it read as a window that could not be moved at
    /// all. The handle keeps its column; the rest of the edge drags.
    static let resizeHandle: CGFloat = 72
    /// Gap kept from the screen edges when placing the panel by default.
    static let screenInset: CGFloat = 24

    // MARK: - Mascot

    // Every mascot scale below is expressed as the *physical* size the
    // character should come out at, then snapped to whole device pixels —
    // rather than as a multiplier of its cells.
    //
    // It used to be the other way round, which worked only while the cast was
    // one fixed size. Redrawing it at 48 cells turned `2` from "a 32pt bust"
    // into "an 80pt one", and every one of these constants would have had to
    // be found and divided by three. Asking for points and letting the art
    // decide the multiplier is the arrangement that cannot drift.

    /// The header lockup: a bust about this tall, mark gutter included.
    static let headerMascotPoints: CGFloat = 26
    /// The empty states already reserve a whole row's height for a 20pt SF
    /// Symbol, so this costs no layout at all.
    static let emptyStateMascotPoints: CGFloat = 48
    /// The row of new characters in the arrival banner. Small: they are there to be
    /// recognised, not read — the character itself is one click away.
    static let noticeMascotPoints: CGFloat = 20

    /// How tall the arrival banner is.
    ///
    /// One number, read by the view that draws it and by `chromeHeight`, which
    /// makes room for it. The two disagreeing is exactly the bug — the same
    /// one `emptyStateHeight` carries a note about.
    static let castNoticeHeight: CGFloat = 52

    /// The empty mark gutter on a banner perch, in points, so the row of
    /// faces can close it up. Derived from the same arithmetic
    /// `SpriteLayout.blockWidth` uses rather than measured off a screenshot.
    static func noticeMascotGutter(for mascots: [Mascot], backingScale: CGFloat) -> CGFloat {
        guard let first = mascots.first else { return 0 }
        let unit = CGFloat(SpriteLayout.unit(for: first))
        return (unit + CGFloat(Mark.width) * unit)
            * noticeMascotScale(for: mascots, backingScale: backingScale)
    }

    /// One scale for the whole row of them, taken from the tallest crop.
    ///
    /// Not per character, which is what every other mascot surface does and
    /// what this tried first. A scale snapped from each character's own
    /// `headRows` lands on a different rung for each: Rattle crops to 26 rows
    /// and rounds up to 1×, so he came out at twice the size of the other
    /// three and 66pt wide, which pushed the caption beside them off the end
    /// of the strip. Elsewhere a character is alone and its own size is the
    /// only one that matters; in a row they are being compared, and four
    /// characters at three scales reads as a mistake because it is one.
    static func noticeMascotScale(for mascots: [Mascot], backingScale: CGFloat) -> CGFloat {
        SpriteScale.snapped(targetPoints: noticeMascotPoints,
                            spriteWidth: mascots.map(\.headRows).max() ?? 48,
                            backingScale: backingScale,
                            minimum: 1 / max(1, backingScale))
    }

    static func headerMascotScale(for mascot: Mascot, backingScale: CGFloat) -> CGFloat {
        SpriteScale.snapped(targetPoints: headerMascotPoints,
                            spriteWidth: mascot.headRows,
                            backingScale: backingScale,
                            minimum: 1 / max(1, backingScale))
    }

    static func emptyStateMascotScale(for mascot: Mascot, backingScale: CGFloat) -> CGFloat {
        SpriteScale.snapped(targetPoints: emptyStateMascotPoints,
                            spriteWidth: mascot.sprite.height,
                            backingScale: backingScale,
                            minimum: 1 / max(1, backingScale))
    }

    /// How much room a list with nothing in it takes.
    ///
    /// Measured rather than guessed: the mascot is twelve sprite rows at
    /// `emptyStateMascotScale` (36pt), then 6pt, a 12.5pt title, 6pt, and up to
    /// two 11pt lines of detail, inside 8pt of padding each side — 111pt. It
    /// was being given one row's worth, which is now 78, and the difference was
    /// spilling out of the top and the bottom of the drawer.
    ///
    /// One number, read by both the view that draws it and the sizing that
    /// makes room for it, because the two disagreeing is exactly the bug.
    static let emptyStateHeight: CGFloat = 112

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
    /// Half a point per cell, matching the cast. Whole device pixels on a
    /// 2x display; 64pt — what a 32-cell trophy used to occupy — is not
    /// reachable at 96 cells without landing between two device pixels.
    static let trophyScale: CGFloat = 0.5
    static var trophyCell: CGFloat { CGFloat(TrophyArt.drawnSize) * trophyScale }
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
    /// Never smaller than this, whatever the Dock is doing. Not because the
    /// character breaks, but because the counter's digits stop being a number:
    /// a digit below about ten points is a smudge. Expressed in points and
    /// converted, so enlarging the art cannot quietly shrink the floor.
    private static let badgeMinimumDigitPoints: CGFloat = 10

    /// `crisp` is false only while a corner is being dragged, where the badge
    /// follows the pointer instead of the ladder. See `SpriteScale.continuous`
    /// for why, and `PanelController.commitCornerResize` for the settle.
    static func badgeScale(tile: CGFloat, backingScale: CGFloat,
                           mascot: Mascot, crisp: Bool = true) -> CGFloat {
        let cells = SpriteLayout.blockHeight(for: mascot)
        let digitCells = Counter.height * SpriteLayout.unit(for: mascot)
        let floor = badgeMinimumDigitPoints / CGFloat(digitCells)
        guard crisp else {
            return SpriteScale.continuous(targetPoints: tile,
                                          spriteWidth: cells, minimum: floor)
        }
        return SpriteScale.snapped(targetPoints: tile,
                                   spriteWidth: cells,
                                   backingScale: backingScale,
                                   minimum: floor)
    }

    /// The tile size a snapped scale actually represents.
    ///
    /// A mascot badge can only be drawn at whole device pixels, so a dragged
    /// size lands between two of them. Storing what was *drawn* rather than
    /// what was asked for is what stops the badge drifting a few points every
    /// time it is resized and reopened.
    /// The smallest and largest size the badge can actually be dragged to,
    /// which is what the "biggest"/"smallest" trophies have to be measured
    /// against — see `BadgeSizing.reachableRange`.
    static func reachableBadgeTileRange(mascot: Mascot?,
                                        backingScale: CGFloat) -> (minimum: CGFloat,
                                                                   maximum: CGFloat) {
        guard let mascot else {
            return badgeSizing.reachableRange(spriteWidth: nil,
                                              backingScale: backingScale,
                                              minimumScale: 1)
        }
        let digitCells = Counter.height * SpriteLayout.unit(for: mascot)
        return badgeSizing.reachableRange(
            spriteWidth: SpriteLayout.blockHeight(for: mascot),
            backingScale: backingScale,
            minimumScale: badgeMinimumDigitPoints / CGFloat(digitCells))
    }

    static func tileSize(forBadgeScale scale: CGFloat, mascot: Mascot) -> CGFloat {
        CGFloat(SpriteLayout.blockHeight(for: mascot)) * scale
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
        // Two metadata lines became one when the author joined the number and
        // the repo, so the pre-measurement guess came down with them.
        case .reviews: return 66
        case .mine: return 130
        // Not an estimate at all: every grid row is one cell tall, and a cell
        // is a fixed sprite at a fixed scale. The trophy room is the one
        // surface that knows its row height before a row has measured itself.
        case .trophies: return trophyCell
        // A section's height depends entirely on how many controls it holds,
        // so this is a genuine estimate — near the middle of the three, used
        // only for the single frame before the groups report themselves.
        case .settings, .review: return 130
        // A shelf: four characters and a heading, which is a fixed drawing
        // rather than an estimate.
        case .mascots: return mascotShelfHeight
        }
    }

    static let estimatedRowHeight: CGFloat = estimatedRowHeight(for: .reviews)

    /// What the drawer carries above and below the scrolling part.
    ///
    /// Per surface, because the trophy room hides the tab strip and the filter
    /// bar. Charging it for two controls it is not drawing would leave it 62pt
    /// taller than its own contents — a band of empty material under the last
    /// row of trophies.
    ///
    /// One axis, and deliberately still one now that accounts exist: the
    /// account picker is a pill inside the filter bar rather than a row of its
    /// own, so a second account costs no chrome and there is nothing here to
    /// keep in step with it.
    ///
    /// `notice` is the arrival banner's height, or zero when it is not up.
    /// Passed in rather than read from anywhere, because this is the number
    /// the *window* is framed from: a strip drawn in the drawer that this does
    /// not count is a strip the panel has made no room for, and what it costs
    /// is the last row of the list. The banner draws itself at exactly
    /// `castNoticeHeight` for the same reason.
    static func chromeHeight(for surface: DrawerSurface,
                             notice: CGFloat = 0) -> CGFloat {
        switch surface {
        // header + tab strip + filter bar + footer, plus four dividers.
        case .reviews, .mine:
            return headerHeight + tabStripHeight + filterBarHeight + footerHeight + 4 + notice
        // header + progress footer, plus two dividers. Every other room hides
        // the same two controls and carries a footer of the same height, so
        // they all come to exactly the same chrome.
        case .trophies, .settings, .review:
            return headerHeight + footerHeight + 2 + notice
        // The same, plus the "no mascot" line the shelves do not count.
        case .mascots:
            return headerHeight + footerHeight + 2 + notice + mascotOffRowHeight
        }
    }

    /// The gap a room puts between its units, where a list would use
    /// `rowSpacing`. nil for the tabs, which use the list's own 2pt.
    ///
    /// Every room needs more air than a list does and for the same reason: list
    /// rows are separated by their own borders, and neither a trophy grid nor a
    /// stack of setting groups has any — the gap *is* the separation.
    static func roomSpacing(for surface: DrawerSurface) -> CGFloat? {
        switch surface {
        case .trophies: return trophyGridSpacing
        case .settings, .review, .mascots: return settingsSectionSpacing
        case .reviews, .mine: return nil
        }
    }

    // MARK: - Mascot room

    /// One character's cell in the room, whole rather than cropped to its
    /// head. Big enough to tell two apart at a glance, which is the whole job
    /// of the screen — and a room is the one place there is space to show a
    /// character in full, so cropping it here was just the header's habit
    /// carried somewhere it does not apply.
    static let mascotRoomPoints: CGFloat = 54
    /// Gap between cells, and between one shelf and the next.
    static let mascotGridSpacing: CGFloat = 10

    static func mascotRoomScale(backingScale: CGFloat) -> CGFloat {
        // One scale for the whole room, off the full block every character
        // occupies rather than each one's own crop. Two reasons, and the
        // second is the one that bit: a grid where characters are sized
        // individually is a grid of different-sized characters, and the crop
        // heights differ by eight rows across the cast — so scaling by them
        // made Rattle noticeably smaller than Gourd for no reason a reader
        // could see. `blockHeight` is the same for all of them.
        SpriteScale.snapped(targetPoints: mascotRoomPoints,
                            spriteWidth: SpriteLayout.blockHeight(for: Mascot.blip),
                            backingScale: backingScale,
                            minimum: 1 / max(1, backingScale))
    }

    /// What one shelf occupies: its heading, and one row of whole characters
    /// with their names under them. Used for the single frame before the
    /// shelves report their own measurements.
    static var mascotShelfHeight: CGFloat { mascotRoomPoints + 46 }

    /// The "no mascot" line under the shelves.
    ///
    /// Counted in the room's chrome rather than as a row, because it is not
    /// one: the drawer snaps to shelves. Left out of both it was left out of
    /// the height too, and the one control that turns the character off sat
    /// just below the fold of a window that had sized itself to fit.
    static let mascotOffRowHeight: CGFloat = 30

    // MARK: - Settings

    /// Air between setting groups. One notch tighter than the trophy grid's:
    /// the groups are already boxed, so the gap is reinforcing a separation
    /// rather than carrying it alone.
    static let settingsSectionSpacing: CGFloat = 10
    /// Padding inside a group's box.
    static let settingsSectionPadding: CGFloat = 10
    /// Matches the stack card, so the two boxed things in the app agree.
    static let settingsSectionRadius: CGFloat = 12
    /// Vertical gap between the controls within one group.
    static let settingsRowSpacing: CGFloat = 8
    /// Side margin, so the groups sit inset from the drawer's edges the way the
    /// trophy grid does rather than running into them.
    static let settingsInset: CGFloat = 12
    /// What a group's contents actually get: the drawer, less the margin at
    /// each side and the box's own padding at each side.
    static var settingsContentWidth: CGFloat {
        drawerWidth - settingsInset * 2 - settingsSectionPadding * 2
    }

    /// Fallback ceiling, only used if no screen can be determined. The real
    /// limit is the screen height, passed in per call.
    static let fallbackMaxHeight: CGFloat = 900

    static let sizing = sizing(for: .reviews)

    static func sizing(for surface: DrawerSurface, notice: CGFloat = 0) -> DrawerSizing {
        DrawerSizing(
            rowSpacing: roomSpacing(for: surface) ?? rowSpacing,
            listPadding: listPadding,
            chromeHeight: chromeHeight(for: surface, notice: notice),
            maxHeight: fallbackMaxHeight,
            estimatedRowHeight: estimatedRowHeight(for: surface),
            emptyHeight: emptyStateHeight
        )
    }

    static func drawerHeight(rowHeights: [CGFloat],
                             itemCount: Int,
                             userContentHeight: CGFloat?,
                             maxHeight: CGFloat,
                             snapping: Bool = true,
                             surface: DrawerSurface = .reviews,
                             notice: CGFloat = 0) -> CGFloat {
        sizing(for: surface, notice: notice)
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
