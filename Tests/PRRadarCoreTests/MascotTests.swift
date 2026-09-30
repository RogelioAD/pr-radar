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

    /// Only the two with nothing under them.
    func testTheFloatersBobFurther() {
        XCTAssertEqual(Mascot.scoot.bobScale, 2)
        XCTAssertEqual(Mascot.wobble.bobScale, 2)
        XCTAssertEqual(Mascot.blip.bobScale, 1)
        XCTAssertEqual(Mascot.bloop.bobScale, 1)
    }

    // MARK: - The sweep

    /// Three of them have glass for a beam to cross. The alien does not, and
    /// pulses instead — the branch exists precisely because he is the
    /// exception.
    func testGlassIsFoundOnTheThreeThatHaveIt() {
        XCTAssertNotNil(Mascot.blip.glassBounds)
        XCTAssertNotNil(Mascot.scoot.glassBounds)
        XCTAssertNotNil(Mascot.wobble.glassBounds)
        XCTAssertNil(Mascot.bloop.glassBounds,
                     "the one with no visor is supposed to have no glass")
    }

    /// A real radar beam turns one way and never stops. The first version of
    /// this wrapped badly and left a four-frame hole at the end of every
    /// cycle, which reads as the app having died rather than as it watching.
    func testTheSweepNeverLeavesAFrameWithoutABeam() {
        for mascot in [Mascot.blip, .scoot, .wobble] {
            for frame in 0..<60 {
                let lit = mascot.frame(eyes: .open, frame: frame, sweeping: true)
                let beamed = lit.litPoints.contains {
                    let slot = lit[$0.x, $0.y]
                    return slot == .accentMid || slot == .accentDim
                }
                XCTAssertTrue(beamed, "\(mascot.name) has no beam on frame \(frame)")
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

    /// The regression this exists for: clicking one past the last character
    /// used to land on "off" and stop, because the off state drew inert art
    /// instead of a button. Off is a stop on the loop, not the end of it.
    func testCyclingWrapsAllTheWayRound() {
        var seen: [MascotID?] = []
        var current: MascotID? = MascotID.allCases.first
        for _ in 0...MascotID.allCases.count {
            seen.append(current)
            current = MascotID.next(after: current)
        }
        XCTAssertEqual(seen, MascotID.allCases.map { $0 } + [nil])
        XCTAssertEqual(current, MascotID.allCases.first,
                       "cycling out of off has to lead back to the first character")
    }

    func testCyclingVisitsEveryCharacterExactlyOncePerLap() {
        var current: MascotID? = nil
        var lap: [MascotID?] = []
        for _ in 0..<(MascotID.allCases.count + 1) {
            current = MascotID.next(after: current)
            lap.append(current)
        }
        XCTAssertEqual(Set(lap.compactMap { $0 }), Set(MascotID.allCases))
        XCTAssertEqual(lap.filter { $0 == nil }.count, 1, "off should come round once")
    }

    /// An id written by an older build must not silently turn the mascot off.
    func testUnknownIdIsNotTreatedAsOff() {
        XCTAssertNil(MascotID(rawValue: "sprocket"))
        XCTAssertEqual(MascotID.next(after: nil), MascotID.allCases.first)
    }
}
