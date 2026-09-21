import Foundation

/// The trophy drawings, and the rule for putting one together.
///
/// Composed rather than drawn thirty times over, the way `Pancakes` builds a
/// stack from a count. Three pieces decide a trophy:
///
///   - a **base**: the 32-cell frame — cup, shield, medal, plaque
///   - a **tier**: which metal that frame is struck in
///   - a **motif**: a 12-cell picture of the thing the trophy is actually for
///
/// The point of composing is that a shelf of thirty has to read as one set.
/// Thirty independent drawings share nothing but their size, and the eye sees
/// a junk drawer; four frames in three metals is a collection, and the motif
/// is then free to be specific without pulling the whole grid apart.
///
/// Bases are authored in gold. `badge` swaps that pair for the tier's, which
/// is what lets the fifty/hundred ladder be the same cup twice in two metals
/// rather than two unrelated pictures of success.
public enum TrophyArt {

    /// Cells square. Four times a mascot's pixel budget, and the reason a
    /// trophy can carry a readable picture inside a readable frame.
    public static let size = 32
    /// The engraving field a motif is stamped into.
    public static let motifSize = 12

    public enum Tier: Sendable {
        case gold, silver, bronze

        var face: Slot {
            switch self {
            case .gold: return .gold
            case .silver: return .silver
            case .bronze: return .bronze
            }
        }

        var shade: Slot {
            switch self {
            case .gold: return .goldShade
            case .silver: return .silverShade
            case .bronze: return .bronzeShade
            }
        }
    }

    public enum Base: Sendable {
        case cup, shield, medal, plaque
    }

    /// One trophy: a base struck in a tier with a motif engraved on it.
    ///
    /// Traps on a motif that is not `motifSize` square, for the same reason
    /// `Sprite` traps on ragged art — it is source code, so a wrong one is a
    /// mistake to be caught at first run rather than drawn slightly off.
    public static func badge(_ base: Base, motif: [String], tier: Tier) -> Sprite {
        precondition(motif.count == motifSize,
                     "motif has \(motif.count) rows, expected \(motifSize)")
        precondition(motif.allSatisfy { $0.count == motifSize },
                     "motif rows disagree with \(motifSize)")

        var sprite = base.sprite
        // Bases are authored in gold; any other tier is a swap of the pair.
        if tier != .gold {
            for y in 0..<sprite.height {
                for x in 0..<sprite.width {
                    switch sprite[x, y] {
                    case .gold: sprite[x, y] = tier.face
                    case .goldShade: sprite[x, y] = tier.shade
                    default: break
                    }
                }
            }
        }

        let origin = base.motifOrigin
        for (dy, row) in motif.enumerated() {
            for (dx, character) in row.enumerated() where character != "." {
                guard let slot = Slot(rawValue: character) else {
                    preconditionFailure("unknown motif slot '\(character)'")
                }
                sprite[origin.x + dx, origin.y + dy] = slot
            }
        }
        return sprite
    }
}

extension TrophyArt.Base {

    /// Where this base's engraving field starts. Not centred in the frame: a
    /// cup's field sits in its bowl and a medal's in its disc, and both are
    /// well above the middle of the 32 cells the whole drawing occupies.
    var motifOrigin: Point {
        switch self {
        case .cup: return Point(10, 4)
        case .shield: return Point(10, 6)
        case .medal: return Point(9, 14)
        case .plaque: return Point(10, 6)
        }
    }

    var sprite: Sprite {
        switch self {
        case .cup: return TrophyBaseArt.cup
        case .shield: return TrophyBaseArt.shield
        case .medal: return TrophyBaseArt.medal
        case .plaque: return TrophyBaseArt.plaque
        }
    }
}

/// The four frames, as literals.
///
/// A namespace of their own rather than statics on `Base`, which cannot carry
/// a `cup` beside a case already called `cup`. The split reads better than the
/// workaround deserves to: what a base *is* belongs with the other bases, and
/// which base a trophy *uses* belongs with the trophy.
public enum TrophyBaseArt {

