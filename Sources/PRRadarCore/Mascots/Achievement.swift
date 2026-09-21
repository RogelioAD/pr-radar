import Foundation

/// The banner that drops in when a trophy is earned, and the arithmetic that
/// sizes it.
///
/// Green, because that is already this app's colour for *nothing is in your
/// way* — the same `Health.good` the ready-to-merge count wears, resolved from
/// `accent` rather than written down a second time.
///
/// It began as one hardcoded message for one achievement. Everything here now
/// takes the emblem and the title it is drawing, because thirty trophies have
/// thirty names of different lengths and a banner sized for the longest would
/// be a banner three times too wide for the shortest.
public enum Achievement {

    /// The standing line. Two lines, the way these have always been: a small
    /// header that never changes, and the thing you actually did.
    public static let headline = "ACHIEVEMENT UNLOCKED"

    /// What a burst of unlocks says instead of holding the screen one trophy
    /// at a time. See `AchievementBanner`.
    public static func manyTitle(_ count: Int) -> String {
        "\(count) TROPHIES"
    }

    /// A five-pointed star, the oldest badge there is.
    ///
    /// Drawn bare — no outline and no halo. Both ring the silhouette, and a
    /// star is mostly notches: filling them costs the shape the very thing that
    /// makes it a star. Green on a near-black banner needs neither.
    public static let emblem = Sprite([
        ".....a.....",
        "....aaa....",
        "....aaa....",
        "aaaaaaaaaaa",
        ".aaaaaaaaa.",
        "..aaaaaaa..",
        "..aaaaaaa..",
        ".aaa...aaa.",
        ".aa.....aa.",
        ".aa.....aa.",
        "aa.......aa",
    ])
}

extension Achievement {

    // MARK: - Size

    /// Everything about the banner is a multiple of the sprite scale, so it is
    /// one number that decides how big it is — and the screen decides that
    /// number.
    /// The white ring around the whole banner.
    ///
    /// The same bargain the badge's sprite halo makes, for the same reason:
    /// this arrives unannounced over a desktop the app is not allowed to look
    /// at, and a near-black card on somebody's dark wallpaper has no edge at
    /// all. Paired with the dark card inside it the outline carries both
    /// poles of contrast, so one static treatment survives any backdrop.
    ///
    /// One cell, like the sprite halo — so it scales with everything else and
    /// is never thinner than the green border it sits outside.
    public static let haloCells: CGFloat = 1

    public static let paddingCells: CGFloat = 6
    public static let gapCells: CGFloat = 5
    public static let lineGapCells: CGFloat = 2

    /// Never below 2: the font is 5x7, and at 1x a capital is seven points
    /// tall — a texture rather than a word.
    public static let minimumScale: CGFloat = 2
    /// Never above 4. Past that it stops being a banner and becomes a wall.
    public static let maximumScale: CGFloat = 4
    /// How much of the screen's width the banner may take. Small on purpose:
    /// it arrives uninvited, so it should be a nod rather than an interruption.
    public static let widthFraction: CGFloat = 0.12

    /// The standing header sits a step below the title, which carries the
    /// message — but never below 1, where it would vanish.
    public static func headlineScale(_ scale: CGFloat) -> CGFloat {
        max(1, scale - 1)
    }

    /// Height of the two lines of type together.
    public static func textHeight(scale: CGFloat) -> CGFloat {
        CGFloat(BannerFont.height) * (scale + headlineScale(scale))
            + lineGapCells * scale
    }

    /// The whole scale that brings an emblem to about the height of the type
    /// beside it.
    ///
    /// Derived rather than fixed, because the emblems are no longer one size.
    /// The star is 11 cells and a trophy is 32 — drawn at the text's own scale
    /// the star is right and the trophy is three times the height of the
    /// banner it is supposed to sit inside. Asking instead *what makes this
    /// one as tall as the words* gives the star the 2x it has always had and
    /// the trophy the 1x it needs, from a single rule.
    ///
    /// Whole, and never below 1: a sprite at a fraction of a pixel is the
    /// thing this whole app is arranged to avoid.
    public static func emblemScale(_ emblem: Sprite, textScale: CGFloat) -> CGFloat {
        let target = textHeight(scale: textScale)
        return max(1, (target / CGFloat(emblem.height)).rounded(.down))
    }

    /// The banner's footprint at a given scale, derived from the art rather
    /// than measured — so the window is exactly the drawing and its corners are
    /// where the drawing's are.
    public static func size(emblem: Sprite, title: String, scale: CGFloat) -> CGSize {
        let padding = paddingCells * scale
        let gap = gapCells * scale
        let header = headlineScale(scale)
        let art = emblemScale(emblem, textScale: scale)

        let emblemWidth = CGFloat(emblem.width) * art
        let textWidth = max(CGFloat(BannerFont.width(of: title)) * scale,
                            CGFloat(BannerFont.width(of: headline)) * header)

        // The halo is drawn, so it is counted — the window is exactly the
        // drawing, and its corners are where the drawing's are.
        let halo = haloCells * scale * 2
        return CGSize(
            width: halo + padding * 2 + emblemWidth + gap + textWidth,
            height: halo + padding * 2 + max(CGFloat(emblem.height) * art,
                                             textHeight(scale: scale))
        )
    }

    /// The largest whole scale that keeps the banner inside its share of the
    /// screen.
    ///
    /// Whole, because a sprite is only crisp when one source pixel covers a
    /// whole number of pixels — the same rule the badge follows. So the banner
    /// steps between sizes across screens rather than sliding, and a narrow
    /// screen gets the floor instead of an unreadable fraction of one.
    public static func scale(forScreenWidth width: CGFloat,
                             emblem: Sprite,
                             title: String) -> CGFloat {
        let ceiling = width * widthFraction
        var chosen = minimumScale
        var candidate = minimumScale
        while candidate <= maximumScale {
            if size(emblem: emblem, title: title, scale: candidate).width <= ceiling {
                chosen = candidate
            }
            candidate += 1
        }
        return chosen
    }
}

extension SpriteLayout {
    /// The star, tinted by the one health that means "clear". Still what a
    /// burst of unlocks shows, because no one trophy in a burst is the one
    /// the banner is about.
    public static func achievementEmblem() -> SpriteLayout {
        single(Achievement.emblem, accent: .good)
    }

    /// A line of banner text. `tint` only matters when `slot` is `.accent`.
    public static func bannerText(_ text: String,
                                  slot: Slot,
                                  tint: Health = .good) -> SpriteLayout {
        single(BannerFont.render(text, slot: slot), accent: tint)
    }
}
