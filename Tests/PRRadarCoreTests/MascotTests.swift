import XCTest
@testable import PRRadarCore

/// The art is data, so its invariants are assertions rather than a careful look
/// at a screenshot.
final class MascotTests: XCTestCase {

    func testEverySpriteIsFortyEightSquare() {
        for mascot in Mascot.all {
            XCTAssertEqual(mascot.sprite.width, 48, "\(mascot.name) width")
            XCTAssertEqual(mascot.sprite.height, 48, "\(mascot.name) height")
        }
    }

    /// Every character is authored as 48 rows of 24 and mirrored, so the
    /// silhouette has to come back symmetric to the pixel. The *colours* do
    /// not: the shading pass lights from the upper left, which is the whole
    /// point of it.
    func testEverySilhouetteIsMirrorSymmetric() {
        for mascot in Mascot.all {
            let art = mascot.sprite
            for y in 0..<art.height {
                for x in 0..<(art.width / 2) {
                    XCTAssertEqual(art[x, y] == nil,
                                   art[art.width - 1 - x, y] == nil,
                                   "\(mascot.name) silhouette at (\(x), \(y))")
                }
            }
        }
    }

    /// The shading pass may not invent a specular highlight — one it decides
    /// on its own turns a soft edge into a hard white rim, which is exactly
    /// what happened to the first floater.
    func testSpecularIsRareEnoughToBeDeliberate() {
        for mascot in Mascot.all {
            let spec = mascot.sprite.litPoints.filter { mascot.sprite[$0.x, $0.y] == .chassisSpec }
            let lit = mascot.sprite.litPoints.count
            XCTAssertLessThan(Double(spec.count) / Double(lit), 0.05,
                              "\(mascot.name) is \(spec.count)/\(lit) specular — that is a rim, not a highlight")
        }
    }

    func testEyeBoxesAreInBoundsAndOnSkin() {
        for mascot in Mascot.all {
            for box in mascot.eyes {
                let n = mascot.eyeSize
                XCTAssertTrue(box.x >= 0 && box.y >= 0
                              && box.x + n <= mascot.sprite.width
                              && box.y + n <= mascot.sprite.height,
                              "\(mascot.name) eye box \(box) out of bounds")
                for dy in 0..<n {
                    for dx in 0..<n {
                        XCTAssertNotNil(mascot.sprite[box.x + dx, box.y + dy],
                                        "\(mascot.name) eye on a transparent pixel")
                    }
                }
            }
        }
    }

    /// Eyes have to sit symmetrically about the centre line, or a face reads
    /// as a pixel off even though every feature is where it was drawn.
    func testEyesArePlacedSymmetricallyAboutTheCentre() {
        for mascot in Mascot.all {
            XCTAssertEqual(mascot.eyes.count, 2, "\(mascot.name)")
            let left = mascot.eyes[0], right = mascot.eyes[1]
            let n = mascot.eyeSize, w = mascot.sprite.width
            XCTAssertEqual(left.x + n - 1, w - 1 - right.x,
                           "\(mascot.name) eyes are off-centre")
            XCTAssertEqual(left.y, right.y, "\(mascot.name) eyes are not level")
        }
    }

    /// A dark-eyed mascot loses the mood colour entirely without one, which is
    /// how two of the previous four ended up reading identically.
    func testEveryMascotHasATellOutsideItsEyes() {
        for mascot in Mascot.all {
            XCTAssertFalse(mascot.tell.isEmpty, "\(mascot.name) has no tell")
            let n = mascot.eyeSize
            let inEye = { (point: Point) in
                mascot.eyes.contains { box in
                    (box.x..<box.x + n).contains(point.x) && (box.y..<box.y + n).contains(point.y)
                }
            }
            XCTAssertTrue(mascot.tell.contains { !inEye($0) },
                          "\(mascot.name)'s tell is entirely inside its eyes")
        }
    }

    func testApplyingAMoodLightsTheTellAndDrawsTheEyes() {
        for mascot in Mascot.all {
            let shut = mascot.frame(eyes: .shut)
            let open = mascot.frame(eyes: .open)
            XCTAssertNotEqual(shut, open, "\(mascot.name) looks the same shut as open")
            let box = mascot.eyes[0]
            XCTAssertEqual(open[box.x + mascot.eyeSize / 2, box.y + mascot.eyeSize / 2],
                           mascot.eyeInk,
                           "\(mascot.name) open eye has no ink in the middle of it")
        }
    }

