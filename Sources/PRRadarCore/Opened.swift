import Foundation

/// Review requests you have opened and not yet dealt with.
///
/// Snoozing gave the list a way to say *not now*. There was never one for *I
/// am on it*: you open a pull request, read four hundred lines, get pulled
/// into something else, and the row you come back to is identical to one you
/// have never touched.
///
/// So opening a row records that it happened. It is deliberately the weakest
/// possible claim — it says you opened the thing, never that you read it or
/// got anywhere — because that is the only thing the app actually witnessed.
/// A row that has been open three days and still has not been reviewed is a
/// more useful nag than its ping age, and it is one you put there yourself.
///
/// Keyed on the **ping key**, like the snooze and the auto-review pin: a
/// re-request is a new key, so having opened last week's version of a pull
/// request is not a claim about the one you have just been handed.
public struct Opened: Equatable, Sendable, Codable {
    /// Ping key to the moment it was opened. The *first* time, not the last —
    /// see `open(_:at:)`.
    private var at: [String: Date]

    public init(_ at: [String: Date] = [:]) { self.at = at }

    public var isEmpty: Bool { at.isEmpty }

    public func openedAt(_ key: String) -> Date? { at[key] }

    public func wasOpened(_ key: String) -> Bool { at[key] != nil }

    /// Records an open, keeping the earliest.
    ///
    /// Opening a pull request for the fourth time is not a fresh start — it is
    /// the fourth time, and the interesting number is how long this has been
    /// going on. Keeping the latest would reset the clock every time you went
    /// back to it, which is exactly when it has most to say.
    public mutating func open(_ key: String, at when: Date = Date()) {
        guard let existing = at[key] else { at[key] = when; return }
        if when < existing { at[key] = when }
    }

    public mutating func forget(_ key: String) { at.removeValue(forKey: key) }

    /// Drops what the fetch no longer returns.
    ///
    /// Only that. There is no expiry here, where the snooze has one: a snooze
    /// is a promise about a time and goes stale on its own, where "you opened
    /// this" stays true until the pull request is dealt with — and being dealt
    /// with is exactly what takes it out of the fetch.
    ///
    /// nil means the round did not see everything, and then nothing is
    /// dropped, for the reason `Snoozes.prune` gives.
    public mutating func prune(known: Set<String>?) {
        guard let known else { return }
        at = at.filter { known.contains($0.key) }
    }

    // MARK: - What a row says

    /// `opened 3d ago`, or nil for a row you have not.
    public func label(for key: String, now: Date = Date()) -> String? {
        guard let when = at[key] else { return nil }
        return "opened \(TimeAgo.short(since: when, now: now)) ago"
    }

    /// Grey for a few hours, then amber.
    ///
    /// Not the staleness ladder the two clocks either side of it use. Those
    /// measure somebody waiting on somebody; this measures a thing you started
    /// and did not finish, and an afternoon of that is ordinary where four
    /// days of it is the point. One day, not three.
    public func health(for key: String, now: Date = Date()) -> Health {
        guard let when = at[key] else { return .neutral }
        return now.timeIntervalSince(when) >= 86_400 ? .attention : .neutral
    }

    public func help(for key: String, now: Date = Date()) -> String? {
        guard let when = at[key] else { return nil }
        return "You opened this \(TimeAgo.long(since: when, now: now)) and it is "
             + "still waiting on you. Reviewing it is what clears it."
    }

    // MARK: - Persistence

    public static func decoded(from data: Data?) -> Opened {
        guard let data,
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return Opened() }
        return Opened(decoded)
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(at) }
}