    /// The two-handled cup. What a trophy looks like when a child draws one,
    /// which is exactly why it carries the trophies that are about *amount* —
    /// the ladder, the full board, the juggling act.
    public static let cup = Sprite([
            "................................",
            "......kkkkkkkkkkkkkkkkkkkk......",
            "......kooooooooooooooooook......",
            "......knnnnnnnnnnnnnnnnnnk......",
            "......koooccccccccccccoook......",
            "...kkkkoooccccccccccccoookkkk...",
            "..kok.koooccccccccccccoook.kok..",
            "..kok.koooccccccccccccoook.kok..",
            "..kok.koooccccccccccccoook.kok..",
            "..kok.koooccccccccccccoook.kok..",
            "..kok.koooccccccccccccoook.kok..",
            "..kok.koooccccccccccccoook.kok..",
            "..kok.koooccccccccccccoook.kok..",
            "...kkkkoooccccccccccccoookkkk...",
            "......koooccccccccccccoook......",
            "......koooccccccccccccoook......",
            ".......kooooooooooooooook.......",
            "........kooooooooooooook........",
            "..........knnnnnnnnnnk..........",
            "............knnnnnnk............",
            "..............kook..............",
            "..............kook..............",
            "..............knnk..............",
            "..........kkkkkkkkkkkk..........",
            "..........kooooooooook..........",
            "..........knnnnnnnnnnk..........",
            "........kkkkkkkkkkkkkkkk........",
            "........kooooooooooooook........",
            "........knnnnnnnnnnnnnnk........",
            "........kkkkkkkkkkkkkkkk........",
            "................................",
            "................................",
    ])

    /// A crested shield. Carries the trophies about holding a line rather than
    /// piling something up: a queue dug out of, a stack kept in order, an app
    /// still running after a month.
    public static let shield = Sprite([
            "................................",
            "................................",
            "....kkkkkkkkkkkkkkkkkkkkkkkk....",
            "....kooooooooooooooooooooook....",
            "....kkkkkkkkkkkkkkkkkkkkkkkk....",
            "....kooooooooooooooooooooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....koooooccccccccccccoooook....",
            "....kooooooooooooooooooooook....",
            ".....kooooooooooooooooooook.....",
            "......kooooooooooooooooook......",
            ".......kooooooooooooooook.......",
            "........kooooooooooooook........",
            ".........knnnnnnnnnnnnk.........",
            "..........knnnnnnnnnnk..........",
            "............knnnnnnk............",
            ".............knnnnk.............",
            "..............knnk..............",
            "...............kk...............",
            "..............kkkk..............",
            "................................",
            "................................",
    ])

    /// A disc on a ribbon. The one-moment award — it has no plinth, because
    /// nothing about it is meant to look permanent.
    ///
    /// Alone among the bases it has no cream field: a square of paper inside a
    /// round medal reads as a sticker stuck on it. The motif sits straight on
    /// the metal instead.
    public static let medal = Sprite([
            "........kuuuk......kuuuk........",
            "........kuuuk......kuuuk........",
            "........kuuuk......kuuuk........",
            ".........kuuuk....kuuuk.........",
            ".........kuuuk....kuuuk.........",
            ".........kuuuk....kuuuk.........",
            "..........kuuuk..kuuuk..........",
            "..........kuuuk..kuuuk..........",
            "..........kuuuk..kuuuk..........",
            "...........kukkkkkuuk...........",
            "..........kknnnnnnnkk...........",
            ".........knnnkkkkknnnk..........",
            ".......kknnkkoooookknnkk........",
            ".......knkkoooooooookknk........",
            "......knkoooooooooooooknk.......",
            ".....knnkoooooooooooooknnk......",
            ".....knkoooooooooooooooknk......",
            ".....nnkoooooooooooooooknn......",
            "....knkoooooooooooooooooknk.....",
            "....knkoooooooooooooooooknk.....",
            "....knkoooooooooooooooooknk.....",
            "....knkoooooooooooooooooknk.....",
            "....knkoooooooooooooooooknk.....",
            ".....nnkoooooooooooooooknn......",
            ".....knkoooooooooooooooknk......",
            ".....knnkoooooooooooooknnk......",
            "......knkoooooooooooooknk.......",
            ".......knkkoooooooookknk........",
            ".......kknnkkoooookknnkk........",
            ".........knnnkkkkknnnk..........",
            "..........kknnnnnnnkk...........",
            ".............kkkkk..............",
    ])

    /// An engraved plate on a stand. The reference-book base, for trophies
    /// that are really a record of a setting or a state rather than a feat.
    public static let plaque = Sprite([
            "................................",
            "................................",
            "...kkkkkkkkkkkkkkkkkkkkkkkkkk...",
            "...kooooooooooooooooooooooook...",
            "...konnnnnnnnnnnnnnnnnnnnnnok...",
            "...konoooooooooooooooooooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konooooccccccccccccoooonok...",
            "...konoooooooooooooooooooonok...",
            "...konoooooooooooooooooooonok...",
            "...konnnnnnnnnnnnnnnnnnnnnnok...",
            "...kooooooooooooooooooooooook...",
            "...kkkkkkkkkkkkkkkkkkkkkkkkkk...",
            ".............kkkkkk.............",
            ".............knnnnk.............",
            ".............knnnnk.............",
            ".......kkkkkkkkkkkkkkkkkk.......",
            ".......kooooooooooooooook.......",
            ".......knnnnnnnnnnnnnnnnk.......",
            ".......kkkkkkkkkkkkkkkkkk.......",
            "................................",
            "................................",
    ])
}

