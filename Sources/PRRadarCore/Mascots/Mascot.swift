// Generated from the design pipeline — see the mascot preview artifact.
// Edited by regenerating, not by hand: the art is mirrored and shaded by a
// build step, and a hand edit here is a pixel the shading pass never saw.
//
// What the pipeline does, because the rules are not obvious from the output
// and the October four cost a day of rediscovering them:
//
//   1. A character is drawn as 48 rows of 24 and mirrored, so the silhouette
//      is symmetric to the pixel and only half of it is authored.
//   2. The outline is taken afterwards, from 4-connectivity: a lit cell with
//      an empty cell directly above, below, left or right becomes `k`. Doing
//      it 8-connected inks every diagonal step and the drawing turns to lace.
//   3. Only then is the fill shaded, from a normal read out of the distance
//      field, lit from the upper left. The interior sits on `base`; only the
//      surface brightens or falls away.
//   4. `chassisSpec` is placed by hand, after all of it. See the note on the
//      slot: a highlight the pass invents turns a soft edge into a rim.
//
// Two rules about shape that only show up once something is drawn wrong. A
// silhouette's edge may not swing more than about three rows between
// neighbouring columns — the outline pass inks every one of those steps, and
// Flit's wings came out as fringe until they were smoothed. And any spur has
// to be at least three columns wide: a single column reaching past its
// neighbours is outlined down both sides, which draws a spike rather than a
// fingertip.

import Foundation

/// How a character sweeps while the app is looking.
///
/// Declared per character rather than worked out from the art. Three of the
/// original four have a visor wider than it is tall, so deriving the axis from
/// the glass gave a helmet that should scan downward and a saucer that should
/// swing a searchlight the same beam going across. Half the cast has no glass
/// at all now, which makes the point twice over.
public enum SweepKind: Sendable {
    /// A beam across the glass, trailing, wrapping round the lens.
    case visor
    /// The same beam, scanning down the inside of a helmet instead.
    case hud
    /// A searchlight swinging through an arc under the hull.
    case beam
    /// Rings rippling outward, for the one with no glass to sweep.
    case psi
    /// A shimmer rising through a body that has no surface to light.
    case wisp
    /// Sonar: arcs thrown forward and down, out of the muzzle.
    case echo
    /// A candle guttering behind a carving, and the light it spills.
    case flicker
    /// A pulse stepping down the spine, one rib at a time.
    case marrow
}

/// Which section of the mascot room a character belongs to.
///
/// Declared per character rather than worked out from anything about the art,
/// for the same reason `SweepKind` is: a rule that reads the drawing is a rule
/// that changes when somebody redraws it.
///
/// `custom` is the default, and that is deliberate. A fork that has added its
/// own character is constructing `Mascot` with the arguments this type had
/// before the room existed; defaulting means `git pull && make install` keeps
/// building for them and their character turns up in their own row without
/// them doing anything. The cost is that a *built-in* one could forget to say
/// where it goes and land in somebody's personal row — so that is pinned by a
/// test rather than by the compiler. See `testEveryBuiltInMascotDeclaresItsSection`.
public enum MascotCohort: String, CaseIterable, Sendable {
    /// The 16-cell cast the app shipped with, upscaled to stand next to the rest.
    case og
    /// The 48-cell redraw: a radar bot, an astronaut, a saucer and an alien.
    case space
    /// The Halloween four. Dated because there may be another cohort later,
    /// not because they go away — they do not.
    case october2026
    /// Anything this build did not ship. A fork's own.
    case custom

    /// The section heading. `custom` has none of its own: the room titles it
    /// with whoever is signed in, which this type has no business knowing.
    public var title: String? {
        switch self {
        case .og:          return "OG Mascots"
        case .space:       return "Out of this World"
        case .october2026: return "October 2026"
        case .custom:      return nil
        }
    }

    /// Ordered as the room stacks them: oldest first, yours last.
    public static let ordered: [MascotCohort] = [.og, .space, .october2026, .custom]
}

public enum MascotID: String, CaseIterable, Sendable {
    /// The original cast, drawn at 16 cells and retired when the 48-cell
    /// redraw landed. Back, upscaled, because a room with a shelf for them is
    /// a better home than the git history was.
    case pip, byte, widget, nimbus
    case blip, scoot, wobble, bloop
    case boo, flit, gourd, rattle

    /// The picker, for anyone who finds it by clicking: each character in
    /// turn, then off, then round again.
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

/// One character: a 48×48 grid, where its eyes are, and its own chassis ramp.
///
/// Forty-eight rather than sixteen because the face had run out of room. A 2×2
/// eye gives about five distinguishable expressions and no more; at this size
/// an eye is a lens with a catchlight, a beam can cross a visor, and a surface
/// can be lit on one side and shaded on the other.
///
/// Every sprite is authored as 48 rows of 24 and mirrored, so a chassis is
/// symmetric to the pixel and only half of it is drawn by hand.
public struct Mascot: Identifiable, Sendable, Equatable {
    public let id: MascotID
    public let name: String
    /// What the tell is, for the picker's help text.
    public let tellName: String
    /// One line for the picker.
    public let blurb: String
    public let sprite: Sprite
    /// Top-left of each eye box.
    public let eyes: [Point]
    /// Eye boxes are square and this is their side. The alien's is half again
    /// the others — the whole joke of him is the eyes.
    public let eyeSize: Int
    /// What a lit eye pixel is drawn in.
    public let eyeInk: Slot
    /// How this one sweeps. Declared, not derived: deriving the axis from the
    /// shape of the glass collapsed three different sweeps into one beam.
    public let sweep: SweepKind
    /// This character's six chassis rungs. Per-character rather than one
    /// shared greyscale: four machines in the same grey read as one machine in
    /// four poses. The tell still takes the live `Health` tint, so the mood is
    /// never competing with the body colour for the same pixels.
    public let ramp: ChassisRamp
    /// Which shelf of the mascot room this one sits on.
    public let cohort: MascotCohort
    /// How far this one bobs: two for the ones with nothing under them, one
    /// for the ones standing on something.
    ///
    /// Stored with a default, for the same reason `cohort` is, and after the
    /// same mistake. This was a `switch id` with no default for one release —
    /// which meant a fork that had added its own character stopped compiling
    /// the moment it pulled, on a line that had nothing to do with anything
    /// it had asked for. The compile-time nudge is not worth that; a test
    /// keeps the built-in cast honest instead.
    public let bobScale: Int
    /// Rows to keep for a small perch: the head, and nothing it stands on.
    ///
    /// Sized so the crop still carries a tell. Cropping past the antenna
    /// would leave a header mascot with no way to show the mood at all,
    /// which is the whole reason a tell exists.
    public let headRows: Int

