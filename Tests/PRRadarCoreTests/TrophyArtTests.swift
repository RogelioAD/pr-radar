import XCTest
@testable import PRRadarCore

/// Thirty drawings are data, so what is wrong with one is an assertion rather
/// than a careful look at a screenshot — the same bargain `PancakeSpriteTests`
/// and `MascotTests` make.
///
/// Building every trophy is most of the value here. `Sprite.init` traps on
/// ragged art and on an unknown slot, and `TrophyArt.badge` traps on a motif
/// that is not square — so a test that merely *constructs* the roster is
/// already checking every literal in the set.
final class TrophyArtTests: XCTestCase {

    // MARK: - The frame

    func testEveryTrophyIsTheDeclaredSize() {
        for trophy in Trophy.all {
            XCTAssertEqual(trophy.art.width, TrophyArt.size, "\(trophy.id) width")
            XCTAssertEqual(trophy.art.height, TrophyArt.size, "\(trophy.id) height")
        }
    }

    func testEveryTrophyActuallyDrawsSomething() {
        for trophy in Trophy.all {
            XCTAssertGreaterThan(trophy.art.litPoints.count, 120,
                                 "\(trophy.id) is nearly empty")
        }
    }

    /// Nothing should fill its whole frame: a trophy that reaches every edge
    /// has no silhouette, and the grid would read as thirty rectangles.
    func testNoTrophyFillsItsEntireFrame() {
        let cells = TrophyArt.size * TrophyArt.size
        for trophy in Trophy.all {
            XCTAssertLessThan(trophy.art.litPoints.count, cells,
                              "\(trophy.id) has no silhouette")
        }
    }

    func testEveryMotifIsSquareAndTheDeclaredSize() {
        // Reached through `badge`, which is what actually enforces it — and
        // constructing the roster above has already run every one. This
        // states the rule the trap is protecting.
        let motif = [String](repeating: String(repeating: ".", count: TrophyArt.motifSize),
                             count: TrophyArt.motifSize)
        let art = TrophyArt.badge(.cup, motif: motif, tier: .gold)
        XCTAssertEqual(art.width, TrophyArt.size)
    }

    // MARK: - Centring
    //
    // Nothing here is visible in a single trophy — a motif a cell high is
    // just a motif. It is visible in a *grid* of thirty, where one sitting
    // high makes the whole row look loose, which is exactly the kind of
    // thing that is easier to assert than to keep noticing.

    /// A motif has to be centred in its own 12 cells, or it lands off-centre
    /// on a base that placed it perfectly.
    func testEveryMotifIsCentredInItsOwnBox() {
        for (name, motif) in Self.everyMotif {
            let lit = motif.enumerated().flatMap { y, row in
                row.enumerated().compactMap { x, c in c == "." ? nil : (x, y) }
            }
            XCTAssertFalse(lit.isEmpty, "\(name) is blank")
            let xs = lit.map(\.0), ys = lit.map(\.1)
            let middle = Double(TrophyArt.motifSize - 1) / 2
            let cx = Double(xs.min()! + xs.max()!) / 2
            let cy = Double(ys.min()! + ys.max()!) / 2
            // Half a cell is the best an odd-sized drawing can do in an
            // even-sized box; a whole cell is a mistake.
            XCTAssertLessThan(abs(cx - middle), 1, "\(name) sits left or right")
            XCTAssertLessThan(abs(cy - middle), 1, "\(name) sits high or low")
        }
    }

    /// And the box itself has to be centred in the frame around it.
    ///
    /// Every base is symmetric, so this is exact rather than approximate —
    /// and it is the check the medal failed. It is the one base with no cream
    /// field to line the motif up against, so its origin was placed by eye,
    /// and a disc drawn about a whole cell is an odd number of cells across,
    /// which nothing 12 wide can ever be centred on.
    func testEveryBaseCentresTheMotifItCarries() {
        for base in [TrophyArt.Base.cup, .shield, .medal, .plaque] {
            let sprite = base.sprite
            let lit = sprite.litPoints
            let xs = lit.map(\.x)
            let frameCentre = Double(xs.min()! + xs.max()!) / 2
            let motifCentre = Double(base.motifOrigin.x)
                + Double(TrophyArt.motifSize - 1) / 2
            XCTAssertEqual(motifCentre, frameCentre, accuracy: 0.001, "\(base)")
        }
    }

    /// The motif must land inside the frame's own drawing, not half off it.
    func testTheMotifSitsWithinTheFrame() {
        for base in [TrophyArt.Base.cup, .shield, .medal, .plaque] {
            let origin = base.motifOrigin
            XCTAssertGreaterThanOrEqual(origin.x, 0, "\(base)")
            XCTAssertGreaterThanOrEqual(origin.y, 0, "\(base)")
            XCTAssertLessThanOrEqual(origin.x + TrophyArt.motifSize,
                                     TrophyArt.size, "\(base)")
            XCTAssertLessThanOrEqual(origin.y + TrophyArt.motifSize,
                                     TrophyArt.size, "\(base)")
        }
    }

