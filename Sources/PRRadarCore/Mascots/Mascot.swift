import Foundation

public enum MascotID: String, CaseIterable, Sendable {
    case pip, byte, widget, nimbus

    /// The picker, for anyone who finds it by clicking: each character in turn,
    /// then off, then round again.
    ///
    /// `nil` is a stop on the loop rather than the end of it. Treating it as a
    /// terminus is what strands someone who clicks one past the last character
    /// — the control goes inert and the context menu becomes the only way back.
    public static func next(after current: MascotID?) -> MascotID? {
        guard let current, let index = allCases.firstIndex(of: current) else {
            return allCases.first
        }
        return index + 1 < allCases.count ? allCases[index + 1] : nil
    }
}

/// One character: a 16×16 grid, where its eyes are, and the one element that
/// always takes the mood colour.
///
/// That last part is not decoration. A mascot with dark eyes loses the accent
/// entirely — the first pass had two of these four reading identically across
/// all seven moods — so every character declares a `tell` wide enough to be
/// seen at the smallest size it is ever drawn.
public struct Mascot: Identifiable, Sendable {
    public let id: MascotID
    public let name: String
    /// What the tell is, for the picker's help text.
    public let tellName: String
    public let sprite: Sprite
    /// Top-left of each 2×2 eye box.
    public let eyes: [Point]
    /// What a lit eye pixel is drawn in. Glowing for the machines, outline for
    /// the animals — which is why those two need a wider tell.
    public let eyeInk: Slot
    /// What an unlit eye pixel reverts to.
    public let eyeOff: Slot
    /// Always drawn in the accent, whatever the eyes are doing.
    public let tell: [Point]
    /// Rows to keep for the small crop. Three of the four are busts whose
    /// bottom four rows are a shared collar; cropping those off is what makes
    /// a 16 pt perch read as a head rather than a smudge.
    public let headRows: Int

    /// The character with a mood applied: eyes repainted, tell lit.
    public func frame(eyes pattern: EyePattern) -> Sprite {
        var grid = sprite
        for box in eyes {
            for dy in 0..<2 {
                for dx in 0..<2 {
                    grid[box.x + dx, box.y + dy] =
                        pattern.isLit(dx: dx, dy: dy) ? eyeInk : eyeOff
                }
            }
        }
        for point in tell { grid[point.x, point.y] = .accent }
        return grid
    }
}

extension Mascot {
    /// Rows 12–15 of every bust. Identical by construction, so swapping
    /// characters can never shift the layout around them.
    public static let collar = [
        ".....kggggk.....",
        "..kkggggggggkk..",
        "..kgggggggggdk..",
        "..kkkkkkkkkkkk..",
    ]

    public static let pip = Mascot(
        id: .pip, name: "Pip", tellName: "antenna",
        sprite: Sprite([
            ".......aa.......",
            ".......kk.......",
            "....kkkkkkkk....",
            "..kkggggggggkk..",
            "..kgggggggggdk..",
            "..kgvvvvvvvvgk..",
            ".kkgvaavvaavgkk.",
            ".kdgvaavvaavgdk.",
            "..kgvvvvvvvvgk..",
            "..kggdddddddgk..",
            "..kkggggggggkk..",
            "....kkkkkkkk....",
        ] + collar),
        eyes: [Point(5, 6), Point(9, 6)], eyeInk: .accent, eyeOff: .glass,
        tell: [Point(7, 0), Point(8, 0)], headRows: 12)

    public static let byte = Mascot(
        id: .byte, name: "Byte", tellName: "ear tips and collar",
        sprite: Sprite([
            "..k..........k..",
            "..kk........kk..",
            "..kak......kak..",
            "..kkkkkkkkkkkk..",
            ".kggggggggggggk.",
            ".kgwkggggggwkgk.",
            ".kgkkggggggkkgk.",
            ".kggggkkkkggggk.",
            ".kgggkpppkgggdk.",
            ".kdggkkkkkggddk.",
            "..kddddddddddk..",
            "...kkkkkkkkkk...",
        ] + collar),
        eyes: [Point(3, 5), Point(11, 5)], eyeInk: .outline, eyeOff: .body,
        // Dark eyes, so the tell has to do all of it: ear tips plus a band
        // across the collar.
        tell: [Point(3, 2), Point(12, 2),
               Point(5, 14), Point(6, 14), Point(7, 14),
               Point(8, 14), Point(9, 14), Point(10, 14)],
        headRows: 12)

    public static let widget = Mascot(
        id: .widget, name: "Widget", tellName: "mouth bar and power LED",
        sprite: Sprite([
            "................",
            "...kkkkkkkkkk...",
            "..kddddddddddk..",
            "..kdvvvvvvvvdk..",
            "..kdvaavvaavdk..",
            "..kdvaavvaavdk..",
            "..kdvvvvvvvvdk..",
            "..kdvvaaaavvdk..",
            "..kdvvvvvvvvdk..",
            "..kddddddddadk..",
            "...kkkkkkkkkk...",
            ".....kkkkkk.....",
        ] + collar),
        eyes: [Point(5, 4), Point(9, 4)], eyeInk: .accent, eyeOff: .glass,
        tell: [Point(12, 9)], headRows: 12)

    /// The one floater. No collar, so it bobs twice as far and there is nothing
    /// to crop — its head crop is the whole sprite.
    public static let nimbus = Mascot(
        id: .nimbus, name: "Nimbus", tellName: "glowing eyes",
        sprite: Sprite([
            "......kkkk......",
            "....kkwwwwkk....",
            "...kwwwwwwwwk...",
            "..kwwwwwwwwwwk..",
            "..kwwwwwwwwwwk..",
            "..kwwkkwwkkwwk..",
            "..kwwkkwwkkwwk..",
            "..kwwwwwwwwwwk..",
            "..kwpwwwwwwpwk..",
            "..kwwwwwwwwwwk..",
            "..kwwwwwwwwwwk..",
            "..kwwwwwwwwwwk..",
            "..kwwwwwwwwwwk..",
            "..kwwkwwwwkwwk..",
            "..kwwkwwwwkwwk..",
            "..kkk.kkkk.kkk..",
        ]),
        eyes: [Point(5, 5), Point(9, 5)], eyeInk: .accent, eyeOff: .light,
        tell: [Point(4, 8), Point(11, 8)], headRows: 16)

    public static let all: [Mascot] = [pip, byte, widget, nimbus]

    public static func named(_ id: MascotID) -> Mascot {
        all.first { $0.id == id } ?? pip
    }

    /// Whether this character bobs further than the busts. Only the floater
    /// does; the others are anchored by the collar.
    public var bobScale: Int { id == .nimbus ? 2 : 1 }
}