    /// Spelled out rather than left to the memberwise initialiser, so
    /// `cohort` can carry a default. See `MascotCohort`: a fork that added a
    /// character before this existed has to keep compiling.
    public init(id: MascotID, name: String, tellName: String, blurb: String,
                sprite: Sprite, eyes: [Point], eyeSize: Int, eyeInk: Slot,
                sweep: SweepKind, ramp: ChassisRamp, headRows: Int,
                cohort: MascotCohort = .custom, bobScale: Int = 1) {
        self.id = id
        self.name = name
        self.tellName = tellName
        self.blurb = blurb
        self.sprite = sprite
        self.eyes = eyes
        self.eyeSize = eyeSize
        self.eyeInk = eyeInk
        self.sweep = sweep
        self.ramp = ramp
        self.headRows = headRows
        self.cohort = cohort
        self.bobScale = bobScale
    }

    /// Always drawn in the live tint, whatever the eyes are doing.
    ///
    /// Derived from the art rather than listed by hand: the accent cells *are*
    /// the tell, and two copies of that fact drift apart the first time a
    /// sprite is edited.
    public var tell: [Point] {
        sprite.litPoints.filter {
            switch sprite[$0.x, $0.y] {
            case .accent, .accentMid, .accentDim: return true
            default: return false
            }
        }
    }

}


// MARK: - The original cast
//
// Drawn at 16 cells, retired when the 48-cell redraw landed, and brought back
// for the room's first shelf. Kept at their original size in source and
// enlarged by `scaled3x` — the app's own pixel-art upscale, the one the mood
// marks and the trophies already go through. Redrawing them at 48 would make
// them *different characters*, which is the one thing a nostalgia shelf must
// not do.
//
// Three things had to change to make them citizens of the current system.
//
// Their tell used to be a list of points painted at draw time and is derived
// from the art now, so it is baked into the literal as `a`.
//
// Their body tones were the old shared greyscale — `g`, `d`, `w` — and are
// chassis rungs now, with a ramp each mixed to land back on the greys they
// were. That is not cosmetic: `brighten` only understands chassis slots, so
// on the old palette three of the four had sweeps that changed nothing at
// all on some frames. A character that stops moving in the one state meant
// to show the app working is worse than a character in the wrong grey.
//
// And they predate the sweep, so each is given one that suits what it
// already was. Pip and Widget have visors, so a beam crosses them; Byte has
// the ears for sonar; Nimbus is a floater and shimmers.

extension Mascot {
    /// Rows 12–15 of the three busts. Identical by construction, so swapping
    /// characters could never shift the layout around them.
    private static let collar = [
        ".....kHHHHk.....",
        "..kkHHHHHHHHkk..",
        "..kHHHHHHHHHSk..",
        "..kkkkkkkkkkkk..",
    ]

    public static let pip = Mascot(
        id: .pip, name: "Pip", tellName: "antenna",
        blurb: "The first one there ever was. Radar, before it had a dish.",
        sprite: Sprite([
            ".......aa.......",
            ".......kk.......",
            "....kkkkkkkk....",
            "..kkHHHHHHHHkk..",
            "..kHHHHHHHHHSk..",
            "..kHVVVVVVVVHk..",
            ".kkHVaaVVaaVHkk.",
            ".kSHVaaVVaaVHSk.",
            "..kHVVVVVVVVHk..",
            "..kHHSSSSSSSHk..",
            "..kkHHHHHHHHkk..",
            "....kkkkkkkk....",
        ] + collar).scaled3x(),
        eyes: [Point(15, 18), Point(27, 18)], eyeSize: 6, eyeInk: .accent,
        sweep: .visor,
        ramp: ChassisRamp(deep: RGB(0.129, 0.145, 0.165), shade: RGB(0.271, 0.294, 0.325), mid: RGB(0.435, 0.463, 0.502),
                          base: RGB(0.639, 0.667, 0.706), light: RGB(0.839, 0.859, 0.886), spec: RGB(0.969, 0.976, 0.984)),
        headRows: 33, cohort: .og)

    public static let byte = Mascot(
        id: .byte, name: "Byte", tellName: "ear tips",
        blurb: "The animal of the first cast. Dark eyes, so the ears do the talking.",
        sprite: Sprite([
            "..k..........k..",
            "..kk........kk..",
            "..kak......kak..",
            "..kkkkkkkkkkkk..",
            ".kHHHHHHHHHHHHk.",
            ".kHWkHHHHHHWkHk.",
            ".kHkkHHHHHHkkHk.",
            ".kHHHHkkkkHHHHk.",
            ".kHHHkPPPkHHHSk.",
            ".kSHHkkkkkHHSSk.",
            "..kSSSSSSSSSSk..",
            "...kkkkkkkkkk...",
            ".....kHHHHk.....",
            "..kkHHHHHHHHkk..",
            "..kHHaaaaaaHSk..",
            "..kkkkkkkkkkkk..",
        ]).scaled3x(),
        eyes: [Point(9, 15), Point(33, 15)], eyeSize: 6, eyeInk: .outline,
        sweep: .echo,
        ramp: ChassisRamp(deep: RGB(0.161, 0.145, 0.129), shade: RGB(0.310, 0.286, 0.259), mid: RGB(0.478, 0.447, 0.408),
                          base: RGB(0.675, 0.643, 0.600), light: RGB(0.859, 0.835, 0.800), spec: RGB(0.980, 0.969, 0.953)),
        headRows: 33, cohort: .og)