/// The 12-cell pictures, one per trophy.
///
/// Literals rather than anything procedural: a motif is a drawing of a broom
/// or a crescent moon, and there is no formula for either. `.` is transparent,
/// so whatever the base put underneath — cream field or bare metal — shows
/// through, and one motif works on any of the four.
public enum TrophyMotif {

    /// An in-tray with nothing in it but the last thing leaving.
    public static let inboxZero = [
            "............",
            "..t......t..",
            "..t......t..",
            "..t......t..",
            "..t..ff..t..",
            "..t.f..f.t..",
            "..tf....ft..",
            "..tttttttt..",
            "...t....t...",
            "....tttt....",
            "............",
            "............",
    ]

    /// A zero with an arrow coming back round to it.
    ///
    /// Both drawn two cells wide: at one, the ring and the digit read as the
    /// same smudge from across a grid.
    public static let backToZero = [
            "...tttttt...",
            "..t......t..",
            ".t..ffff..t.",
            "t..ff..ff..t",
            "t..ff..ff..t",
            "t..ff..ff..t",
            "t..ff..ff..t",
            ".t..ffff..t.",
            "..t......t..",
            "...ttt...t..",
            ".......t.t..",
            "........tt..",
    ]

    /// A broom, mid-stroke.
    public static let cleanSweep = [
            ".........tt.",
            "........tt..",
            ".......tt...",
            "......tt....",
            ".....tt.....",
            "....tt......",
            "...bbbb.....",
            "..bbbbbb....",
            ".bb.bb.bb...",
            "bb..bb..bb..",
            "b...bb...b..",
            "............",
    ]

    /// Paper, stacked past the point anyone is reading it.
    ///
    /// Outlines rather than solids: the field behind it is already cream, and
    /// a cream sheet on a cream plate is a blank plate.
    public static let swamped = [
            "...tttttt...",
            "...t....t...",
            "..tttttttt..",
            "..t......t..",
            ".tttttttttt.",
            ".t........t.",
            "tttttttttttt",
            "t..........t",
            "tttttttttttt",
            "............",
            "............",
            "............",
    ]

    /// Several people, all looking your way.
    public static let inDemand = [
            "............",
            "..u...u...u.",
            ".uuu.uuu.uuu",
            "..u...u...u.",
            "............",
            ".uuu.uuu.uuu",
            "uuuuuuuuuuuu",
            "uuuuuuuuuuuu",
            "............",
            "............",
            "............",
            "............",
    ]

    /// Three balls in the air, which is one more than is comfortable.
    public static let juggler = [
            "....rrrr....",
            "..rr....rr..",
            ".r........r.",
            "r..........r",
            "............",
            "..uu....uu..",
            ".uuuu..uuuu.",
            ".uuuu..uuuu.",
            "..uu....uu..",
            "....ffff....",
            "...ffffff...",
            "....ffff....",
    ]

    /// A tick, in the one colour this app uses for nothing-in-your-way.
    public static let greenLight = [
            "............",
            "...ffffff...",
            "..ffffffff..",
            ".ffffffffff.",
            ".ffff...tff.",
            ".fff...tttf.",
            ".fft..ttt.f.",
            ".fftttt...f.",
            "..fttt....f.",
            "...tf.....f.",
            "...fffffff..",
            "............",
    ]

    /// Not one tick but a grid of them — the whole board, not a row of it.
    public static let allClear = [
            "............",
            "..ff..ff..ff",
            ".ffff.ffffff",
            "ffffffffffff",
            ".ffff.ffffff",
            "..ff..ff..ff",
            "............",
            "..ff..ff..ff",
            ".ffff.ffffff",
            "ffffffffffff",
            ".ffff.ffffff",
            "..ff..ff..ff",
    ]

    /// Two pancakes and syrup. The stack marker the rows already wear.
    public static let shortStack = [
            "............",
            "....ssss....",
            "...s....s...",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".wwwwwwwwww.",
            "..tttttttt..",
            "............",
            "............",
    ]

    /// The same stack, four deep and running out of frame.
    public static let tallStack = [
            "....ssss....",
            "...s....s...",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".wwwwwwwwww.",
    ]

    /// A fork: one base, two things sitting on it.
    public static let branchingOut = [
            "..uu....uu..",
            ".uuuu..uuuu.",
            "..uu....uu..",
            "...u....u...",
            "....u..u....",
            ".....uu.....",
            "......u.....",
            "......u.....",
            "....uuuu....",
            "...uuuuuu...",
            "....uuuu....",
            "............",
    ]

