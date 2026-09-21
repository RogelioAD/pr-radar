import XCTest
@testable import PRRadarCore

/// The banner is the one place this app writes words in pixels, so the font's
/// invariants are assertions rather than a careful look at a screenshot.
final class BannerFontTests: XCTestCase {

    // MARK: - The grid

    /// Every glyph is exactly 5x7, or a word drawn from them would jag.
    /// `Sprite.init` traps on rows of unequal width, so a bad glyph is a crash
    /// at first draw — this catches it at `swift test` instead.
    func testEveryGlyphIsFiveBySeven() {
        for (character, rows) in BannerFont.glyphs {
            XCTAssertEqual(rows.count, BannerFont.height, "'\(character)' row count")
            for row in rows {
                XCTAssertEqual(row.count, BannerFont.width, "'\(character)' row width")
            }
        }
    }

    /// Masks, not slot characters: the caller picks the colour, because the
    /// banner draws one line green and the next white.
    func testGlyphsAreMasks() {
        for (character, rows) in BannerFont.glyphs {
            for row in rows {
                XCTAssertTrue(row.allSatisfy { $0 == "1" || $0 == "." },
                              "'\(character)' should be a mask")
            }
        }
    }

    /// The alphabet the banner actually needs. A missing letter draws as a
    /// gap, which is the kind of thing nobody notices until it ships — and
    /// the banner now says any of thirty trophy names rather than one fixed
    /// line, so the whole roster is the alphabet.
    func testEveryLetterTheBannerUsesExists() {
        var wanted = Achievement.headline + Achievement.manyTitle(12)
        wanted += Trophy.all.map(\.name).joined()
        for character in wanted.uppercased() {
            XCTAssertNotNil(BannerFont.glyphs[character],
                            "no glyph for '\(character)'")
        }
    }

    // MARK: - Rendering

    func testWidthCountsTrackingBetweenLettersOnly() {
        XCTAssertEqual(BannerFont.width(of: "A"), 5, "no tracking after the last letter")
        XCTAssertEqual(BannerFont.width(of: "AB"), 11)
        XCTAssertEqual(BannerFont.width(of: ""), 0)
        XCTAssertEqual(BannerFont.render("HI", slot: .light).width,
                       BannerFont.width(of: "HI"))
    }

    func testRenderedTextIsOneRowTall() {
        XCTAssertEqual(BannerFont.render("CLEARED", slot: .light).height, BannerFont.height)
    }

    /// Lowercase input draws the uppercase glyph rather than nothing, so a
    /// caller that forgets to shout still gets words.
    func testTextIsUppercased() {
        XCTAssertEqual(BannerFont.render("ab", slot: .light).cells,
                       BannerFont.render("AB", slot: .light).cells)
    }

    /// The caller's slot is what lands on the grid — that is the whole point of
    /// masks.
    func testEveryLitPixelTakesTheGivenSlot() {
        for slot in [Slot.light, .accent, .syrup] {
            let sprite = BannerFont.render("REVIEWS", slot: slot)
            XCTAssertFalse(sprite.litPoints.isEmpty)
            XCTAssertTrue(sprite.litPoints.allSatisfy { sprite[$0.x, $0.y] == slot },
                          "\(slot)")
        }
    }

    /// A banner is decoration. A character the font has never heard of should
    /// cost a gap in a word, not the app.
    func testUnknownCharactersDrawAsSpaceRatherThanTrapping() {
        let sprite = BannerFont.render("A@B", slot: .light)
        XCTAssertEqual(sprite.width, BannerFont.width(of: "A@B"))
        // The middle cell is blank, but the letters either side still landed.
        XCTAssertFalse(sprite.litPoints.isEmpty)
        XCTAssertEqual(sprite.litPoints.filter { $0.x >= 6 && $0.x <= 10 }.count, 0,
                       "the unknown glyph occupies its slot and draws nothing")
    }

    // MARK: - The emblem

    /// Bare on purpose: a star is mostly notches, and both an outline and a
    /// halo ring the silhouette and fill them in.
    func testEmblemIsSquareAndEntirelyAccent() {
        let star = Achievement.emblem
        XCTAssertEqual(star.width, star.height)
        XCTAssertTrue(star.litPoints.allSatisfy { star[$0.x, $0.y] == .accent })
    }

