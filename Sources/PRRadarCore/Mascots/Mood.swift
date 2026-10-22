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


/// How hard the one character with a mouthful of fire is breathing.
///
/// Declared per mood rather than worked out from the tint, for the reason
/// `SweepKind` is declared: two moods can share a colour and have nothing
/// else in common. `idle` and `working` are both blue, and one of them is the
/// app actually doing something.
///
/// The reach is a readout, and that is the point of it. It tracks how much
/// the app wants you to look — out when there is nothing to say, a pilot
/// light when it is only keeping a queue warm, everything he has when
/// something has gone stale. Every other character's tell is a colour and
/// nothing else; this one has a length too, and a length is legible across a
/// desk at a glance, which a hue at this size is not.
public enum Breath: String, CaseIterable, Sendable {
    /// Out. The coal in his throat, and nothing past the teeth.
    case out
    /// A pilot light.
    case pilot
    /// Steady.
    case steady
    /// Up.
    case flare
    /// Everything he has.
    case blast
    /// Guttering: pilot length and never twice the same. The one setting
    /// here that reads as something being *wrong* rather than as quiet.
    case gutter

    /// The flame, drawn.
    ///
    /// Left half only, mirrored on the way out, so it comes back symmetric
    /// by construction. `a` is the hot core, `N` the body of it, `M` the
    /// cool outside; the last column is the centre line and is always the
    /// hottest thing in its row.
    ///
    /// Drawn rather than computed, after several goes at computing it. A
    /// flame generated from leans and tapers came out, in order: a cone, a
    /// bell, a splash, a bundle of roots and a glowing blob — each fixing
    /// the last one's artefact and introducing its own. The rest of this
    /// cast's art is drawn by hand and its rules written down, for exactly
    /// this reason.
    ///
    /// Two things about the shape, both learnt by getting them wrong:
    ///
    ///   * It bulges just below the jaw and then tapers a long way to a
    ///     point. Widest in the middle — the obvious symmetric thing to
    ///     draw — is a leaf, and at a glance it reads as one.
    ///   * The bands are nested inside the outline rather than graded from
    ///     the mouth down. A smooth top-to-bottom gradient is what a
    ///     *liquid* looks like, and the version that had one read as
    ///     something being brought up rather than breathed out.
    public var half: [String] {
        switch self {
        case .out:
            return []
        case .pilot:
            return [
                    "........MNa",
                    ".......MNaa",
                    ".......MNaa",
                    "........MNa",
                    "........MMN",
                    ".........MM",
                    "..........M"]
        case .gutter:
            return [
                    "........MNa",
                    ".......MNaa",
                    "........M.a",
                    ".........MN",
                    ".........MN",
                    "..........M"]
        case .steady:
            return [
                    ".......MNaa",
                    "......MNaaa",
                    "......MNaaa",
                    "......MNaaa",
                    ".......MNaa",
                    ".......MNaa",
                    "........MMN",
                    "........MMN",
                    ".........MN",
                    ".........MM",
                    "..........M"]
        case .flare:
            return [
                    ".......MNaa",
                    ".....MNaaaa",
                    ".....MNaaaa",
                    ".....MNaaaa",
                    ".....MNaaaa",
                    "......MNaaa",
                    "......MNaaa",
                    ".......M.aa",
                    ".......M.NN",
                    ".......MMNN",
                    "........MMN",
                    "........MMN",
                    ".........MN",
                    ".........MM",
                    "..........M",
                    "..........M"]
        case .blast:
            return [
                    ".......MNaa",
                    ".....MNaaaa",
                    "....MNaaaaa",
                    "...MNaaaaaa",
                    "...MNaaaaaa",
                    "...MNaaaaaa",
                    "....MNaaaaa",
                    "....MNaaaaa",
                    ".....M.aaaa",
                    ".....M.aaaa",
                    "......MNaaa",
                    "......MMNNN",
                    ".......M.NN",
                    ".......M.NN",
                    "........MMN",
                    "........MMN",
                    ".........MN",
                    ".........MM",
                    "..........M",
                    "..........M",
                    "..........M"]
        }
    }

    /// The whole flame, mirrored.
    public var rows: [String] { half.map { $0 + String($0.reversed()) } }

    /// How many rows it runs for.
    public var reach: Int { half.count }
}