    /// A stamp coming down on a line.
    public static let rubberStamp = [
            "....tttt....",
            "....t..t....",
            "....t..t....",
            "..rrrrrrrr..",
            ".rrrrrrrrrr.",
            "..rrrrrrrr..",
            "....rrrr....",
            "............",
            "tttttttttttt",
            "tttttttttttt",
            "............",
            "............",
    ]

    /// A crescent and two stars.
    ///
    /// Filled, not outlined — an outlined moon on a silver medal is a faint
    /// ring nobody reads as night.
    public static let nightWatch = [
            "....tttt....",
            "..tttttt....",
            ".ttttt...y..",
            ".tttt...yyy.",
            "tttt.....y..",
            "tttt........",
            "tttt........",
            ".tttt....y..",
            ".ttttt..yyy.",
            "..tttttt.y..",
            "....tttt....",
            "............",
    ]

    /// A calendar with the last two days ringed.
    public static let weekendWork = [
            "..t......t..",
            ".tttttttttt.",
            ".t........t.",
            ".tttttttttt.",
            ".t........t.",
            ".t..t..t..t.",
            ".t........t.",
            ".t..t..rrrt.",
            ".t.....rrrt.",
            ".t..rrrrrrt.",
            ".t..rrrrrrt.",
            ".tttttttttt.",
    ]

    /// Four faces in a row — the whole cast, once you have met it.
    public static let meetTheCast = [
            "..tttt.tttt.",
            ".t....t....t",
            ".t.uu.t.uu.t",
            ".t....t....t",
            "..tttt.tttt.",
            "............",
            "..tttt.tttt.",
            ".t....t....t",
            ".t.uu.t.uu.t",
            ".t....t....t",
            "..tttt.tttt.",
            "............",
    ]

    /// A frame pushed out to its corners.
    public static let bigBadge = [
            "tt........tt",
            "t..........t",
            "............",
            "..tttttttt..",
            "..t......t..",
            "..t......t..",
            "..t......t..",
            "..t......t..",
            "..tttttttt..",
            "............",
            "t..........t",
            "tt........tt",
    ]

    /// The same frame pulled in to nothing much.
    public static let tinyBadge = [
            "............",
            ".tt......tt.",
            ".t........t.",
            "............",
            "....tttt....",
            "....t..t....",
            "....t..t....",
            "....tttt....",
            "............",
            ".t........t.",
            ".tt......tt.",
            "............",
    ]

    /// A stack under the button that filters for it.
    public static let pancakePress = [
            "............",
            "....ssss....",
            "...s....s...",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".tbbbbbbbbt.",
            "..tttttttt..",
            ".wwwwwwwwww.",
            "..tttttttt..",
    ]

    /// A clock that has been running a while.
    public static let regular = [
            "....tttt....",
            "..tt....tt..",
            ".t........t.",
            "t....t.....t",
            "t....t.....t",
            "t....ttt...t",
            "t..........t",
            "t..........t",
            ".t........t.",
            "..tt....tt..",
            "....tttt....",
            "............",
    ]

    /// Service chevrons. Two, because one is not yet service.
    public static let veteran = [
            "............",
            "..u......u..",
            "..uu....uu..",
            "...uu..uu...",
            "....uuuu....",
            "............",
            "..u......u..",
            "..uu....uu..",
            "...uu..uu...",
            "....uuuu....",
            "............",
            "............",
    ]

    /// An arrow coming down into a tray.
    public static let upToDate = [
            ".....tt.....",
            ".....tt.....",
            ".....tt.....",
            ".....tt.....",
            "..t.....t...",
            "..tt...tt...",
            "...tt.tt....",
            "....ttt.....",
            "............",
            "t..........t",
            "tttttttttttt",
            "............",
    ]

    /// The number, over the merge it counts.
    public static let fiftyMerged = [
            "............",
            "............",
            "............",
            "............",
            "..ttt.ttt...",
            "..t...t.t...",
            "..ttt.t.t...",
            "....t.t.t...",
            "..ttt.ttt...",
            "............",
            "....f..f....",
            "..ffffffff..",
    ]

    /// The same, one order of magnitude on.
    public static let century = [
            "............",
            "............",
            "............",
            "............",
            ".t..ttt.ttt.",
            "tt..t.t.t.t.",
            ".t..t.t.t.t.",
            ".t..t.t.t.t.",
            "ttt.ttt.ttt.",
            "............",
            "....f..f....",
            "..ffffffff..",
    ]

    /// A question mark, for a trophy that will not say what it is.
    public static let mystery = [
            "...tttttt...",
            "..tt....tt..",
            "..tt....tt..",
            "........tt..",
            ".......tt...",
            "......tt....",
            ".....tt.....",
            ".....tt.....",
            ".....tt.....",
            "............",
            ".....tt.....",
            ".....tt.....",
    ]
}
