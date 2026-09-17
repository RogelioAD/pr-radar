import Foundation

/// A 3×5 font — the smallest that stays a number rather than a texture, and
/// the reason the widget has a minimum scale at all.
public enum PixelFont {
    public static let digitWidth = 3
    public static let digitHeight = 5

    static let glyphs: [Character: [String]] = [
        "0": ["111", "101", "101", "101", "111"],
        "1": ["010", "110", "010", "010", "111"],
        "2": ["111", "001", "111", "100", "111"],
        "3": ["111", "001", "111", "001", "111"],
        "4": ["101", "101", "111", "001", "001"],
        "5": ["111", "100", "111", "001", "111"],
        "6": ["111", "100", "111", "101", "111"],
        "7": ["111", "001", "010", "010", "010"],
        "8": ["111", "101", "111", "101", "111"],
        "9": ["111", "101", "111", "001", "111"],
        "+": ["000", "010", "111", "010", "000"],
    ]
}

/// The count, redrawn on the same grid as everything else.
///
/// The alternative was a Dock badge hung off the corner, which lands on exactly
/// the pixels the mood mark uses — and reads as an anti-aliased circle in
/// SF Pro sitting on a 16×16 character. Chips cost the Dock likeness and buy
/// back a widget that is one artwork.
public enum Counter {
    public static let height = 7

    /// Matches `BadgeView`'s existing cap, so the two never disagree on what a
    /// large number looks like.
    public static func text(for count: Int) -> String {
        count > 99 ? "99+" : "\(count)"
    }

    public static func width(for text: String) -> Int {
        4 * text.count + 3
    }

    /// Outline, accent fill, light digits, corners knocked out so it reads as a
    /// chip rather than a brick.
    public static func chip(_ text: String) -> Sprite {
        let w = width(for: text), h = height
        var rows = Array(repeating: Array(repeating: Character("."), count: w), count: h)

        for x in 0..<w {
            rows[0][x] = "k"
            rows[h - 1][x] = "k"
        }
        for y in 1..<(h - 1) {
            rows[y][0] = "k"
            rows[y][w - 1] = "k"
            for x in 1..<(w - 1) { rows[y][x] = "a" }
        }
        for (y, x) in [(0, 0), (0, w - 1), (h - 1, 0), (h - 1, w - 1)] { rows[y][x] = "." }
        for (y, x) in [(1, 0), (1, w - 1), (h - 2, 0), (h - 2, w - 1)] { rows[y][x] = "k" }

        for (index, character) in text.enumerated() {
            guard let glyph = PixelFont.glyphs[character] else { continue }
            let ox = 2 + index * 4
            for y in 0..<PixelFont.digitHeight {
                for x in 0..<PixelFont.digitWidth
                where Array(glyph[y])[x] == "1" {
                    rows[y + 1][ox + x] = "w"
                }
            }
        }
        return Sprite(rows.map { String($0) })
    }
}

/// Picking a scale that keeps pixels square.
public enum SpriteScale {
    /// A sprite is only crisp when one source pixel covers a whole number of
    /// **device** pixels — not a whole number of points. On a 2× display that
    /// makes 1×, 1.5× and 2× valid and 1.75× a blurry mess, so the scale snaps
    /// to the backing store rather than to the point grid.
    public static func snapped(targetPoints: CGFloat,
                               spriteWidth: Int,
                               backingScale: CGFloat,
                               minimum: CGFloat = 1) -> CGFloat {
        guard spriteWidth > 0 else { return minimum }
        let step = 1 / max(1, backingScale)
        let raw = targetPoints / CGFloat(spriteWidth)
        let snapped = (raw / step).rounded() * step
        return max(minimum, snapped)
    }
}