/// How a character looks and moves for one state. Shared by `Mood` and
/// `Reaction` so the renderer only ever knows about this.
public struct SpriteStyle: Sendable {
    public let eyes: EyePattern
    /// Cycled one per animation frame.
    public let marks: [Mark]
    public let health: Health
    /// Vertical offset per animation frame, in units.
    public let bob: [Int]
    /// How hard the one character with a flame is breathing in this state.
    ///
    /// Carried here rather than read off `health` because the renderer is
    /// only ever given a `SpriteStyle`, and because two states can share a
    /// tint and want different fires out of it. Defaulted for the reason
    /// `Mascot.cohort` is: a caller building a style with the arguments this
    /// type had before the dragon existed keeps compiling, and gets a dragon
    /// breathing normally.
    public let breath: Breath
    /// Whether the character runs its sweep in this state.
    ///
    /// Tied to the tint rather than picked per mood: the sweep belongs to
    /// `running` — the blue states — and nothing else. Blue is the app
    /// *looking*, either watching a clear queue or fetching; green, amber and
    /// red are all outcomes, and a beam crossing a character that is trying
    /// to tell you something is wrong makes the state you must notice look
    /// like the one you can ignore.
    public var sweeps: Bool { health == .running }

    public init(eyes: EyePattern, marks: [Mark], health: Health, bob: [Int],
                breath: Breath = .steady) {
        self.eyes = eyes
        self.marks = marks
        self.health = health
        self.bob = bob
        self.breath = breath
    }

    public func mark(frame: Int) -> Mark { marks[abs(frame) % marks.count] }
    public func offset(frame: Int) -> Int { bob[abs(frame) % bob.count] }
    public var maxBob: Int { bob.max() ?? 0 }
}

