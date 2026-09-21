import Foundation

/// What the shelf remembers between launches.
///
/// Keyed by raw string rather than by `TrophyID` throughout, deliberately.
/// A trophy dropped from a future roster would otherwise fail to decode, and
/// `Codable` fails a whole value rather than a field — one retired id would
/// take somebody's entire shelf with it. Unknown keys are simply carried and
/// never shown.
public struct TrophyState: Codable, Equatable, Sendable {

    /// Earned trophies, and when. The date is not shown anywhere yet; it is
    /// stored because it cannot be recovered later, and a shelf that knows
    /// only *that* you did something is a worse record than one that knows
    /// when.
    public var unlocked: [String: Date] = [:]

    /// Tallies that outlive a refresh — how many times the queue has been
    /// cleared, and nothing else so far.
    public var counters: [String: Int] = [:]

    /// One-off facts the app has witnessed: a badge corner parked in, a
    /// mascot shown. Facts rather than trophies, because several rules read
    /// the same fact and none of them should have to unlock to remember it.
    public var flags: Set<String> = []

    /// False until the first evaluation has run.
    ///
    /// This one bit is what makes the backfill silent. Installing this feature
    /// into a working setup satisfies a dozen rules at once, and a dozen
    /// banners over whatever you were doing is a worse introduction than no
    /// introduction — so the first pass fills the shelf without saying
    /// anything, and everything after it announces itself.
    public var established = false

    /// Earned but not yet looked at. The dot on the header button.
    public var unseen: Set<String> = []

    /// The last calendar day the app was seen running, `yyyy-MM-dd`.
    ///
    /// A single day rather than a set of them: the run counter only needs to
    /// know whether today is a new one, and a set would grow by an entry a
    /// day forever to answer the same question.
    public var lastDay: String?

    public init() {}
}

/// The facts the app witnesses and the shelf remembers.
///
/// Strings rather than an enum because they are persisted, and an enum
/// invites renaming. Gathered here so the side that *records* a fact and the
/// side that *reads* it cannot disagree about its spelling — a mismatch there
/// would be a trophy that silently never unlocks.
public enum TrophyFact {
    public static func mascotSeen(_ id: MascotID) -> String { "mascot.\(id.rawValue)" }
    public static let cornerPrefix = "corner."
    public static func badgeCorner(_ corner: String) -> String { cornerPrefix + corner }
    public static let usedStackedFilter = "used.stackedFilter"
    public static let installedOfferedUpdate = "update.installed"
}

extension TrophyState {

    public func isUnlocked(_ id: TrophyID) -> Bool {
        unlocked[id.rawValue] != nil
    }

    public func unlockedAt(_ id: TrophyID) -> Date? {
        unlocked[id.rawValue]
    }

    /// The earned set, with any id this build no longer knows about dropped.
    public var unlockedIDs: Set<TrophyID> {
        Set(unlocked.keys.compactMap(TrophyID.init(rawValue:)))
    }

    public var hasUnseen: Bool { !unseen.isEmpty }

    public var unseenCount: Int { unseen.count }

    /// Called when the room is opened: everything earned has now been looked
    /// at. Not per-trophy — the room shows the whole shelf at once, so
    /// anything subtler would be a lie about what the eye did.
    public mutating func markAllSeen() {
        unseen.removeAll()
    }

    /// Records something the app watched happen. Idempotent, and cheap
    /// enough to call on every occurrence rather than only the first.
    public mutating func record(_ fact: String) {
        flags.insert(fact)
    }

    public func has(_ fact: String) -> Bool {
        flags.contains(fact)
    }

    /// How many separate days this app has been seen running.
    public var runningDays: Int { count(Counters.runningDays) }

    public enum Counters {
        public static let runningDays = "running.days"
        public static let queueCleared = "queue.cleared"
    }

    mutating func unlock(_ id: TrophyID, at date: Date) {
        guard unlocked[id.rawValue] == nil else { return }
        unlocked[id.rawValue] = date
        unseen.insert(id.rawValue)
    }

    public mutating func bump(_ counter: String) {
        counters[counter, default: 0] += 1
    }

    public func count(_ counter: String) -> Int {
        counters[counter] ?? 0
    }

}

extension TrophyState {

    /// Every trophy at once, for looking at the room as a finished thing.
    ///
    /// Debug only — see `Log.fakeTrophies`. Thirty drawings only work as a
    /// set if they can be seen as one, and earning them honestly to find out
    /// whether two of the greens fight is not a way to spend an afternoon.
    public static func everythingUnlocked(at date: Date) -> TrophyState {
        var state = TrophyState()
        state.established = true
        for trophy in Trophy.all {
            state.unlocked[trophy.id.rawValue] = date
        }
        return state
    }

    /// Round-trips through JSON, which is how `Prefs` stores it.
    ///
    /// A single blob rather than a key per trophy: the whole thing is written
    /// on every refresh, and thirty `UserDefaults` writes to say nothing
    /// changed is thirty more than one.
    public static func decoded(from data: Data?) -> TrophyState {
        guard let data, let state = try? JSONDecoder().decode(TrophyState.self, from: data)
        else { return TrophyState() }
        return state
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
