// Generated from the design pipeline — see the mascot preview artifact.
// Edited by regenerating, not by hand: the art is mirrored and shaded by a
// build step, and a hand edit here is a pixel the shading pass never saw.

import Foundation

public enum MascotID: String, CaseIterable, Sendable {
    case blip, scoot, wobble, bloop

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
    /// This character's six chassis rungs. Per-character rather than one
    /// shared greyscale: four machines in the same grey read as one machine in
    /// four poses. The tell still takes the live `Health` tint, so the mood is
    /// never competing with the body colour for the same pixels.
    public let ramp: ChassisRamp
    /// Rows to keep for the small crop — the head, without whatever it stands on.
    public let headRows: Int

    /// Always drawn in the live tint, whatever the eyes are doing.
    ///
    /// Derived from the art rather than listed by hand: the tinted cells *are*
    /// the tell, and two copies of that fact drift apart the first time a
    /// sprite is edited.
    ///
    /// All three strengths count. The saucer's hull lights are authored dim
    /// because his tic lights one of the six at a time — they are still his
    /// tell, and reading only full-strength cells would say he has none.
    public var tell: [Point] {
        sprite.litPoints.filter {
            switch sprite[$0.x, $0.y] {
            case .accent, .accentMid, .accentDim: return true
            default: return false
            }
        }
    }

    /// Whether this character bobs further than the others. The two with
    /// nothing under them do.
    public var bobScale: Int { id == .scoot || id == .wobble ? 2 : 1 }
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
        eyes: [Point(15, 19), Point(27, 19)], eyeSize: 6, eyeInk: .accent,
        ramp: ChassisRamp(deep: RGB(0.086, 0.129, 0.169), shade: RGB(0.180, 0.255, 0.314), mid: RGB(0.278, 0.376, 0.435),
                          base: RGB(0.424, 0.529, 0.592), light: RGB(0.608, 0.698, 0.753), spec: RGB(0.863, 0.918, 0.945)),
        headRows: 40)
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
        eyes: [Point(15, 13), Point(27, 13)], eyeSize: 6, eyeInk: .accent,
        ramp: ChassisRamp(deep: RGB(0.137, 0.161, 0.220), shade: RGB(0.239, 0.278, 0.376), mid: RGB(0.373, 0.420, 0.533),
                          base: RGB(0.537, 0.588, 0.698), light: RGB(0.741, 0.780, 0.863), spec: RGB(0.957, 0.973, 1.000)),
        headRows: 30)
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
        eyes: [Point(15, 9), Point(27, 9)], eyeSize: 6, eyeInk: .accent,
        ramp: ChassisRamp(deep: RGB(0.110, 0.090, 0.188), shade: RGB(0.200, 0.169, 0.322), mid: RGB(0.306, 0.263, 0.471),
                          base: RGB(0.447, 0.400, 0.627), light: RGB(0.655, 0.612, 0.776), spec: RGB(0.902, 0.878, 0.973)),
        headRows: 32)
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
        eyes: [Point(10, 15), Point(29, 15)], eyeSize: 9, eyeInk: .accent,
        ramp: ChassisRamp(deep: RGB(0.071, 0.161, 0.102), shade: RGB(0.122, 0.271, 0.153), mid: RGB(0.192, 0.392, 0.227),
                          base: RGB(0.298, 0.545, 0.325), light: RGB(0.455, 0.714, 0.482), spec: RGB(0.784, 0.929, 0.788)),
        headRows: 36)
}

extension Mascot {
    public static let all: [Mascot] = [blip, scoot, wobble, bloop]

    public static func named(_ id: MascotID) -> Mascot {
        all.first { $0.id == id } ?? blip
    }
}
