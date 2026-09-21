import Foundation

/// A 5×7 uppercase font, for text that has to be read across a room rather
/// than glanced at on a badge.
///
/// Separate from `PixelFont` rather than an extension of it: that one is 3×5
/// and exists because a counter chip has nowhere to put a sixth row. Letters
/// need the extra two — at 3×5 an `M` and an `N` are the same four pixels — and
/// `Counter` measures its chips against `digitWidth` exactly, so widening it
/// would move every badge in the app.
///
/// Masks rather than slot characters, like `PixelFont`: the caller decides what
/// colour a lit pixel is, because the same word is drawn green on one line and
/// white on the next.
public enum BannerFont {
    public static let width = 5
    public static let height = 7
    /// One blank column between letters. Two reads as a word gap.
    public static let tracking = 1

    static let glyphs: [Character: [String]] = [
        "A": [".111.", "1...1", "1...1", "11111", "1...1", "1...1", "1...1"],
        "B": ["1111.", "1...1", "1...1", "1111.", "1...1", "1...1", "1111."],
        "C": [".1111", "1....", "1....", "1....", "1....", "1....", ".1111"],
        "D": ["1111.", "1...1", "1...1", "1...1", "1...1", "1...1", "1111."],
        "E": ["11111", "1....", "1....", "1111.", "1....", "1....", "11111"],
        "F": ["11111", "1....", "1....", "1111.", "1....", "1....", "1...."],
        "G": [".1111", "1....", "1....", "1..11", "1...1", "1...1", ".111."],
        "H": ["1...1", "1...1", "1...1", "11111", "1...1", "1...1", "1...1"],
        "I": ["11111", "..1..", "..1..", "..1..", "..1..", "..1..", "11111"],
        "J": ["....1", "....1", "....1", "....1", "1...1", "1...1", ".111."],
        "K": ["1...1", "1..1.", "1.1..", "11...", "1.1..", "1..1.", "1...1"],
        "L": ["1....", "1....", "1....", "1....", "1....", "1....", "11111"],
        "M": ["1...1", "11.11", "1.1.1", "1...1", "1...1", "1...1", "1...1"],
        "N": ["1...1", "11..1", "1.1.1", "1..11", "1...1", "1...1", "1...1"],
        "O": [".111.", "1...1", "1...1", "1...1", "1...1", "1...1", ".111."],
        "P": ["1111.", "1...1", "1...1", "1111.", "1....", "1....", "1...."],
        "Q": [".111.", "1...1", "1...1", "1...1", "1.1.1", "1..1.", ".11.1"],
        "R": ["1111.", "1...1", "1...1", "1111.", "1.1..", "1..1.", "1...1"],
        "S": [".1111", "1....", "1....", ".111.", "....1", "....1", "1111."],
        "T": ["11111", "..1..", "..1..", "..1..", "..1..", "..1..", "..1.."],
        "U": ["1...1", "1...1", "1...1", "1...1", "1...1", "1...1", ".111."],
        "V": ["1...1", "1...1", "1...1", "1...1", "1...1", ".1.1.", "..1.."],
        "W": ["1...1", "1...1", "1...1", "1...1", "1.1.1", "11.11", "1...1"],
        "X": ["1...1", "1...1", ".1.1.", "..1..", ".1.1.", "1...1", "1...1"],
        "Y": ["1...1", "1...1", ".1.1.", "..1..", "..1..", "..1..", "..1.."],
        "Z": ["11111", "....1", "...1.", "..1..", ".1...", "1....", "11111"],
        "0": [".111.", "1...1", "1..11", "1.1.1", "11..1", "1...1", ".111."],
        "1": ["..1..", ".11..", "..1..", "..1..", "..1..", "..1..", ".111."],
        "2": [".111.", "1...1", "....1", "...1.", "..1..", ".1...", "11111"],
        "3": ["11111", "...1.", "..1..", "...1.", "....1", "1...1", ".111."],
        "4": ["...1.", "..11.", ".1.1.", "1..1.", "11111", "...1.", "...1."],
        "5": ["11111", "1....", "1111.", "....1", "....1", "1...1", ".111."],
        "6": [".111.", "1....", "1111.", "1...1", "1...1", "1...1", ".111."],
        "7": ["11111", "....1", "...1.", "..1..", ".1...", ".1...", ".1..."],
        "8": [".111.", "1...1", "1...1", ".111.", "1...1", "1...1", ".111."],
        "9": [".111.", "1...1", "1...1", ".1111", "....1", "....1", ".111."],
        " ": [".....", ".....", ".....", ".....", ".....", ".....", "....."],
        ",": [".....", ".....", ".....", ".....", "..11.", "..1..", ".1..."],
        ".": [".....", ".....", ".....", ".....", ".....", "..11.", "..11."],
        "!": ["..1..", "..1..", "..1..", "..1..", "..1..", ".....", "..1.."],
        "'": ["..1..", "..1..", ".1...", ".....", ".....", ".....", "....."],
        "-": [".....", ".....", ".....", "11111", ".....", ".....", "....."],
    ]

    /// Cells a string occupies, tracking included. Zero for an empty string,
    /// which is the one case where the `- tracking` below would go negative.
    public static func width(of text: String) -> Int {
        text.isEmpty ? 0 : text.count * (width + tracking) - tracking
    }

    /// Renders uppercased text into a sprite, every lit pixel `slot`.
    ///
    /// Anything the font has no glyph for is drawn as a space rather than
    /// trapping. A banner is decoration: a missing punctuation mark should cost
    /// a gap in a word, not the app.
    public static func render(_ text: String, slot: Slot) -> Sprite {
        let characters = Array(text.uppercased())
        guard !characters.isEmpty else { return Sprite([String(repeating: ".", count: 1)]) }

        let total = width(of: text)
        var rows = Array(repeating: Array(repeating: Character("."), count: total),
                         count: height)
        for (index, character) in characters.enumerated() {
            let glyph = glyphs[character] ?? glyphs[" "]!
            let originX = index * (width + tracking)
            for (y, row) in glyph.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "1" {
                    rows[y][originX + x] = slot.rawValue
                }
            }
        }
        return Sprite(rows.map { String($0) })
    }
}