/// What the app is doing, as one of seven faces.
public enum Mood: String, CaseIterable, Sendable {
    case asleep, dozing, stirring, idle, nudging, alarmed, working, proud, lost

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
                          hasProblem: Bool,
                          snoozed: Int = 0,
                          wakingSoon: Bool = false) -> Mood {
        if hasProblem { return .lost }
        if isRefreshing { return .working }
        if reviews == 0 {
            if readyToMerge > 0 { return .proud }
            // An empty list and a parked one are not the same thing, and the
            // character was saying they were. `reviews` is the waking count,
            // so snoozing six put him to sleep exactly as finishing six did —
            // accidentally charming, and a small lie told in the one place
            // that is on screen all day.
            //
            // `proud` still wins, because that is about your own work being
            // ready and has nothing to do with what you parked.
            guard snoozed > 0 else { return .asleep }
            return wakingSoon ? .stirring : .dozing
        }
        switch worst {
        case .stale: return .alarmed
        case .aging: return .nudging
        case .fresh: return .idle
        }
    }

    /// How close a wake has to be before the character notices it coming.
    ///
    /// Five minutes, which is about how long the eye takes to find a badge it
    /// was not looking for. Shorter and it would be over before you glanced;
    /// longer and he would spend half an afternoon pretending to stir.
    public static let stirringWindow: TimeInterval = 300

    /// Reuses the app's one colour scale rather than inventing a palette, so
    /// the mascot and the count beside it are the same colour by construction.
    public var style: SpriteStyle {
        switch self {
        case .asleep:
            return SpriteStyle(eyes: .shut, marks: [.zzz, .zzz, .zzz, .none],
                               health: .good, bob: [0, 0, 0, 1, 1, 1],
                               breath: .out)
        case .dozing:
            // Asleep's shape, slowed down and taken off green.
            //
            // Green is the colour of a queue you cleared. Grey is the honest
            // one for a queue you put down — nothing is wrong, and nothing
            // has been dealt with either. The longer cycles are the rest of
            // the tell: the mark hangs around twice as long and the bob is
            // half the rate, so this reads as deeper sleep rather than as a
            // different character.
            //
            // A pilot light rather than `out`. The fire is banked, not gone:
            // there is still a queue, and it is coming back.
            return SpriteStyle(eyes: .shut,
                               marks: [.zzz, .zzz, .zzz, .zzz, .zzz, .zzz, .none, .none],
                               health: .neutral,
                               bob: [0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1],
                               breath: .pilot)
        case .stirring:
            // One eye open, because something you parked is about to come
            // back. `glance` is the sideways look the nudging mood uses, and
            // it is exactly right here for a different reason: he is not
            // looking at you, he is looking at the thing that is about to
            // land.
            return SpriteStyle(eyes: .glance, marks: [.zzz, .none, .none, .none],
                               health: .running,
                               bob: [0, 0, 1, 1],
                               breath: .pilot)
        case .idle:
            // The one mood with a longer cycle than it strictly needs: the
            // sweep runs off the frame counter, so a one-frame bob would hold
            // the body still while the beam crossed it.
            return SpriteStyle(eyes: .open, marks: [.none],
                               health: .running,
                               bob: [0, 0, 0, 0, 1, 1, 1, 1, 0, 0, 0, 0],
                               breath: .pilot)
        case .nudging:
            return SpriteStyle(eyes: .glance, marks: [.bang, .bang, .none],
                               health: .attention, bob: [0, 0, 1, 1],
                               breath: .flare)
        case .alarmed:
            return SpriteStyle(eyes: .wide, marks: [.bang, .none],
                               health: .bad, bob: [0, 1],
                               breath: .blast)
        case .working:
            // The one state that is literally a scan. The mark sweeps the
            // gutter and the beam sweeps the character, and a longer cycle so
            // the body is not holding still underneath a moving beam.
            return SpriteStyle(eyes: .shut,
                               marks: [.scanLeft, .scanMiddle, .scanRight],
                               health: .running,
                               bob: [0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1],
                               breath: .steady)
        case .proud:
            // Shares `steady` with `working`, which is the one collision the
            // six settings force on seven moods. Picked here because these
            // two are the pair that least needs telling apart by the fire:
            // nothing is wrong in either, and they are already a different
            // colour, eye, mark and sweep from each other.
            return SpriteStyle(eyes: .open, marks: [.spark, .none],
                               health: .good, bob: [0, 0, 1, 1],
                               breath: .steady)
        case .lost:
            return SpriteStyle(eyes: .dead, marks: [.query],
                               health: .neutral, bob: [0],
                               breath: .gutter)
        }
    }

    /// Whether this mood can occur while the review list is empty — which is
    /// exactly when the empty-state mascot is the one on screen.
    public var reachableWhenListEmpty: Bool {
        switch self {
        case .asleep, .dozing, .stirring, .working, .proud, .lost: return true
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
    case waking, held, startled, cheered

    /// Which reaction wins, given everything happening to the panel at once.
    ///
    /// Pure, so the truth table is pinned without a window — and a function
    /// rather than three writers racing for one property. Hover, press and
    /// events arrive independently, so last-write-wins loses in both
    /// directions: a release while the pointer is still over the badge would
    /// clear the hover, and a hover-out mid-drag would cancel the press.
    ///
    /// Order is the argument. A hand on the badge is the most immediate thing
    /// happening to it, so it outranks a review landing; a review landing is
    /// news, so it outranks a pointer merely resting there.
    public static func resolve(pressed: Bool,
                               event: Reaction?,
                               hovering: Bool) -> Reaction? {
        if pressed { return .held }
        if let event { return event }
        return hovering ? .waking : nil
    }

    public func style(tint: Health) -> SpriteStyle {
        switch self {
        case .waking:
            return SpriteStyle(eyes: .open, marks: [.none], health: tint, bob: [0, 0, 1, 1])
        case .held:
            return SpriteStyle(eyes: .wide, marks: [.none], health: tint, bob: [1])
        case .startled:
            return SpriteStyle(eyes: .wide, marks: [.bang, .none],
                               health: .attention, bob: [0, 2, 1, 0])
        case .cheered:
            // `startled`'s counterpart, and deliberately its mirror: the same
            // hop, a spark where the bang is, and green instead of amber.
            // There was a reaction for bad news arriving and none at all for
            // the one unambiguously good thing that happens — something of
            // yours going in.
            //
            // It ignores the tint it is handed, as `startled` does. Both are
            // news about one event rather than a reading of the queue, and a
            // merge is green whatever the rest of the drawer looks like.
            return SpriteStyle(eyes: .open, marks: [.spark, .none],
                               health: .good, bob: [0, 2, 1, 0])
        }
    }
}