    public static let widget = Mascot(
        id: .widget, name: "Widget", tellName: "mouth bar and power LED",
        blurb: "A screen on a collar. Says everything with one bar.",
        sprite: Sprite([
            "................",
            "...kkkkkkkkkk...",
            "..kSSSSSSSSSSk..",
            "..kSVVVVVVVVSk..",
            "..kSVaaVVaaVSk..",
            "..kSVaaVVaaVSk..",
            "..kSVVVVVVVVSk..",
            "..kSVVaaaaVVSk..",
            "..kSVVVVVVVVSk..",
            "..kSSSSSSSaaSk..",
            "...kkkkkkkkkk...",
            ".....kkkkkk.....",
        ] + collar).scaled3x(),
        eyes: [Point(15, 12), Point(27, 12)], eyeSize: 6, eyeInk: .accent,
        sweep: .visor,
        ramp: ChassisRamp(deep: RGB(0.110, 0.129, 0.161), shade: RGB(0.235, 0.271, 0.322), mid: RGB(0.384, 0.435, 0.502),
                          base: RGB(0.573, 0.627, 0.694), light: RGB(0.796, 0.835, 0.882), spec: RGB(0.957, 0.969, 0.980)),
        headRows: 33, cohort: .og)

    /// The one floater of the first cast, and the reason `bobScale` exists.
    public static let nimbus = Mascot(
        id: .nimbus, name: "Nimbus", tellName: "cheeks",
        blurb: "The first floater. Nothing under it then either.",
        sprite: Sprite([
            "......kkkk......",
            "....kkWWWWkk....",
            "...kWWWWWWWWk...",
            "..kWWWWWWWWWWk..",
            "..kWWWWWWWWWWk..",
            "..kWWkkWWkkWWk..",
            "..kWWkkWWkkWWk..",
            "..kWWWWWWWWWWk..",
            "..kWaWWWWWWaWk..",
            "..kWWWWWWWWWWk..",
            "..kWWWWWWWWWWk..",
            "..kWWWWWWWWWWk..",
            "..kWWWWWWWWWWk..",
            "..kWWkWWWWkWWk..",
            "..kWWkWWWWkWWk..",
            "..kkk.kkkk.kkk..",
        ]).scaled3x(),
        eyes: [Point(15, 15), Point(27, 15)], eyeSize: 6, eyeInk: .accent,
        sweep: .wisp,
        ramp: ChassisRamp(deep: RGB(0.298, 0.310, 0.337), shade: RGB(0.451, 0.467, 0.494), mid: RGB(0.616, 0.631, 0.659),
                          base: RGB(0.788, 0.800, 0.824), light: RGB(0.914, 0.922, 0.937), spec: RGB(1.000, 1.000, 1.000)),
        headRows: 33, cohort: .og, bobScale: 2)
}

extension Mascot {
    public static let blip = Mascot(
        id: .blip, name: "Blip", tellName: "antenna lamp and chest badge",
        blurb: "Radar bot, and the one the app opens on.",
        sprite: Sprite([
            ".....................kkkkkk.....................",
            "....................kaaaaaak....................",
            "...................kaaaaaaaak...................",
            "...................kaaaaaaaak...................",
            "....................kaaaaaak....................",
            ".....................kaaaak.....................",
            "......................kSDk......................",
            "......................kHDk......................",
            "......................kBSk......................",
            "..............kkkkkkkkkkkkkkkkkkkk..............",
            "...........kkkWWWWWWWWWWWWWWWWWWWWkkk...........",
            ".........kkWHWWWWWWWWWWWWWWWWWWWWWWHBkk.........",
            "........kHWWWXWWWWWWWWWWWWWHWWWWWWWWWBBk........",
            ".......kHHWWXWHWHWHWHWHWHWHWHWHHHWHWHWSSk.......",
            ".......kHWWXWHWHWHHHHHHHHHHHHHHHHHHHHHHDk.......",
            ".......kHWHWBHHHHHHHHHHHHHHHHHHHHBHHHHBDk.......",
            "...kWWBkHWWBHkVUUUUUUUUUUUUUUUUUUVkHHHHDkBHHk...",
            "..kWHWSkBWHHkVUUVVUUVVVVVVVVVVVVVVVkBHBDkBHBSk..",
            "..kWHHDkBHHkVUUVVVVVVVVVVVVVVVVVVVVVkHHDkSHBSk..",
            "..kWHD.kBHHkUUVVVVVVVVVVVVVVVVVVVVVVkWBDk.SHDk..",
            "..kHHD.kBHHkUVVVVVVVVVVVVVVVVVVVVVVVkHHDk.BBSk..",
            "..kHHD.kBHBkVVVVVVVVVVVVVVVVVVVVVVVVkWHDk.SBDk..",
            "...kHD.kBHHkVVVVVVVVVVVVVVVVVVVVVVVVkHHDk.BSk...",
            "...kHD.kBHBkVVVVVVVVVVVVVVVVVVVVVVVVkHHDk.SSk...",
            "...kHS.kBWBkVVVVVVVVVVVVVVVVVVVVVVVVkHHDk.BSk...",
            "...kHS.kBWHkVVVVVVVVVVVVVVVVVVVVVVVVkWHDk.SSk...",
            "...kHD.kBHWHkVVVVVVUUVVUUVVUUVVVVVVkWHHDk.BSk...",
            "...kHS.kBWHHHkVVVVVVVVVVVVVVVVVVVVkWWHBDk.BBk...",
            "..kWHD.kBWWHHHWHHHHHHHHHHHHBHHHHHHHWHHBDk.BBSk..",
            "..kWHS.kBSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSDk.BHSk..",
            ".kWHHD.kBHWHHHHHHBkSaaaaaaaaSkHHHHHHHBBDk.BHBSk.",
            ".kHBHD.kBWHSHHHHBBkaaaakkaaaakWHHHHHSBBDk.SHSDk.",
            ".kHBBD.kBWWHHHHHHBkaaakaakaaakWHHHHHHBBDk.SBSDk.",
            ".kBDDD.kBWHSHHHHHHkSakaaaakaSkWHHHBHSBBDk.DDDDk.",
            ".kkkkk.kBHHHHBHBHBHHHHHBHBHBHHHHHHHBHBBDk.kkkkk.",
            ".......kSSSSDDDSDDDDDSDDDDDSDSDSDSDDDDDDk.......",
            "........kDSDDDSDDDDDDDDDDDDDDDDDDDDDDDDk........",
            "..........kDDDDDDDDDDDDDDDDDDDDDDDDDDk..........",
            "..........kkkkkkkkkkkkkkkkkkkkkkkkkkkk..........",
            ".............kBBSSDk........kBSSSDk.............",
            ".............kBSSDDk........kBBSDDk.............",
            ".............kBBSDDk........kHSSDDk.............",
            ".............kHBSDDk........kBBSSDk.............",
            ".............kBSSDDk........kBSSDDk.............",
            "...........kWHHBBSSSSk....kHHHBSSSSSk...........",
            "...........kBSDDDDDDDk....kBSSDDDDDDk...........",
            "...........kSDDDDDDDDk....kSDDDDDDDDk...........",
            "...........kkkkkkkkkkk....kkkkkkkkkkk...........",
        ]),
        eyes: [Point(15, 19), Point(27, 19)], eyeSize: 6, eyeInk: .accent, sweep: .visor,
        ramp: ChassisRamp(deep: RGB(0.086, 0.129, 0.169), shade: RGB(0.180, 0.255, 0.314), mid: RGB(0.278, 0.376, 0.435),
                          base: RGB(0.424, 0.529, 0.592), light: RGB(0.608, 0.698, 0.753), spec: RGB(0.863, 0.918, 0.945)),
        headRows: 28, cohort: .space)
}

extension Mascot {
    public static let scoot = Mascot(
        id: .scoot, name: "Scoot", tellName: "helmet lamp and chest panel",
        blurb: "The astronaut. Nothing under him, so he never quite lands.",
        sprite: Sprite([
            ".....................kaaaak.....................",
            ".............kkkkkkkkkkkkkkkkkkkkkk.............",
            "..........kkkWWWWWWWWWWWWWWWWWWWWWWkkk..........",
            "........kkWWWWWWWWWWWWWWWWWWWWWWWWWWWWkk........",
            ".......kWWWWWWWWXXWWWWWWWWWWWWWWWWWWWWWWk.......",
            "......kWWWWWWWWXHWHWHWHWHWHWHWHWHWHWHWHHHk......",
            "......kWWWWWWHWHWHWHWHWHWHWHWHWHWHHHWHHHHk......",
            ".....kWWWHHWHWHHHHHHHHHHHHHHHHHHHHHHBHHHBBk.....",
            ".....kWWWHkVVVVVVVVVVVVVVVVVVVVVVVVVVkHHHBk.....",
            ".....kWWHkVVVVVVVVVVVVVVVVVVVVVVVVVVVVkHHBk.....",
            "....kWWWHkVVUUUUUUUUUUUUUUUUUUUUUUUUVVkWHBBk....",
            "....kWWWHkVVVUUVVUUVVVVVVVVVVVVVVVVVVVkWHBBk....",
            "....kWWHHkVVUUVVVVVVVVVVVVVVVVVVVVVVVVkWHHBk....",
            "....kWWHBkVUUVVVVVVVVVVVVVVVVVVVVVVVVVkWHHSk....",
            "....kWWHHkVUVVVVVVVVVVVVVVVVVVVVVVVVVVkWHBBk....",
            "....kWWHBkVVVVVVVVVVVVVVVVVVVVVVVVVVVVkWHHSk....",
            "....kWWHHkVVVVVVVVVVVVVVVVVVVVVVVVVVVVkWHBBk....",
            "....kWHHBkVVVVVVVVVVVVVVVVVVVVVVVVVVVVkWHHSk....",
            "....kWWHHkVVVVVVVVVVVVVVVVVVVVVVVVVVVVkWHBBk....",
            "....kWWWBkVVVVVVVVVVVVVVVVVVVVVVVVVVVVkWHBSk....",
            "....kWWHHkVVVVVVVVVVVVVVVVVVVVVVVVVVVVkHHBSk....",
            "....kWWWHWkVVVVVVVVVVVVVVVVVVVVVVVVVVkHHBBSk....",
            ".....kWHHHHkVVVVVVVVVVVVVVVVVVVVVVVVkHWBHSk.....",
            ".....kWWHHHHWkVVVVVVVVVVVVVVVVVVVVkHHWHHSSk.....",
            "......kWWBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBSk......",
            "......kWHBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBSk......",
            ".......kHBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBSk.......",
            "........kkHHHHHHHHHHHHHHHHHHHHHHHHHHBBkk........",
            "......kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHk......",
            "....kkWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHkk....",
            "...kWWWWWHHHSHHHHHHHHHHHHHHBHBHHHHHSHHHHHHHHk...",
            "...kWWWWHHHHSHHHBBBHHHHHHHBHBBHHHHHSHHHHHHBBk...",
            "...kWWWHHHHHSHHBHBkaaaaaaaaaakHHHHHSHHHHHBBSk...",
            "...kWWHHHHHHSHHHBBkakkaaaakkakWHHHHSHHHHBBBSk...",
            "...kWWWHHHHHSHHHHBkaaaaaaaaaakWHHHHSHHHHHBBSk...",
            "...kWWHHHHHHSHHHBHkaaaaaaaaaakHHHHHSHHHHBBBSk...",
            "...kWWHHHHHHSHHHHHHHHHHHHHHHHHWHHHHSHHHHHBBSk...",
            "...kWWHHHHHHSHHHHHHHHHHHHHHHHHHHHHHSHHHHBBBSk...",
            "...kWHHHHHHHSHHHHHHHHHHHHHHHHHHHHHHSHHHBBBBSk...",
            "...kWWHHHHHHSHHHHHHHHHHHHHHHHHHHHHHSHHBHBBSSk...",
            "...kWHHHHBHBSHHBHHHBHBHBHHHBHHHBHHHSHBBBBBSDk...",
            "....kHHHBBBHBHHHBBBBBBBBBHBHBHBBBBBBBBBBBSDk....",
            ".....kHBBBBBHBHHBBBBBBBBBBBBHBHBBBBBBBBSSDk.....",
            "......kDDDDDDDDSDDDDDDDDDDDDDDDSDDDDDDDDDk......",
            ".............kSDDDDk........kSSDDDk.............",
            ".............kSDDDDk........kSDDDDk.............",
            "............kSSDDDDDk......kBSDDDDDk............",
            "............kkkkkkkkk......kkkkkkkkk............",
        ]),
        eyes: [Point(15, 13), Point(27, 13)], eyeSize: 6, eyeInk: .accent, sweep: .hud,
        ramp: ChassisRamp(deep: RGB(0.137, 0.161, 0.220), shade: RGB(0.239, 0.278, 0.376), mid: RGB(0.373, 0.420, 0.533),
                          base: RGB(0.537, 0.588, 0.698), light: RGB(0.741, 0.780, 0.863), spec: RGB(0.957, 0.973, 1.000)),
        headRows: 28, cohort: .space, bobScale: 2)
}

extension Mascot {
    public static let wobble = Mascot(
        id: .wobble, name: "Wobble", tellName: "six rim lights",
        blurb: "The saucer. Hovers, never walks.",
        sprite: Sprite([
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "...............kkkkkkkkkkkkkkkkkk...............",
            ".............kkVVVVVVVVVVVVVVVVVVkk.............",
            "...........kkVXXVVVVVVVVVVVVVVVVVVVkk...........",
            "..........kVVXVVVVVVVVVVVVVVVVVVVVVVVk..........",
            ".........kUUUUUUUUUUUUUUUUUUUUUUUUUUUUk.........",
            ".........kVVUUVVUVVVVVVVVVVVVVVVVVVVVVk.........",
            "........kVVUUVVVVVVVVVVVVVVVVVVVVVVVVVVk........",
            "........kVVUVVVVVVVVVVVVVVVVVVVVVVVVVVVk........",
            "........kVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVk........",
            "........kVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVk........",
            "........kVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVk........",
            "........kVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVk........",
            "........kVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVk........",
            "........kVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVk........",
            "....kWWWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHWWWk....",
            "..kkWWWWWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHWHWHWkk..",
            "kkWWWWWHWHWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHWHWWkk",
            "kWWWWWHWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBk",
            "kWSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSBk",
            "kWMMMBBBBMMMBBBBMMMBBBBBBBBBBMMMBBBBMMMBBBSMMMDk",
            "kHMMMBBBBMMMBBBBMMMBBBBBBBBBBMMMBBBBMMMBBBBMMMDk",
            ".kMMMBBBBMMMBBBBMMMBBBBBBBBBBMMMBBBBMMMBSSSMMMk.",
            "..kSSSBBBSBBBBBBBBBBBBBBBBBBBBBBBBBSBSBSSSDDDk..",
            "....kDDDDDDSDDDSDDDSDDDSDDDSDDDSDDDSDDDDDDDk....",
            "......kDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDk......",
            ".........kDDDDDDDDDDDDDDDDDDDDDDDDDDDDk.........",
            "............kkkkkkkkkkkkkkkkkkkkkkkk............",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
        ]),
        eyes: [Point(15, 9), Point(27, 9)], eyeSize: 6, eyeInk: .accent, sweep: .beam,
        ramp: ChassisRamp(deep: RGB(0.110, 0.090, 0.188), shade: RGB(0.200, 0.169, 0.322), mid: RGB(0.306, 0.263, 0.471),
                          base: RGB(0.447, 0.400, 0.627), light: RGB(0.655, 0.612, 0.776), spec: RGB(0.902, 0.878, 0.973)),
        headRows: 31, cohort: .space, bobScale: 2)
}

extension Mascot {
    public static let bloop = Mascot(
        id: .bloop, name: "Bloop", tellName: "antenna bulbs",
        blurb: "The alien. Biggest eyes of the four, by a long way.",
        sprite: Sprite([
            "......kkkk............................kkkk......",
            ".....kaaaak..........................kaaaak.....",
            ".....kaaaak..........................kaaaak.....",
            "......kkkk............................kkkk......",
            ".......kk..............................kk.......",
            "........kk............................kk........",
            ".........kk..........................kk.........",
            "..........kk........................kk..........",
            "...........kk......................kk...........",
            "............kkkkkkkkkkkkkkkkkkkkkkkk............",
            ".........kkkWWWWWWWWWWWWWWWWWWWWWWWWkkk.........",
            ".......kkWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWkk.......",
            ".....kkWWWWWWWXXWWWWWWWWWWWWWWWWWWWWWWWWWkk.....",
            "....kWWWWWWWHXHWHWHWHWHWHWHWHWHWHWHWHWHWHWWk....",
            "...kWWWWWHWWWHWHHHHHHHHHHHHHHHHHHHHHHHHHHHHBk...",
            "...kWWWWHWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBk...",
            "...kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBSk...",
            "...kWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBSk...",
            "...kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBSk...",
            "...kWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBSk...",
            "...kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBSk...",
            "...kWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBSk...",
            "...kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBSk...",
            "...kWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBSk...",
            "...kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBSk...",
            "...kWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBHBSk...",
            "...kWWWHPPPPPHHHHHHHHHHHHHHHHHHHHHHPPPPPHBBSk...",
            "...kWHHHPPPPPHHHHHHHHkHHHHkHHHHHHHHPPPPPBBSSk...",
            "....kHHHPPPPPHHHHHHHHHkkkkHHHHHHHHHPPPPPBSSk....",
            ".....kBBBHHHHHHHHHHHHHHHHHHHHHHHHHBHBBBSSSk.....",
            ".......kBBHHHHHHHHHHHHHHHHHHHHHBHBBBBSSDk.......",
            ".........kBBHHHHHHHHHHHHHHHHHHBHBBBSSSk.........",
            "...........kBHHHHHHHHHHHHHHHHHHBBSSDk...........",
            ".............kHHHHHHHHHHHHHHHHHHBSk.............",
            "..............kSSSSSSSSSSSSSSSSDDk..............",
            "............kWWWHHHHHHHHHHHHHHHHBBBk............",
            "...........kWWWHHHHHHHHHHHHHHHHHHBBBk...........",
            "...........kWWHHHHHHWWWWWWWWHHHHBHBSk...........",
            "...........kWWHHHHHWWWWWWWWWWHHHHBBSk...........",
            "...........kWWHHHHHWWWWWWWWWWHHHBBBSk...........",
            "...........kWHHHHBHWWWWWWWWWWBHBHBBSk...........",
            "...........kWHHHBBBHWWWWWWWWHBBBBBSSk...........",
            "...........kWHHBBBBBBBBBBBBBBBBBBSBDk...........",
            "...........kSDDDDDDDDDDDDDDDDDDDDDDDk...........",
            "............kkkkkkkkkkkkkkkkkkkkkkkk............",
            "..............kSDDk..........kSSDk..............",
            "..............kDDDk..........kDDDk..............",
            ".............kkkkkkk........kkkkkkk.............",
        ]),
        eyes: [Point(10, 15), Point(29, 15)], eyeSize: 9, eyeInk: .accent, sweep: .psi,
        ramp: ChassisRamp(deep: RGB(0.071, 0.161, 0.102), shade: RGB(0.122, 0.271, 0.153), mid: RGB(0.192, 0.392, 0.227),
                          base: RGB(0.298, 0.545, 0.325), light: RGB(0.455, 0.714, 0.482), spec: RGB(0.784, 0.929, 0.788)),
        headRows: 28, cohort: .space)
}

extension Mascot {
    public static let boo = Mascot(
        id: .boo, name: "Boo", tellName: "mouth-light and hem wisps",
        blurb: "The ghost. Wails in whatever colour the queue is.",
        sprite: Sprite([
            "................................................",
            "................................................",
            "................................................",
            "..................kkkkkkkkkkkk..................",
            "...............kkkWWWWWWWWWHHHkkk...............",
            ".............kkWWWWWWWWWWWWWHHHHHkk.............",
            "............kWWWWWWWWWWHWHWHHHHHHHHk............",
            "...........kWWWWWWHWHWHWHWHHHHHHHHHHk...........",
            "..........kWXXWWWHHHHHHHHHHHHHHHHHHHHk..........",
            ".........kWWXWWHHHHHHHHHHHHHHHHHHHHHHHk.........",
            ".........kWWWWHHHHHHHHHHHHHHHHHHHHHHHHk.........",
            "........kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHk........",
            "........kWWWWHHHHHHHHHHHHHHHHHHHHHHHHBHk........",
            ".......kWXXWHHHHHHHHHHHHHHHHHHHHHHHHHHBHk.......",
            ".......kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHBk.......",
            "......kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHk......",
            "......kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHBHk......",
            "......kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHBHBk......",
            ".....kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBHBk.....",
            ".....kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHBHBHk.....",
            ".....kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBBk.....",
            "....kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBHBk....",
            "....kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBHBHk....",
            "....kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBBk....",
            "....kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBBBk....",
            "...kWWWWHHHHHHHHHHHHHaaaaaaHHHHHHHHHHHHHBBBHk...",
            "...kWWWHHHHHHHHHHHHHaaaaaaaaHHHHHHHHHHHHHBBBk...",
            "...kWWWWHHHHHHHHHHHHaaaaaaaaHHHHHHHHHHHHBBBBk...",
            "...kWWWHHHHHHHHHHHHHaaaaaaaaHHHHHHHHHHHHHBBBk...",
            "..kWWWHHHHHHHHHHHHHHHaaaaaaHHHHHHHHHHHHHHHBBBk..",
            "..kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBBBk..",
            "..kWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBBk..",
            "..kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBBBk..",
            ".kWWWWHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHBBBBk.",
            ".kWWWHHHHHHBHBHHHHHHHHHHHHHHHHHHHHHBHHHHHHHBBBk.",
            ".kWWHWHHHHHHBHHHHHHHHHHHHHHHHHHHHHBHBHHHHHBBBBk.",
            ".kWWWHHHHHHBBBHHHHHHHHHHHHHHHHHHHHBBBHHHHHHBBSk.",
            ".kWWHHHHHHHBBBBHHHHHHHHHHHHHHHHHHHBBBHHHHHBBSSk.",
            ".kWHHHHHHHHkkkHHHHHHHHHHHHHHHHHHHBkkkBHHHHHBBSk.",
            ".kHHHHHHBSk...kWHHHHHHHHHHHHHHBBDk...kHHHHHBSSk.",
            ".kHHHHHBBSk...kHWHHHHHHHHHHHHBBSSk...kHHHHHBBSk.",
            "..kHHHBBSSk...kHHHHHHHHHHHHHHBBSDk...kHHHHBBSk..",
            "..kBHBBBSk.....kHHHHHHHHHBHBBBSDk.....kHHBBBSk..",
            "...kaaaaak.....kaaaaaaaHBaaaaaaak.....kaaaaak...",
            "....kaaak.......kaaaaaaBBaaaaaak.......kaaak....",
            ".....kkk.........kaaaaaBSaaaaak.........kkk.....",
            "..................kkkkkkkkkkkk..................",
            "................................................",
        ]),
        eyes: [Point(12, 17), Point(29, 17)], eyeSize: 7, eyeInk: .accent, sweep: .wisp,
        ramp: ChassisRamp(deep: RGB(0.137, 0.184, 0.204), shade: RGB(0.235, 0.318, 0.341), mid: RGB(0.361, 0.471, 0.490),
                          base: RGB(0.529, 0.659, 0.671), light: RGB(0.729, 0.847, 0.851), spec: RGB(0.925, 0.980, 0.980)),
        headRows: 32, cohort: .october2026, bobScale: 2)
}

extension Mascot {
    public static let flit = Mascot(
        id: .flit, name: "Flit", tellName: "ear linings and chest pip",
        blurb: "The bat. Ears first, everything else second.",
        sprite: Sprite([
            "................................................",
            "................................................",
            "...............kkkkk........kkkkk...............",
            "..............kWWWWWk......kWWWWHk..............",
            ".............kWWWWWHHk....kWWWWWHHk.............",
            ".............kWaaaaaHk....kWaaaaaHk.............",
            "............kWaaaaaaHk....kWaaaaaaBk............",
            "............kWaaaaaaHk....kWaaaaaaBk............",
            "...........kWaaaaaaaHk....kWaaaaaaaBk...........",
            "...........kWaaaaaaaBk....kWaaaaaaaBk...........",
            "...........kWHHBHHHBBk....kWWHHHBSSSk...........",
            "k..........kkkkkHHHHHHkkkkHHHHHHkkkkk..........k",
            "kkk.............kXXWWHWWWWHHBBBk.............kkk",
            "kkkkk.........kkWWHHHHWWWWHHHHBBkk.........kkkkk",
            "kWWkkkk......kWWWHHHHHWHWHHHHHHBHHk......kkkkWWk",
            "kWWWWkkk....kWWWHHHHHHHWHWHHHHHHHHHk....kkkWWWHk",
            "kWWWWWHkkk..kXWWHHHHHHHHHHHHHHHBHBHk..kkkWWHHHHk",
            "kWWWWWWWkkkkWWHHHHHHHHHHHHHHHHHHHHHWkkkkHHHHHHBk",
            "kWWWWHWWWWkWWHHHHHHHHHHHHHHHHHHHHHHHWkWWHHHHHBBk",
            "kWWWHHHWWWWWHHHHHHHHHHHHHHHHHHHHHHHWWWHWHHHHBBSk",
            "kWWWWHHHWHWHHHHHHHHHHHHHHHHHHHHHHHHHWHHHHBHBBBSk",
            "kWHWHHHHHHHWHHBHBHHHHHHHHHHHHHHHHHBHHHHHHBBHBBDk",
            ".kWHHHHHHHHHHBBBHBHHHHHHHHHHHBHBHBBHHHHHHSBBBDk.",
            ".kHWHHHHHHHHHBBBBHBHHHHHHHHHHHBBBBBHHHHHBSSBSSk.",
            ".kHHHHkHHHHHHkkBBBBHHHDDDDHHHBBBBkkHHHHHBkSBSDk.",
            "..kBBk.kHHBHk..kkHHHHHDDDDHHBSDkk..kHHBBk.kBBk..",
            "..kBk..kHBBBk....kkWWHHHHHHBBkk....kHBBSk..kBk..",
            "...kk..kBBBBk......kWWHHHHBBk......kHBBSk..kk...",
            "........kBBBk.....kWWHHHHHHBSk.....kHBBk........",
            "........kBBBk.....kWWaaaaaaBSk.....kBBSk........",
            ".........kkBk.....kHWaaaaaaBSk.....kBkk.........",
            "...........kk.....kWWWaaaaBBDk.....kk...........",
            "...........kk......kWHHHHBBSk......kk...........",
            "............k......kWHHHBBBBk......k............",
            "............k......kWHHBBBBSk......k............",
            "....................kHBBBBSk....................",
            "....................kHBBBSSk....................",
            "...................kHHkkkkSSk...................",
            "...................kBk....kBk...................",
            "...................kBk....kBk...................",
            "...................kkk....kkk...................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
        ]),
        eyes: [Point(13, 16), Point(28, 16)], eyeSize: 7, eyeInk: .accent, sweep: .echo,
        ramp: ChassisRamp(deep: RGB(0.106, 0.071, 0.063), shade: RGB(0.196, 0.133, 0.114), mid: RGB(0.298, 0.208, 0.176),
                          base: RGB(0.447, 0.325, 0.271), light: RGB(0.639, 0.518, 0.443), spec: RGB(0.906, 0.843, 0.788)),
        headRows: 30, cohort: .october2026, bobScale: 2)
}

extension Mascot {
    public static let gourd = Mascot(
        id: .gourd, name: "Gourd", tellName: "carved grin and nose",
        blurb: "The jack-o'-lantern. The only one lit from inside.",
        sprite: Sprite([
            ".....................ffffff.....................",
            ".....................ffffff.....................",
            "....................ffffffff....................",
            "....................ffffffff....................",
            "....................ffffffff....................",
            "...................ffffffffff...................",
            "...................ffffffffff...................",
            "..............kkkkkWHHHHHHHHHkkkkk..............",
            "...........kkkWWWWWWHHHHHHHHWWWHHHkkk...........",
            ".........kkWWWWWWWWWHHHHHHHHHWWWHHHHHkk.........",
            ".......kkWWWWWWWWHWHHHHHHHHHHHWHWHWHHHHkk.......",
            "......kkWWWWWWkWHWHHHHHHHHHHHWHWHkHHHHHHkk......",
            ".....kWkWWWHWHkHHHHHHHHHHHHHHHHHHkHHHHHHkHk.....",
            "....kWWkWWHXXHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHk....",
            "...kWWWkWHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHHk...",
            "...kWWWkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHHk...",
            "..kWWWWkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHHHk..",
            "..kWWWHkHHXHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHHBk..",
            ".kWWWHHkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHHHHk.",
            ".kWWWWHkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHHBHk.",
            ".kWWWHHkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHBHBk.",
            "kWWWHHHkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHHBHBk",
            "kWWWWHHkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkHHHHBBk",
            "kWWWHHHkHHHHHHkHHHHHHHaaaaHHHHHHHkHHHHHHkHHHBBBk",
            "kWWWWHHkHHHHHHkHHHHHHaaaaaaHHHHHHkHHHHHHkHHBBBBk",
            "kWWWHHHkHHHHHHkHHHHHHaaaaaaHHHHHHkHHHHHHkHHHBBSk",
            "kWWHHHHkHHHHaakHHaaaaHHHHHHaaaaHHkaaHHHHkHHBBSSk",
            "kWHWHHHkaaaaaakHHaaaaHHHHHHaaaaHHkaaaaaakHHHBBDk",
            ".kWHWHHkaaaaaakHHaaaaHHHHHHaaaaHHkaaaaaakHHBBDk.",
            ".kHWHHHkaaaaaakaaaaaaaaaaaaaaaaaakaaaaaakHBBSSk.",
            ".kHHHHHkHaaaaakaaaHHaaaaaaaaHHaaakaaaaaHkHHBSDk.",
            "..kWHHHkHHHHaakaaaHHaaaaaaaaHHaaakaaHHHHkHBSDk..",
            "..kHHHHkHHHHHHkHHHHHHaaaaaaHHHHHHkHHHHHHkBBSDk..",
            "...kHHHkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHHkBSDk...",
            "...kHHHkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHHBkBSDk...",
            "....kHHkHHHHHHkHHHHHHHHHHHHHHHHHHkHHHHBBkSDk....",
            ".....kHkHHHHHHkHHHHHHHHHHHHHHHHHHkHBHBBSkDk.....",
            "......kkHHHHHHkHBHHHHHHHHHHHHHBHBkBBBSSSkk......",
            ".......kkHHHHBkBHBHBHBHBHBHBHBHBBkBSSDSkk.......",
            ".......k.kkHHHkHBBBHBHBHBHBHBBBBSkSSDkk.k.......",
            "...........kkkHHHBHBBBBBBBBBBBSSSDkkk...........",
            "..............kkkkHHBBBBSSSSSSkkkk..............",
            "..................kkkkkkkkkkkk..................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
            "................................................",
        ]),
        eyes: [Point(10, 15), Point(30, 15)], eyeSize: 8, eyeInk: .accent, sweep: .flicker,
        ramp: ChassisRamp(deep: RGB(0.235, 0.086, 0.024), shade: RGB(0.373, 0.161, 0.043), mid: RGB(0.541, 0.255, 0.063),
                          base: RGB(0.729, 0.373, 0.094), light: RGB(0.882, 0.549, 0.243), spec: RGB(0.976, 0.816, 0.608)),
        headRows: 34, cohort: .october2026)
}

extension Mascot {
    public static let rattle = Mascot(
        id: .rattle, name: "Rattle", tellName: "nose hollow and the spark in his ribs",
        blurb: "The skeleton. Nothing to bob but bones.",
        sprite: Sprite([
            "................................................",
            "................................................",
            "..............kkkkkkkkkkkkkkkkkkkk..............",
            "............kkWWWWWWWWWWWWWWWWHHHHkk............",
            "...........kWWWWWWWWWWWWWWWWWHWHHHHHk...........",
            "..........kXXWWWWWWWHWHWHWHWHWHHHHHHHk..........",
            ".........kWWWWWHWHWHWHWHWHWHWHHHHHHHHHk.........",
            ".........kWWWWHHHHHHHHHHHHHHHHHHHHHHHHk.........",
            "........kWWWWHHHHHHHHHHHHHHHHHHHHHHHHBBk........",
            "........kWXWHHHHHHHHHHHHHHHHHHHHHHHHBBBk........",
            "........kWWWWHHHHHHHHHHHHHHHHHHHHHHHHBBk........",
            "........kWWWHHHHHHHHHHHHHHHHHHHHHHHHBBSk........",
            "........kWWHHHHHHHHHHHHHHHHHHHHHHHHBBSSk........",
            "........kWHHHHHHHHHHHHHHHHHHHHHHHHHBBBSk........",
            ".........kWHHHHHHHHHHHHHHHHHHHHHHHHBSDk.........",
            ".........kHHHHHHHHHHHHHHHHHHHHHHHHBBSDk.........",
            "..........kHHHHHHHHHHHaaaaHHHHHHHBBSDk..........",
            "...........kHWHHHHHHHHaaaaHHHHHHBBSDk...........",
            "............kWWHHHHHHHHaaHHHHHHBBSSk............",
            ".............kHWHHHHHHHHHHHHHHBBSSk.............",
            "............kHHkHHkHHkHHHHkHHkBBkSSk............",
            "............kHHkHHkHHkHHHHkHBkBBkSDk............",
            "............kHHkHHkBHkHHHHkHBkBSkDDk............",
            ".............kkkHHBBHHHHHHHHSSSSkkk.............",
            "................kkkkWHHHHHHBkkkk................",
            "....................kWHHHHBk....................",
            "....................kWWHHBBk....................",
            "....................kWHHHHBk....................",
            "......kkkkkkkkkkkkkkHHHHHHHHkkkkkkkkkkkkkk......",
            ".....kWHk.kWWWWWWWWWHHSSSSHHWWWWHHHHBk.kHWk.....",
            "....kWWHk.kWDDDDDDDDDDSSSSDDDDDDDDDDBk.kHWWk....",
            "....kWWk..kWWWWWWWWWHaaaaaaHHWHHHHBBSk..kWWk....",
            "...kWHWk...kWWWWWHWHHaaaaaaHHHHHHHBSk...kWWHk...",
            "...kHHk....kWDDDDDDDDDSSSSDDDDDDDDDSk....kHHk...",
            "...kHHk....kWWWHHHHHHHSSSSHHHHHHHBBSk....kHHk...",
            "...kHHk.....kWWWHHHHHHSSSSHHHHHHBBSk.....kHHk...",
            "....kBHk....kHDDDDDDDDSSSSDDDDDDDDSk....kHBk....",
            "....kBBk.....kWWWWHHHHSSSSHHHHHHSSk.....kHBk....",
            ".....kBHk.....kHWHHHHHSSSSHBHBBBSk.....kWBk.....",
            ".....kBHHk....kWWWHHHHBHBBBBHHBBDk....kWHBk.....",
            "......kHHHk..kHHWHHHHBBBBBBBHHHBSDk..kWHHk......",
            "......kHHHk..kHHHHHHBBBBBBSSHHBBDDk..kHHBk......",
            ".......kkkk...kkWHHHkkkkkkkkHBBSkk...kkkk.......",
            "................kBBk........kBBk................",
            "................kBBk........kBBk................",
            "................kBBk........kBBk................",
            "................kBBk........kBBk................",
            "...............kkkkkk......kkkkkk...............",
        ]),
        eyes: [Point(11, 9), Point(30, 9)], eyeSize: 7, eyeInk: .accent, sweep: .marrow,
        ramp: ChassisRamp(deep: RGB(0.239, 0.227, 0.196), shade: RGB(0.376, 0.357, 0.306), mid: RGB(0.537, 0.514, 0.443),
                          base: RGB(0.714, 0.686, 0.596), light: RGB(0.867, 0.847, 0.776), spec: RGB(0.984, 0.976, 0.941)),
        headRows: 26, cohort: .october2026)
}

extension Mascot {
    /// Every character this build ships, in the order the room stacks them
    /// and the order clicking the mascot cycles them.
    public static let all: [Mascot] = [pip, byte, widget, nimbus,
                                       blip, scoot, wobble, bloop,
                                       boo, flit, gourd, rattle]

    /// The characters on one shelf, in cast order.
    public static func cohort(_ cohort: MascotCohort) -> [Mascot] {
        all.filter { $0.cohort == cohort }
    }

    public static func named(_ id: MascotID) -> Mascot {
        all.first { $0.id == id } ?? blip
    }
}
