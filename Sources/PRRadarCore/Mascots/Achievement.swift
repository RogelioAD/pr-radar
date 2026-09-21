import Foundation

/// The art for the banner that drops in when the review queue reaches zero.
///
/// Green, because that is already this app's colour for *nothing is in your
/// way* — the same `Health.good` the ready-to-merge count wears, resolved from
/// `accent` rather than written down a second time.
public enum Achievement {

    /// What the banner says. Two lines, the way these have always been: a small
    /// standing header, and the thing you actually did.
    public static let headline = "ACHIEVEMENT UNLOCKED"
    public static let title = "REVIEWS CLEARED"

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

    /// The banner's footprint at a given scale, derived from the art rather
    /// than measured — so the window is exactly the drawing and its corners are
    /// where the drawing's are.
    public static func size(scale: CGFloat) -> CGSize {
        let padding = paddingCells * scale
        let gap = gapCells * scale
        let header = headlineScale(scale)

        let emblemWidth = CGFloat(emblem.width) * scale
        let textWidth = max(CGFloat(BannerFont.width(of: title)) * scale,
                            CGFloat(BannerFont.width(of: headline)) * header)
        let textHeight = CGFloat(BannerFont.height) * (scale + header)
            + lineGapCells * scale

        return CGSize(
            width: padding * 2 + emblemWidth + gap + textWidth,
            height: padding * 2 + max(CGFloat(emblem.height) * scale, textHeight)
        )
    }

    /// The largest whole scale that keeps the banner inside its share of the
    /// screen.
    ///
    /// Whole, because a sprite is only crisp when one source pixel covers a
    /// whole number of pixels — the same rule the badge follows. So the banner
    /// steps between sizes across screens rather than sliding, and a narrow
    /// screen gets the floor instead of an unreadable fraction of one.
    public static func scale(forScreenWidth width: CGFloat) -> CGFloat {
        let ceiling = width * widthFraction
        var chosen = minimumScale
        var candidate = minimumScale
        while candidate <= maximumScale {
            if size(scale: candidate).width <= ceiling { chosen = candidate }
            candidate += 1
        }
        return chosen
    }
}

extension SpriteLayout {
    /// The star, tinted by the one health that means "clear".
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