    /// Every motif the roster draws, by name, so a failure says which one.
    private static let everyMotif: [(String, [String])] = [
        ("inboxZero", TrophyMotif.inboxZero),
        ("backToZero", TrophyMotif.backToZero),
        ("cleanSweep", TrophyMotif.cleanSweep),
        ("swamped", TrophyMotif.swamped),
        ("inDemand", TrophyMotif.inDemand),
        ("juggler", TrophyMotif.juggler),
        ("greenLight", TrophyMotif.greenLight),
        ("allClear", TrophyMotif.allClear),
        ("shortStack", TrophyMotif.shortStack),
        ("tallStack", TrophyMotif.tallStack),
        ("branchingOut", TrophyMotif.branchingOut),
        ("rubberStamp", TrophyMotif.rubberStamp),
        ("nightWatch", TrophyMotif.nightWatch),
        ("weekendWork", TrophyMotif.weekendWork),
        ("meetTheCast", TrophyMotif.meetTheCast),
        ("bigBadge", TrophyMotif.bigBadge),
        ("tinyBadge", TrophyMotif.tinyBadge),
        ("pancakePress", TrophyMotif.pancakePress),
        ("regular", TrophyMotif.regular),
        ("veteran", TrophyMotif.veteran),
        ("upToDate", TrophyMotif.upToDate),
        ("fiftyMerged", TrophyMotif.fiftyMerged),
        ("century", TrophyMotif.century),
        ("mystery", TrophyMotif.mystery),
    ]

    // MARK: - Tiers

    /// A tier swap must change the metal and nothing else. If it changed the
    /// silhouette, the ladder would stop reading as one ladder.
    func testTiersDifferOnlyInWhichMetalIsStruck() {
        let gold = TrophyArt.badge(.cup, motif: TrophyMotif.century, tier: .gold)
        let bronze = TrophyArt.badge(.cup, motif: TrophyMotif.century, tier: .bronze)

        XCTAssertEqual(gold.litPoints, bronze.litPoints)
        for point in gold.litPoints {
            let left = gold[point.x, point.y]
            let right = bronze[point.x, point.y]
            if left == .gold {
                XCTAssertEqual(right, .bronze, "at (\(point.x), \(point.y))")
            } else if left == .goldShade {
                XCTAssertEqual(right, .bronzeShade, "at (\(point.x), \(point.y))")
            } else {
                XCTAssertEqual(left, right, "at (\(point.x), \(point.y))")
            }
        }
    }

    /// Bases are authored in gold, so a silver one must have none left in it.
    func testANonGoldTierKeepsNoGoldAtAll() {
        for base in [TrophyArt.Base.cup, .shield, .medal, .plaque] {
            let art = TrophyArt.badge(base, motif: TrophyMotif.mystery, tier: .silver)
            for point in art.litPoints {
                let slot = art[point.x, point.y]
                XCTAssertNotEqual(slot, .gold, "\(base)")
                XCTAssertNotEqual(slot, .goldShade, "\(base)")
            }
        }
    }

    /// The motif has to land inside the frame and actually replace what was
    /// under it — a badge whose engraving fell off the edge would still be a
    /// valid sprite.
    func testTheMotifIsStampedIntoTheFrame() {
        let solid = [String](repeating: String(repeating: "r", count: TrophyArt.motifSize),
                             count: TrophyArt.motifSize)
        for base in [TrophyArt.Base.cup, .shield, .medal, .plaque] {
            let art = TrophyArt.badge(base, motif: solid, tier: .gold)
            let crimson = art.litPoints.filter { art[$0.x, $0.y] == .crimson }
            XCTAssertEqual(crimson.count, TrophyArt.motifSize * TrophyArt.motifSize,
                           "\(base) lost part of its motif")
        }
    }

    /// `.` in a motif is transparent, so the base shows through.
    func testAnEmptyMotifLeavesTheBaseUntouched() {
        let blank = [String](repeating: String(repeating: ".", count: TrophyArt.motifSize),
                             count: TrophyArt.motifSize)
        XCTAssertEqual(TrophyArt.badge(.shield, motif: blank, tier: .gold).cells,
                       TrophyBaseArt.shield.cells)
    }

    // MARK: - The palette

    /// Every slot has to resolve in both appearances, or a trophy drawn in
    /// Dark would be missing pixels a test on the sprite alone cannot see.
    func testEverySlotHasAColourInBothAppearances() {
        for slot in Slot.allCases {
            for dark in [true, false] {
                let rgb = SpritePalette.color(for: slot, dark: dark)
                XCTAssertGreaterThan(rgb.alpha, 0, "\(slot) dark=\(dark)")
            }
        }
    }

    /// The locked treatment has to actually take the colour out — and stay
    /// well clear of both ends, so a locked gold cup is not still the
    /// brightest thing on the shelf.
    func testLockedColoursAreGreyAndMidToned() {
        for slot in Slot.allCases {
            let locked = SpritePalette.locked(SpritePalette.color(for: slot, dark: false))
            XCTAssertEqual(locked.red, locked.green, accuracy: 0.0001, "\(slot)")
            XCTAssertEqual(locked.green, locked.blue, accuracy: 0.0001, "\(slot)")
            XCTAssertGreaterThan(locked.red, 0.2, "\(slot) went black")
            XCTAssertLessThan(locked.red, 0.75, "\(slot) stayed bright")
        }
    }

    /// Two slots that look different unlocked should still look different
    /// locked — otherwise the shelf is thirty identical grey blobs.
    func testLockedColoursStayDistinguishable() {
        let gold = SpritePalette.locked(SpritePalette.color(for: .gold, dark: false))
        let ink = SpritePalette.locked(SpritePalette.color(for: .ink, dark: false))
        XCTAssertGreaterThan(abs(gold.red - ink.red), 0.1)
    }
}