    /// Only the ones with nothing under them.
    func testTheFloatersBobFurther() {
        for mascot in [Mascot.scoot, .wobble, .boo, .flit] {
            XCTAssertEqual(mascot.bobScale, 2, "\(mascot.name) floats")
        }
        for mascot in [Mascot.blip, .bloop, .gourd, .rattle] {
            XCTAssertEqual(mascot.bobScale, 1, "\(mascot.name) stands on something")
        }
    }

    // MARK: - The sweep

    /// Three of them have glass for a beam to cross. The other five do not,
    /// and each does something else — the branch exists precisely because
    /// they are the exceptions.
    func testGlassIsFoundOnTheThreeThatHaveIt() {
        XCTAssertNotNil(Mascot.blip.glassBounds)
        XCTAssertNotNil(Mascot.scoot.glassBounds)
        XCTAssertNotNil(Mascot.wobble.glassBounds)
        for mascot in [Mascot.bloop, .boo, .flit, .gourd, .rattle] {
            XCTAssertNil(mascot.glassBounds,
                         "\(mascot.name) has no visor and should have no glass")
        }
    }

    /// A glass sweep on a character with no glass draws nothing at all, which
    /// is a character that stops moving in exactly the state that is supposed
    /// to show the app working.
    func testNobodyWithoutGlassIsGivenAGlassSweep() {
        for mascot in Mascot.all where mascot.glassBounds == nil {
            XCTAssertFalse([SweepKind.visor, .hud].contains(mascot.sweep),
                           "\(mascot.name) sweeps glass it does not have")
        }
    }

    /// Every sweep is somebody's. One nobody uses is dead code that still has
    /// to be kept working.
    func testEveryCharacterSweepsAndEverySweepIsUsed() {
        let used = Set(Mascot.all.map(\.sweep))
        for kind in [SweepKind.visor, .hud, .beam, .psi, .wisp, .echo, .flicker, .marrow] {
            XCTAssertTrue(used.contains(kind), "\(kind) belongs to nobody")
        }
    }

