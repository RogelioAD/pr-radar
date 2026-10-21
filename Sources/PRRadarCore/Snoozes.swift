import Foundation

/// How long a row is being put down for.
///
/// Three, and all of them absolute times rather than durations. "For an hour"
/// is the one that reads as a duration and it is stored as a wake time like
/// the others, because a duration has to be counted from something and the
/// only honest something is the moment you pressed it — which is exactly what
/// an absolute time already records.
public enum SnoozeOption: String, CaseIterable, Sendable {
    case anHour
    case tomorrow
    case nextWeek

    /// What counts as morning. One number, so the two options that mean
    /// "morning" cannot drift into meaning different ones.
    public static let morningHour = 9

    public var label: String {
        switch self {
        case .anHour: return "For an hour"
        case .tomorrow: return "Until tomorrow morning"
        case .nextWeek: return "Until Monday morning"
        }
    }

    public func wake(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .anHour:
            return now.addingTimeInterval(3_600)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
            return Self.morning(of: tomorrow, calendar: calendar)
        case .nextWeek:
            return Self.morning(of: Self.nextMonday(after: now, calendar: calendar),
                                calendar: calendar)
        }
    }

    static func morning(of day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: morningHour, minute: 0, second: 0, of: day)
            ?? day
    }

    /// The Monday strictly after today.
    ///
    /// Strictly, so that pressing it on a Monday parks the row for the week
    /// rather than for the next hour — the label says Monday because you are
    /// putting it down until the week turns over, and a Monday nine o'clock
    /// that is forty minutes away is not what anybody meant by it.
    static func nextMonday(after now: Date, calendar: Calendar) -> Date {
        var candidate = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        for _ in 0..<7 {
            if calendar.component(.weekday, from: candidate) == 2 { return candidate }
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}

/// Review requests put down until later.
///
/// The list's rule is that a pull request leaves it when you comment on it or
/// review it, and that rule is what makes it honest. It also leaves you no way
/// to say *not until Thursday* except by writing a comment you do not mean,
/// which is lying to the one list that does not lie to you.
///
/// Keyed on the **ping key**, which carries the timestamp of the request it
/// answers — so a re-request is a new key, and a row you put down last week
/// comes straight back when somebody asks you again. That is the same choice
/// the auto-review pin makes, for the same reason: a key with a request in it
/// cannot outlive the request.
///
/// A sleeping row leaves the badge as well as the list. The badge answers
/// "what is waiting on me", and a pull request you have deliberately parked
/// until Monday is not waiting on you now — nagging you about it is the exact
/// thing you switched off. What the count must never be is *silently* short,
/// which is why the bar says how many are asleep whenever any are.
public struct Snoozes: Equatable, Sendable, Codable {
    /// Ping key to wake time.
    private var until: [String: Date]

    public init(_ until: [String: Date] = [:]) { self.until = until }

    public var isEmpty: Bool { until.isEmpty }

    public func wakeTime(for key: String) -> Date? { until[key] }

    public func isAsleep(_ key: String, now: Date = Date()) -> Bool {
        guard let wake = until[key] else { return false }
        return wake > now
    }

    public mutating func snooze(_ key: String, until wake: Date) {
        until[key] = wake
    }

    public mutating func wake(_ key: String) {
        until.removeValue(forKey: key)
    }

    /// Forgets what there is no longer any reason to remember.
    ///
    /// Two kinds of rubbish, dropped for two different reasons. A wake time in
    /// the past has already done its job; and a key the fetch no longer
    /// returns belongs to a pull request that has been reviewed, merged or
    /// closed, which will never be asked about again.
    ///
    /// `known` is the set of keys the round actually saw, and passing nil
    /// means *this round did not see everything* — a fetch that failed, or an
    /// account that came back short. Then only the expired half runs, because
    /// pruning against a partial list would quietly wake every row belonging
    /// to the account that was unreachable.
    public mutating func prune(known: Set<String>?, now: Date = Date()) {
        until = until.filter { key, wake in
            guard wake > now else { return false }
            guard let known else { return true }
            return known.contains(key)
        }
    }

    // MARK: - Splitting a list

    public func awake(_ items: [ReviewItem], now: Date = Date()) -> [ReviewItem] {
        items.filter { !isAsleep($0.pingKey, now: now) }
    }

    public func asleep(_ items: [ReviewItem], now: Date = Date()) -> [ReviewItem] {
        items.filter { isAsleep($0.pingKey, now: now) }
    }

    // MARK: - Persistence

    public static func decoded(from data: Data?) -> Snoozes {
        guard let data,
              let decoded = try? JSONDecoder().decode([String: Date].self, from: data)
        else { return Snoozes() }
        return Snoozes(decoded)
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(until) }
}