    /// Accent resolves to a live `Health`, and this one has to be the green the
    /// ready-to-merge count already uses — the banner must not invent a second
    /// idea of "clear".
    func testEmblemIsTintedWithTheSameGreenAsReadyToMerge() {
        let layout = SpriteLayout.achievementEmblem()
        XCTAssertEqual(layout.layers.count, 1)
        XCTAssertEqual(layout.layers[0].accent, .good)
    }

    // MARK: - Sizing to the screen

    /// What the sizing tests below measure. The original banner's pairing —
    /// the star and a title of typical length — so these keep testing the
    /// rule rather than whichever trophy happens to have the longest name.
    private var emblem: Sprite { Achievement.emblem }
    private var title: String { "REVIEWS CLEARED" }

    private func scale(_ width: CGFloat) -> CGFloat {
        Achievement.scale(forScreenWidth: width, emblem: emblem, title: title)
    }

    private func size(_ scale: CGFloat) -> CGSize {
        Achievement.size(emblem: emblem, title: title, scale: scale)
    }

    /// Whole scales only. A sprite is crisp when one source pixel covers a
    /// whole number of pixels, so the banner steps between sizes across screens
    /// rather than sliding.
    func testScaleIsAlwaysWholeAndInRange() {
        for width in stride(from: CGFloat(800), through: 6000, by: 40) {
            let chosen = scale(width)
            XCTAssertEqual(chosen, chosen.rounded(), "\(width)")
            XCTAssertGreaterThanOrEqual(chosen, Achievement.minimumScale)
            XCTAssertLessThanOrEqual(chosen, Achievement.maximumScale)
        }
    }

    /// A bigger screen never gets a smaller banner.
    func testScaleNeverShrinksAsTheScreenGrows() {
        var previous = scale(800)
        for width in stride(from: CGFloat(800), through: 6000, by: 40) {
            let chosen = scale(width)
            XCTAssertGreaterThanOrEqual(chosen, previous, "\(width)")
            previous = chosen
        }
    }

    /// The banner keeps to its share of the screen — unless it is already at
    /// the floor, where being readable outranks being small.
    func testBannerStaysWithinItsShareUnlessItIsAtTheFloor() {
        for width in stride(from: CGFloat(800), through: 6000, by: 40) {
            let chosen = scale(width)
            guard chosen > Achievement.minimumScale else { continue }
            XCTAssertLessThanOrEqual(size(chosen).width,
                                     width * Achievement.widthFraction, "\(width)")
        }
    }

    /// Going one step bigger would always break that share — otherwise the rule
    /// is leaving usable size on the table.
    func testTheChosenScaleIsTheLargestThatFits() {
        for width in stride(from: CGFloat(800), through: 6000, by: 40) {
            let chosen = scale(width)
            guard chosen < Achievement.maximumScale else { continue }
            XCTAssertGreaterThan(size(chosen + 1).width,
                                 width * Achievement.widthFraction, "\(width)")
        }
    }

    /// A narrow screen gets the floor rather than an unreadable fraction of a
    /// scale — a 5x7 capital at 1x is seven points tall.
    func testNarrowScreensGetTheFloorRatherThanSomethingUnreadable() {
        XCTAssertEqual(scale(640), Achievement.minimumScale)
        XCTAssertEqual(scale(1),
                       Achievement.minimumScale, "and nothing divides by a screen")
    }

    /// Every metric is a multiple of the one scale, so the banner grows in
    /// proportion rather than stretching.
    func testSizeGrowsInProportionWithTheScale() {
        let two = size(2)
        let four = size(4)
        XCTAssertGreaterThan(four.width, two.width)
        XCTAssertGreaterThan(four.height, two.height)
    }

    /// The header steps down from the title but never disappears.
    func testHeadlineSitsOneStepBelowTheTitleWithAFloor() {
        XCTAssertEqual(Achievement.headlineScale(3), 2)
        XCTAssertEqual(Achievement.headlineScale(2), 1)
        XCTAssertEqual(Achievement.headlineScale(1), 1, "never vanishes")
    }

    func testEmblemLayoutReportsTheSpriteItCarries() {
        let layout = SpriteLayout.achievementEmblem()
        XCTAssertEqual(layout.width, Achievement.emblem.width)
        XCTAssertEqual(layout.height, Achievement.emblem.height)
    }
}
