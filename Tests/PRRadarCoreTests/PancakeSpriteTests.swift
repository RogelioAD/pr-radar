import XCTest
@testable import PRRadarCore

/// The art is data, so its invariants are assertions rather than a careful look
/// at a screenshot — the same bargain `MascotTests` makes.
final class PancakeSpriteTests: XCTestCase {

    // MARK: - Height carries the meaning

    /// The whole point of the marker: one more pancake per PR below this one.
    func testEachPancakeAddsAFixedNumberOfRows() {
        let one = Pancakes.stack(of: 1)
        for depth in 2...Pancakes.maxDrawn {
            XCTAssertEqual(Pancakes.stack(of: depth).height,
                           one.height + (depth - 1) * Pancakes.pancakeRows,
                           "a stack of \(depth)")
        }
    }

    /// Width is fixed, so a column of markers of different depths lines up
    /// rather than stepping sideways.
    func testWidthIsTheSameAtEveryDepth() {
        for depth in 1...Pancakes.maxDrawn {
            XCTAssertEqual(Pancakes.stack(of: depth).width, Pancakes.width)
        }
    }

    /// Beyond the cap the marker would be taller than the row carrying it.
    func testDepthIsCappedRatherThanGrowingForever() {
        XCTAssertEqual(Pancakes.stack(of: 40).height,
                       Pancakes.stack(of: Pancakes.maxDrawn).height)
    }

    /// Nonsense in, something drawable out: a stack of zero is still a row's
    /// marker, not an empty sprite `Sprite.init` would trap on.
    func testZeroAndNegativeDepthsDrawOnePancake() {
        XCTAssertEqual(Pancakes.stack(of: 0).height, Pancakes.stack(of: 1).height)
        XCTAssertEqual(Pancakes.stack(of: -3).height, Pancakes.stack(of: 1).height)
    }

    // MARK: - Shape

    /// The plate is the last rows, so markers of different depths share a
    /// baseline and the difference between them reads as height.
    func testPlateIsAtTheBottom() {
        for depth in [1, 3, Pancakes.maxDrawn] {
            let sprite = Pancakes.stack(of: depth)
            let rim = sprite.height - Pancakes.plateRows
            XCTAssertEqual(sprite[0, rim], .outline, "plate rim ends at depth \(depth)")
            XCTAssertEqual(sprite[sprite.width - 1, rim], .outline)
            XCTAssertEqual(sprite[1, rim], .light, "plate rim fill")
            XCTAssertEqual(sprite[1, sprite.height - 1], .outline, "plate foot")
        }
    }

    /// Syrup is a garnish, not a layer. A stack of one has to be one whole
    /// pancake with syrup on it — if the syrup counted, the base of every stack
    /// would be the one member drawn as something other than a pancake.
    func testSyrupIsAGarnishRatherThanAPancake() {
        let sprite = Pancakes.stack(of: 1)
        XCTAssertEqual(sprite[4, 1], .syrup, "the syrup, on top")
        XCTAssertNil(sprite[1, 1], "and narrower than the pancakes under it")
        XCTAssertEqual(sprite[4, 3], .batter, "a whole pancake beneath it")
        XCTAssertEqual(sprite[1, 3], .outline, "full width, like every other")

        // Every pancake is identical; only the syrup sits above them.
        let three = Pancakes.stack(of: 3)
        for pancake in 0..<3 {
            let body = Pancakes.syrupRows + pancake * Pancakes.pancakeRows + 1
            XCTAssertEqual(three[4, body], .batter, "pancake \(pancake)")
            XCTAssertEqual(three[1, body], .outline, "pancake \(pancake) is full width")
        }
    }

    /// One row of syrup however deep the stack, so the glaze never grows into
    /// something that could be miscounted.
    func testGlazeIsTheSameWhateverTheDepth() {
        let one = Pancakes.stack(of: 1).cells.filter { $0 == .syrup }.count
        XCTAssertGreaterThan(one, 0)
        for depth in 2...Pancakes.maxDrawn {
            XCTAssertEqual(Pancakes.stack(of: depth).cells.filter { $0 == .syrup }.count,
                           one, "a stack of \(depth) carries no extra syrup")
        }
        XCTAssertEqual(Pancakes.stack(of: 4).cells.filter { $0 == .syrup }.count,
                       Pancakes.stack(of: 1).cells.filter { $0 == .syrup }.count)
    }



    // MARK: - Halo

    /// The invariant a new sprite fails most easily: an interior hole or a
    /// detached pixel. Mirrors `MascotTests.testHaloSurroundsTheSilhouette`.
    func testHaloSurroundsTheSilhouetteWithoutOverlappingIt() {
        let sprite = Pancakes.stack(of: 4)
        let halo = sprite.halo()
        XCTAssertFalse(halo.isEmpty)
        for point in halo {
            XCTAssertNil(sprite[point.x, point.y], "halo must not sit on a lit pixel")
            let touches = (-1...1).contains { dy in
                (-1...1).contains { dx in sprite[point.x + dx, point.y + dy] != nil }
            }
            XCTAssertTrue(touches, "halo must not float free of the art")
        }
    }

    // MARK: - Layouts

    /// `SpriteCanvas` draws layouts, and `Layer`'s init is internal — so the
    /// factories are the only way the app can draw these at all.
    func testLayoutsReportTheSpriteTheyCarry() {
        let layout = SpriteLayout.pancakeStack(of: 3)
        let sprite = Pancakes.stack(of: 3)
        XCTAssertEqual(layout.width, sprite.width)
        XCTAssertEqual(layout.height, sprite.height)
        XCTAssertEqual(layout.layers.count, 1)
        // The invariant every composition has to satisfy: nothing outside the
        // bounds it reports.
        for layer in layout.layers {
            XCTAssertGreaterThanOrEqual(layer.origin.x, 0)
            XCTAssertGreaterThanOrEqual(layer.origin.y, 0)
            XCTAssertLessThanOrEqual(layer.origin.x + layer.sprite.width, layout.width)
            XCTAssertLessThanOrEqual(layer.origin.y + layer.sprite.height, layout.height)
        }
    }

    /// Batter and syrup are the only slots with a hue of their own, and unlike
    /// `accent` they must not move with the mood.
    func testBatterAndSyrupAreFixedColoursInBothAppearances() {
        for slot in [Slot.batter, Slot.syrup] {
            let light = SpritePalette.color(for: slot, dark: false)
            let dark = SpritePalette.color(for: slot, dark: true)
            XCTAssertGreaterThan(light.red, light.blue, "\(slot) should read warm")
            XCTAssertGreaterThan(dark.red, dark.blue)
        }
    }
}
