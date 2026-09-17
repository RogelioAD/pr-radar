import Foundation

/// A 2×2 eye. Two by two gives about five distinguishable expressions and no
/// more, which is fine: the face was never the signal. Colour, the mark and the
/// bob carry the mood; the eyes are punctuation.
public enum EyePattern: Sendable {
    case open, shut, glance, wide, dead

    /// `dx`/`dy` are 0 or 1 within the eye box.
    public func isLit(dx: Int, dy: Int) -> Bool {
        switch self {
        case .open, .wide: return true
        case .shut:        return dy == 1
        case .glance:      return dx == 1
        case .dead:        return dx == dy
        }
    }
}

/// The small glyph beside the character's head. Drawn in the accent, in a
/// gutter to the right of the character — which is exactly where a Dock badge
/// would hang, and the reason the counters moved below instead.
public enum Mark: String, CaseIterable, Sendable {
    case none, zzz, bang, query, spark, scanLeft, scanMiddle, scanRight

    public static let width = 5
    public static let height = 6

    public var rows: [String] {
        switch self {
        case .none:       return [".....", ".....", ".....", ".....", ".....", "....."]
        case .zzz:        return [".aaa.", "...a.", "..a..", ".a...", ".aaa.", "....."]
        case .bang:       return ["..a..", "..a..", "..a..", "..a..", ".....", "..a.."]
        case .query:      return [".aaa.", "a...a", "...a.", "..a..", ".....", "..a.."]
        case .spark:      return ["..a..", "a.a.a", ".aaa.", "a.a.a", "..a..", "....."]
        case .scanLeft:   return [".....", ".....", "a....", ".....", ".....", "....."]
        case .scanMiddle: return [".....", ".....", "..a..", ".....", ".....", "....."]
        case .scanRight:  return [".....", ".....", "....a", ".....", ".....", "....."]
        }
    }

    public var sprite: Sprite { Sprite(rows) }
}

/// How a character looks and moves for one state. Shared by `Mood` and
/// `Reaction` so the renderer only ever knows about this.
public struct SpriteStyle: Sendable {
    public let eyes: EyePattern
    /// Cycled one per animation frame.
    public let marks: [Mark]
    public let health: Health
    /// Vertical offset per animation frame, in sprite pixels.
    public let bob: [Int]

    public init(eyes: EyePattern, marks: [Mark], health: Health, bob: [Int]) {
        self.eyes = eyes
        self.marks = marks
        self.health = health
        self.bob = bob
    }

    public func mark(frame: Int) -> Mark { marks[abs(frame) % marks.count] }
    public func offset(frame: Int) -> Int { bob[abs(frame) % bob.count] }
    public var maxBob: Int { bob.max() ?? 0 }
}

/// What the app is doing, as one of seven faces.
public enum Mood: String, CaseIterable, Sendable {
    case asleep, idle, nudging, alarmed, working, proud, lost

    /// Pure, so the whole truth table is tested without a window.
    ///
    /// Order matters and is the argument: a problem outranks everything because
    /// nothing else on screen can be trusted while it holds, and a refresh
    /// outranks staleness because "I am checking" is the more useful answer to
    /// "is this number still true".
    public static func of(reviews: Int,
                          worst: Staleness,
                          readyToMerge: Int,
                          isRefreshing: Bool,
                          hasProblem: Bool) -> Mood {
        if hasProblem { return .lost }
        if isRefreshing { return .working }
        if reviews == 0 { return readyToMerge > 0 ? .proud : .asleep }
        switch worst {
        case .stale: return .alarmed
        case .aging: return .nudging
        case .fresh: return .idle
        }
    }

    /// Reuses the app's one colour scale rather than inventing a palette, so
    /// the mascot and the count beside it are the same colour by construction.
    public var style: SpriteStyle {
        switch self {
        case .asleep:
            return SpriteStyle(eyes: .shut, marks: [.zzz, .zzz, .zzz, .none],
                               health: .good, bob: [0, 0, 0, 1, 1, 1])
        case .idle:
            return SpriteStyle(eyes: .open, marks: [.none],
                               health: .running, bob: [0])
        case .nudging:
            return SpriteStyle(eyes: .glance, marks: [.bang, .bang, .none],
                               health: .attention, bob: [0, 0, 1, 1])
        case .alarmed:
            return SpriteStyle(eyes: .wide, marks: [.bang, .none],
                               health: .bad, bob: [0, 1])
        case .working:
            return SpriteStyle(eyes: .shut,
                               marks: [.scanLeft, .scanMiddle, .scanRight],
                               health: .running, bob: [0])
        case .proud:
            return SpriteStyle(eyes: .open, marks: [.spark, .none],
                               health: .good, bob: [0, 0, 1, 1])
        case .lost:
            return SpriteStyle(eyes: .dead, marks: [.query],
                               health: .neutral, bob: [0])
        }
    }

    /// Whether this mood can occur while the review list is empty — which is
    /// exactly when the empty-state mascot is the one on screen.
    public var reachableWhenListEmpty: Bool {
        switch self {
        case .asleep, .working, .proud, .lost: return true
        case .idle, .nudging, .alarmed: return false
        }
    }
}

/// Reactions the collapsed badge earns and the drawer does not: the drawer is
/// open for seconds at a time, the badge is on screen all day. A gesture
/// A reaction outranks the derived mood for as long as it lasts.
/// Named `Reaction` rather than `Gesture` because SwiftUI already owns that
/// word, and a mascot type that shadows it makes every `Gesture` in the view
/// layer ambiguous.
public enum Reaction: String, CaseIterable, Sendable {
    case waking, held, startled

    public func style(tint: Health) -> SpriteStyle {
        switch self {
        case .waking:
            return SpriteStyle(eyes: .open, marks: [.none], health: tint, bob: [0, 0, 1, 1])
        case .held:
            return SpriteStyle(eyes: .wide, marks: [.none], health: tint, bob: [1])
        case .startled:
            return SpriteStyle(eyes: .wide, marks: [.bang, .none],
                               health: .attention, bob: [0, 2, 1, 0])
        }
    }
}