    /// The test that should have existed first. Deriving the sweep axis from
    /// the glass collapsed Scoot's downward helmet scan and Wobble's
    /// searchlight into Blip's beam-across, because all three have a visor
    /// wider than it is tall — and nothing failed, because "a sweep happened"
    /// was all anything checked.
    func testEachCharacterSweepsOnItsOwnAxis() {
        func litCentre(_ m: Mascot, _ frame: Int) -> (x: Double, y: Double)? {
            let g = m.frame(eyes: .open, frame: frame, sweeping: true)
            let pts = g.litPoints.filter {
                let s = g[$0.x, $0.y]
                return s == .accentMid || s == .accentDim
            }
            guard !pts.isEmpty else { return nil }
            return (pts.reduce(0.0) { $0 + Double($1.x) } / Double(pts.count),
                    pts.reduce(0.0) { $0 + Double($1.y) } / Double(pts.count))
        }
        func travel(_ m: Mascot) -> (x: Double, y: Double) {
            let samples = (0..<18).compactMap { litCentre(m, $0) }
            let xs = samples.map(\.x), ys = samples.map(\.y)
            return ((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
        }
        let blip = travel(.blip)
        XCTAssertGreaterThan(blip.x, blip.y * 2, "Blip's beam should cross, not descend")

        let scoot = travel(.scoot)
        XCTAssertGreaterThan(scoot.y, scoot.x * 2, "Scoot's beam should descend, not cross")

        // The searchlight swings, so its centre moves sideways well below the
        // hull rather than inside the canopy.
        let wobbleFrames = (0..<30).map { Mascot.wobble.frame(eyes: .open, frame: $0, sweeping: true) }
        let beamRows = wobbleFrames.flatMap { g in
            g.litPoints.filter { g[$0.x, $0.y] == .accentMid || g[$0.x, $0.y] == .accentDim }.map(\.y)
        }
        XCTAssertGreaterThan(beamRows.max() ?? 0, 40,
                             "the searchlight should reach well below the saucer")
        XCTAssertGreaterThan(travel(.wobble).x, 2, "the searchlight should swing")
    }

    /// The same question for the October four, asked of whatever the sweep
    /// *changed* rather than of accent cells alone: three of these four are
    /// rendered mostly in the character's own chassis tones, and an
    /// accent-only measurement calls that nothing. This is the test that
    /// catches two sweeps quietly becoming one.
    func testTheOctoberSweepsAreEachTheirOwnThing() {
        func changed(_ m: Mascot, _ frame: Int) -> [Point] {
            let plain = m.frame(eyes: .open, frame: frame, sweeping: false)
            let swept = m.frame(eyes: .open, frame: frame, sweeping: true)
            return swept.litPoints.filter { swept[$0.x, $0.y] != plain[$0.x, $0.y] }
                + plain.litPoints.filter { swept[$0.x, $0.y] != plain[$0.x, $0.y] }
        }
        func centres(_ m: Mascot, _ frames: Range<Int>) -> [(x: Double, y: Double)] {
            frames.compactMap { frame in
                let pts = changed(m, frame)
                guard !pts.isEmpty else { return nil }
                return (pts.reduce(0.0) { $0 + Double($1.x) } / Double(pts.count),
                        pts.reduce(0.0) { $0 + Double($1.y) } / Double(pts.count))
            }
        }
        func travel(_ m: Mascot, _ frames: Range<Int>) -> (x: Double, y: Double) {
            let s = centres(m, frames)
            let xs = s.map(\.x), ys = s.map(\.y)
            return ((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
        }

        // Boo shimmers up the body: a long vertical travel, almost no lateral.
        let boo = travel(.boo, 0..<44)
        XCTAssertGreaterThan(boo.y, 12, "Boo's shimmer should climb him")
        XCTAssertGreaterThan(boo.y, boo.x * 3, "Boo's shimmer should not cross him")

        // Rattle steps down the same axis, which is what makes the direction
        // the thing that tells them apart.
        let rattle = travel(.rattle, 0..<18)
        XCTAssertGreaterThan(rattle.y, 8, "Rattle's pulse should run down him")
        XCTAssertGreaterThan(rattle.y, rattle.x * 3, "Rattle's pulse should not cross him")

        // And they run opposite ways, which is the only thing that tells the
        // two vertical sweeps apart. Boo is sampled from frame 3, past the
        // point where his wrapped trail is still hanging at the far end: the
        // wrap puts mass at both ends of him at once, and a centre measured
        // across it describes neither band.
        let booRun = centres(.boo, 3..<22).map(\.y)
        let rattleRun = centres(.rattle, 0..<9).map(\.y)
        XCTAssertGreaterThan(booRun.first ?? 0, booRun.last ?? 0, "Boo rises")
        XCTAssertLessThan(rattleRun.first ?? 0, rattleRun.last ?? 0, "Rattle descends")

        // Gourd does not travel at all: he is lit from inside, so the whole
        // carving pulses in place. A travelling centre here would mean the
        // candle had turned into somebody else's beam.
        let gourd = travel(.gourd, 0..<12)
        XCTAssertLessThan(gourd.x, 3, "the candle should not wander sideways")
        XCTAssertLessThan(gourd.y, 3, "the candle should not wander up or down")

        // Flit throws his arcs clear of the body, well below it.
        let reach = (0..<15).flatMap { changed(.flit, $0).map(\.y) }
        XCTAssertGreaterThan(reach.max() ?? 0, 40,
                             "the sonar should carry past his feet")
    }

    /// Rattle's pulse stops on each bone rather than sliding past them, which
    /// is the whole difference between his sweep and Boo's. Stated as "the
    /// same frame comes round twice in a row", because that is what a held
    /// stop is and a smooth slide never does it.
    func testTheSkeletonsPulseStepsRatherThanSlides() {
        let frames = (0..<18).map { Mascot.rattle.frame(eyes: .open, frame: $0, sweeping: true) }
        let held = zip(frames, frames.dropFirst()).filter { $0 == $1 }.count
        XCTAssertGreaterThan(held, 5, "the pulse is sliding, not stepping")
        XCTAssertLessThan(held, 17, "the pulse is not moving at all")
    }

    /// The rings expand. Checked as growth over time rather than as a shape,
    /// because he fills his own silhouette and most of a ring is rendered in
    /// his surface rather than in empty space.
    func testTheAlienRingsExpand() {
        func spread(_ frame: Int) -> Int {
            let plain = Mascot.bloop.frame(eyes: .open, frame: frame, sweeping: false)
            let swept = Mascot.bloop.frame(eyes: .open, frame: frame, sweeping: true)
            var touched: [Int] = []
            for y in 0..<swept.height {
                for x in 0..<swept.width where swept[x, y] != plain[x, y] {
                    touched.append(abs(x - swept.width / 2))
                }
            }
            return touched.max() ?? 0
        }
        let reach = (0..<26).map(spread)
        XCTAssertGreaterThan(reach.max() ?? 0, 18, "the rings never get far from him")
        XCTAssertNotEqual(reach.min(), reach.max(), "the rings are not expanding at all")
    }

    /// The mood has to survive the ripple: it may brighten his chassis, but
    /// it must never bury the tell that carries the tint.
    func testTheRippleNeverBuriesTheTell() {
        for frame in 0..<26 {
            let swept = Mascot.bloop.frame(eyes: .open, frame: frame, sweeping: true)
            let tinted = swept.litPoints.filter {
                switch swept[$0.x, $0.y] {
                case .accent, .accentMid, .accentDim, .light: return true
                default: return false
                }
            }
            XCTAssertFalse(tinted.isEmpty, "frame \(frame) has no tell left")
        }
    }

    /// A real radar beam turns one way and never stops. The first version of
    /// this wrapped badly and left a four-frame hole at the end of every
    /// cycle, which reads as the app having died rather than as it watching.
    ///
    /// Stated as "the sweep changed something" rather than "an accent pixel
    /// exists": the alien's ripple is rendered in his own chassis tones for
    /// most of its life, and an accent-only check called that nothing.
    func testTheSweepNeverLeavesAFrameWithoutMotion() {
        for mascot in Mascot.all {
            for frame in 0..<60 {
                let plain = mascot.frame(eyes: .open, frame: frame, sweeping: false)
                let swept = mascot.frame(eyes: .open, frame: frame, sweeping: true)
                XCTAssertNotEqual(plain, swept,
                                  "\(mascot.name) is not sweeping on frame \(frame)")
            }
        }
    }

    /// The sweep belongs to the blue states and nothing else: blue is the app
    /// looking, and green, amber and red are all outcomes. A beam crossing a
    /// character that is trying to report a problem makes the state you must
    /// notice look like the one you can ignore.
    func testOnlyTheBlueStatesSweep() {
        for mood in Mood.allCases {
            XCTAssertEqual(mood.style.sweeps, mood.style.health == .running, "\(mood)")
        }
        XCTAssertTrue(Mood.idle.style.sweeps, "watching a clear queue is a sweep")
        XCTAssertTrue(Mood.working.style.sweeps, "a refresh is literally a scan")
        for mood in [Mood.asleep, .nudging, .alarmed, .proud, .lost] {
            XCTAssertFalse(mood.style.sweeps, "\(mood) is an outcome, not a look")
        }
        // A reaction borrows the mood's tint, so a hand on a badge mid-refresh
        // keeps sweeping and one on an alarmed badge does not.
        XCTAssertTrue(Reaction.held.style(tint: .running).sweeps)
        XCTAssertFalse(Reaction.held.style(tint: .bad).sweeps)
    }

    // MARK: - Halo

    /// Every halo cell is empty in the source and touches something lit, and
    /// nothing lit is left without a halo cell beside it.
    func testHaloSurroundsTheSilhouette() {
        for mascot in Mascot.all {
            let sprite = mascot.sprite
            let halo = sprite.halo()
            XCTAssertFalse(halo.isEmpty, "\(mascot.name) has no halo")
            for point in halo {
                XCTAssertNil(sprite[point.x, point.y],
                             "\(mascot.name) halo overlaps a lit pixel at \(point)")
                let touches = (-1...1).contains { dy in
                    (-1...1).contains { dx in sprite[point.x + dx, point.y + dy] != nil }
                }
                XCTAssertTrue(touches, "\(mascot.name) halo floats free at \(point)")
            }
            // The top-left lit pixel must have a halo cell diagonally outside it.
            for y in 0..<sprite.height {
                for x in 0..<sprite.width where sprite[x, y] != nil {
                    let exposed = (-1...1).flatMap { dy in
                        (-1...1).map { dx in Point(x + dx, y + dy) }
                    }.filter { sprite[$0.x, $0.y] == nil }
                    for neighbour in exposed {
                        XCTAssertTrue(halo.contains(neighbour),
                                      "\(mascot.name) missing halo at \(neighbour)")
                    }
                }
            }
        }
    }

    // MARK: - Counters

    func testCounterCapMatchesTheBadge() {
        XCTAssertEqual(Counter.text(for: 7), "7")
        XCTAssertEqual(Counter.text(for: 99), "99")
        XCTAssertEqual(Counter.text(for: 100), "99+")
        XCTAssertEqual(Counter.text(for: 4_000), "99+")
    }

    func testChipGrowsWithTheNumberRatherThanShrinkingTheDigits() {
        let one = Counter.chip("7"), two = Counter.chip("12"), three = Counter.chip("99+")
        XCTAssertEqual(one.width, 7)
        XCTAssertEqual(two.width, 11)
        XCTAssertEqual(three.width, 15)
        for chip in [one, two, three] {
            XCTAssertEqual(chip.height, Counter.height)
            // Corners knocked out, so it reads as a chip and not a brick.
            XCTAssertNil(chip[0, 0])
            XCTAssertNil(chip[chip.width - 1, chip.height - 1])
        }
    }

    func testEveryDigitHasAGlyph() {
        for character in "0123456789+" {
            let glyph = PixelFont.glyphs[character]
            XCTAssertNotNil(glyph, "no glyph for \(character)")
            XCTAssertEqual(glyph?.count, PixelFont.digitHeight)
            XCTAssertEqual(glyph?.allSatisfy { $0.count == PixelFont.digitWidth }, true)
        }
    }

    // MARK: - Scale

    /// One source pixel must cover a whole number of device pixels, or the art
    /// stops being pixel art.
    func testScaleSnapsToTheBackingStoreNotThePointGrid() {
        for backing in [CGFloat(1), 2, 3] {
            for tile in stride(from: CGFloat(28), through: 80, by: 1) {
                let scale = SpriteScale.snapped(targetPoints: tile, spriteWidth: 18,
                                                backingScale: backing, minimum: 1)
                let devicePixels = scale * backing
                XCTAssertEqual(devicePixels, devicePixels.rounded(), accuracy: 0.0001,
                               "tile \(tile) at \(backing)x gave \(scale)")
            }
        }
    }

    /// Why the corner drag does not run on the snapped ladder.
    ///
    /// The rungs are `cells / backingScale` points apart, so a 54-cell badge
    /// on a 1x screen can only rest at 54 and 108 inside its own 28...128
    /// bounds — two sizes. Dragging a corner along that does nothing and then
    /// jumps the whole way. If this ever stops being true the drag could go
    /// back on the ladder; while it is true, it cannot.
    func testTheCrispLadderIsTooCoarseToDragOn() {
        let cells = 54, floor = CGFloat(10) / 21
        let rungs = Set(stride(from: CGFloat(28), through: 128, by: 0.5).map {
            (CGFloat(cells) * SpriteScale.snapped(targetPoints: $0, spriteWidth: cells,
                                                  backingScale: 1, minimum: floor)).rounded()
        })
        XCTAssertLessThanOrEqual(rungs.count, 3,
                                 "the 1x ladder has \(rungs.count) rungs: \(rungs.sorted())")
    }

    /// The drag scale tracks the pointer exactly, which is the whole point of
    /// it — a size asked for is the size drawn.
    func testAContinuousScaleTracksWhatWasAskedFor() {
        for points in stride(from: CGFloat(30), through: 128, by: 0.5) {
            // Below the floor it is the floor that answers, which is the next
            // test; this one is about what happens above it.
            let scale = SpriteScale.continuous(targetPoints: points,
                                               spriteWidth: 54, minimum: 0.1)
            XCTAssertEqual(CGFloat(54) * scale, points, accuracy: 0.0001)
        }
    }

    /// It comes off the pixel grid, not off the floor: the counter's digits
    /// stop being a number below a certain size whether or not a drag is in
    /// progress.
    func testAContinuousScaleStillHonoursItsFloor() {
        let floor: CGFloat = 0.8
        XCTAssertEqual(SpriteScale.continuous(targetPoints: 10, spriteWidth: 54,
                                              minimum: floor), floor)
        XCTAssertGreaterThanOrEqual(
            SpriteScale.continuous(targetPoints: 1, spriteWidth: 54, minimum: floor), floor)
        XCTAssertEqual(SpriteScale.continuous(targetPoints: 100, spriteWidth: 0,
                                              minimum: floor), floor)
    }

    /// And the two are genuinely different things: only the snapped one lands
    /// on whole device pixels. A `continuous` that happened to snap would mean
    /// the drag was still on the ladder and nothing had been fixed.
    func testOnlyTheSnappedScaleLandsOnWholeDevicePixels() {
        var offGrid = 0
        for points in stride(from: CGFloat(30), through: 128, by: 1) {
            for backing in [CGFloat(1), 2] {
                let crisp = SpriteScale.snapped(targetPoints: points, spriteWidth: 54,
                                                backingScale: backing, minimum: 0.5)
                let devicePixels = crisp * backing
                XCTAssertEqual(devicePixels, devicePixels.rounded(), accuracy: 0.0001,
                               "snapped \(points) at \(backing)x")

                let loose = SpriteScale.continuous(targetPoints: points, spriteWidth: 54,
                                                   minimum: 0.5) * backing
                if abs(loose - loose.rounded()) > 0.0001 { offGrid += 1 }
            }
        }
        XCTAssertGreaterThan(offGrid, 100,
                             "the drag scale is snapping, so the drag is still stepping")
    }

    func testScaleHonoursItsFloor() {
        // The 3x5 digits stop being a number below 2x, whatever the Dock does.
        let tiny = SpriteScale.snapped(targetPoints: 28, spriteWidth: 18,
                                       backingScale: 2, minimum: 2)
        XCTAssertGreaterThanOrEqual(tiny, 2)
    }
}

/// Reads digits back out of a rendered chip. A font that is subtly wrong looks
/// like a rendering bug for a long time before anyone counts the pixels.
final class CounterGlyphTests: XCTestCase {

    private func readDigits(_ text: String) -> [[String]] {
        let chip = Counter.chip(text)
        return text.enumerated().map { index, _ in
            (0..<PixelFont.digitHeight).map { y in
                String((0..<PixelFont.digitWidth).map { x in
                    chip[2 + index * 4 + x, y + 1] == .light ? "1" : "0"
                })
            }
        }
    }

    func testEveryDigitLandsWhereTheFontSaysItShould() {
        for (character, glyph) in PixelFont.glyphs {
            XCTAssertEqual(readDigits(String(character)).first, glyph,
                           "glyph for \(character) is misplaced in the chip")
        }
    }

    func testMultiDigitChipsKeepTheirOrderAndSpacing() {
        XCTAssertEqual(readDigits("12"), [PixelFont.glyphs["1"]!, PixelFont.glyphs["2"]!])
        XCTAssertEqual(readDigits("99+"),
                       [PixelFont.glyphs["9"]!, PixelFont.glyphs["9"]!, PixelFont.glyphs["+"]!])
        // One blank column between digits, so they never run together.
        let chip = Counter.chip("99")
        for y in 1..<(Counter.height - 1) {
            XCTAssertNotEqual(chip[5, y], .light, "digits are touching at row \(y)")
        }
    }
}

final class MascotCycleTests: XCTestCase {

    let everyone = MascotID.allCases

    /// The regression this exists for: clicking one past the last character
    /// used to land on "off" and stop, because the off state drew inert art
    /// instead of a button. Off is a stop on the loop, not the end of it.
    func testCyclingWrapsAllTheWayRound() {
        var seen: [MascotID?] = []
        var current: MascotID? = everyone.first
        for _ in 0...everyone.count {
            seen.append(current)
            current = MascotID.next(after: current)
        }
        XCTAssertEqual(seen, everyone.map { $0 } + [nil])
        XCTAssertEqual(current, everyone.first,
                       "cycling out of off has to lead back to the first character")
    }

    func testCyclingVisitsEveryCharacterExactlyOncePerLap() {
        var current: MascotID? = nil
        var lap: [MascotID?] = []
        for _ in 0..<(everyone.count + 1) {
            current = MascotID.next(after: current)
            lap.append(current)
        }
        XCTAssertEqual(Set(lap.compactMap { $0 }), Set(everyone))
        XCTAssertEqual(lap.filter { $0 == nil }.count, 1, "off should come round once")
    }

    /// An id written by an older build must not silently turn the mascot off.
    func testUnknownIdIsNotTreatedAsOff() {
        XCTAssertNil(MascotID(rawValue: "sprocket"))
        XCTAssertEqual(MascotID.next(after: nil), everyone.first)
    }

    // MARK: - Which shelf each one sits on

    /// `.custom` is the default so a fork keeps compiling, which means nothing
    /// in the type system stops a *built-in* character forgetting to say where
    /// it goes — it would just turn up in somebody's personal row. This is the
    /// only thing that catches that.
    func testEveryBuiltInMascotDeclaresItsSection() {
        for mascot in Mascot.all {
            XCTAssertNotEqual(mascot.cohort, .custom,
                              "\(mascot.name) ships with the app but claims no shelf")
        }
    }

    func testTheShelvesHoldWhoTheySay() {
        XCTAssertEqual(Mascot.cohort(.og).map(\.id), [.pip, .byte, .widget, .nimbus])
        XCTAssertEqual(Mascot.cohort(.space).map(\.id), [.blip, .scoot, .wobble, .bloop])
        XCTAssertEqual(Mascot.cohort(.october2026).map(\.id), [.boo, .flit, .gourd, .rattle])
        XCTAssertTrue(Mascot.cohort(.custom).isEmpty, "this build ships nobody's fork")
    }

    /// The guarantee the whole `.custom` default exists for, written as the
    /// call a fork actually makes: the argument list this type had before the
    /// room did, with no `cohort:` and no `bobScale:`. If this stops
    /// compiling, so does every fork that ever added a character.
    func testAForksCallShapeStillCompilesAndLandsOnItsOwnShelf() {
        let theirs = Mascot(
            id: .blip, name: "Theirs", tellName: "a lamp", blurb: "Not ours.",
            sprite: Mascot.blip.sprite, eyes: Mascot.blip.eyes, eyeSize: 6,
            eyeInk: .accent, sweep: .flicker, ramp: .fallback, headRows: 30)
        XCTAssertEqual(theirs.cohort, .custom, "a fork's character has to have a home")
        XCTAssertEqual(theirs.bobScale, 1, "and something to stand on")
    }

    /// `tic` tolerates a character it does not know, so a fork compiles — but
    /// nobody the app ships should be relying on that. A built-in with no
    /// idle is a character that holds perfectly still whenever the sweep is
    /// off, which is every state except the two blue ones.
    func testEveryBuiltInMascotHasAnIdleOfItsOwn() {
        for mascot in Mascot.all {
            let still = mascot.frame(eyes: .open, frame: 0, sweeping: false)
            let moved = (1..<12).contains {
                mascot.frame(eyes: .open, frame: $0, sweeping: false) != still
            }
            XCTAssertTrue(moved, "\(mascot.name) never moves with the sweep off")
        }
    }

    /// The room lays the cast out four to a row, so a shelf that is not a
    /// multiple of four leaves a ragged last line.
    func testEveryShelfFillsWholeRows() {
        for cohort in MascotCohort.ordered where cohort != .custom {
            XCTAssertEqual(Mascot.cohort(cohort).count % 4, 0,
                           "\(cohort) has \(Mascot.cohort(cohort).count)")
        }
    }

    /// Cast order and shelf order are the same walk, so clicking the mascot
    /// moves through the room left to right, top to bottom.
    func testCastOrderMatchesTheRoomsOrder() {
        XCTAssertEqual(Mascot.all.map(\.id),
                       MascotCohort.ordered.flatMap { Mascot.cohort($0).map(\.id) })
        XCTAssertEqual(Mascot.all.map(\.id), MascotID.allCases)
    }

    /// Every built-in shelf has a heading; the custom one deliberately has
    /// none, because the room titles it with whoever is signed in.
    func testOnlyTheCustomShelfBorrowsItsTitle() {
        for cohort in MascotCohort.ordered {
            XCTAssertEqual(cohort.title == nil, cohort == .custom, "\(cohort)")
        }
    }
}
