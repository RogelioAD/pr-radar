import XCTest
@testable import PRRadarCore

/// The art is data, so its invariants are assertions rather than a careful look
/// at a screenshot.
final class MascotTests: XCTestCase {

    func testEverySpriteIsSixteenSquare() {
        for mascot in Mascot.all {
            XCTAssertEqual(mascot.sprite.width, 16, "\(mascot.name) width")
            XCTAssertEqual(mascot.sprite.height, 16, "\(mascot.name) height")
        }
    }

    /// The reason a swap never shifts the layout around it.
    func testBustsShareAnIdenticalCollar() {
        let collar = Sprite(Mascot.collar)
        for mascot in [Mascot.pip, .byte, .widget] {
            for y in 0..<collar.height {
                for x in 0..<collar.width {
                    XCTAssertEqual(mascot.sprite[x, mascot.sprite.height - 4 + y],
                                   collar[x, y],
                                   "\(mascot.name) collar at (\(x), \(y))")
                }
            }
        }
    }

    /// The floater is the deliberate exception — no collar, so it can bob
    /// further and sit higher.
    func testFloaterHasNoCollarAndNoCrop() {
        XCTAssertEqual(Mascot.nimbus.headRows, Mascot.nimbus.sprite.height)
        XCTAssertEqual(Mascot.nimbus.bobScale, 2)
        let collar = Sprite(Mascot.collar)
        let bottomFour = (0..<collar.height).map { y in
            (0..<collar.width).map { x in Mascot.nimbus.sprite[x, 12 + y] }
        }
        let collarRows = (0..<collar.height).map { y in
            (0..<collar.width).map { x in collar[x, y] }
        }
        XCTAssertNotEqual(bottomFour, collarRows,
                          "the floater is supposed to be the one without a collar")
    }

    func testEyeBoxesAreInBoundsAndOnSkin() {
        for mascot in Mascot.all {
            for box in mascot.eyes {
                XCTAssertTrue(box.x >= 0 && box.y >= 0
                              && box.x + 2 <= mascot.sprite.width
                              && box.y + 2 <= mascot.sprite.height,
                              "\(mascot.name) eye box \(box) out of bounds")
                for dy in 0..<2 {
                    for dx in 0..<2 {
                        XCTAssertNotNil(mascot.sprite[box.x + dx, box.y + dy],
                                        "\(mascot.name) eye on a transparent pixel")
                    }
                }
            }
        }
    }

    /// A dark-eyed mascot loses the mood colour entirely without one, which is
    /// how two of these four ended up reading identically in the first pass.
    func testEveryMascotHasATellOutsideItsEyes() {
        for mascot in Mascot.all {
            XCTAssertFalse(mascot.tell.isEmpty, "\(mascot.name) has no tell")
            let inEye = { (point: Point) in
                mascot.eyes.contains { box in
                    (box.x..<box.x + 2).contains(point.x) && (box.y..<box.y + 2).contains(point.y)
                }
            }
            XCTAssertTrue(mascot.tell.contains { !inEye($0) },
                          "\(mascot.name)'s tell is entirely inside its eyes")
            for point in mascot.tell {
                XCTAssertNotNil(mascot.sprite[point.x, point.y],
                                "\(mascot.name) tell on a transparent pixel")
            }
        }
    }

    func testApplyingAMoodLightsTheTellAndRepaintsTheEyes() {
        let frame = Mascot.pip.frame(eyes: .shut)
        for point in Mascot.pip.tell {
            XCTAssertEqual(frame[point.x, point.y], .accent)
        }
        let box = Mascot.pip.eyes[0]
        XCTAssertEqual(frame[box.x, box.y], Mascot.pip.eyeOff,      // shut: top row dark
                       "shut eyes should clear the top row")
        XCTAssertEqual(frame[box.x, box.y + 1], Mascot.pip.eyeInk)
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
