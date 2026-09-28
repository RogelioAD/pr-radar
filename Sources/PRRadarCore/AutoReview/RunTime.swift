import Foundation

/// How long a review took, and how long one has been going.
///
/// Its own type rather than another case in `TimeAgo`, because the two answer
/// different questions and want different shapes. `TimeAgo` says how long ago
/// something happened and rounds hard for it — under a minute it says "now",
/// which is the right answer for a review request and a useless one for a
/// stopwatch that has been running seven seconds.
public enum RunTime {

    /// A duration written the way a clock reads: `0:07`, `4:12`, `1:02:33`.
    ///
    /// Seconds are shown at every length. A review takes minutes, and a number
    /// that only moves once a minute does not look like it is measuring
    /// anything — the whole point of showing it while the work is in flight is
    /// that it visibly advances.
    ///
    /// Negatives clamp to zero: a machine whose clock has been put back should
    /// show `0:00` and not `-3:41`.
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        let (hours, minutes, secs) = (total / 3_600, (total % 3_600) / 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Spoken form, for the tooltip that explains the chip.
    public static func spoken(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        if total < 60 { return "\(total) second\(total == 1 ? "" : "s")" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        let hours = minutes / 60, rest = minutes % 60
        let head = "\(hours) hour\(hours == 1 ? "" : "s")"
        return rest == 0 ? head : "\(head) \(rest) minute\(rest == 1 ? "" : "s")"
    }

    /// How long a run has taken: to now while it is going, to the finish once
    /// it has stopped. nil when it never started, which is every record the
    /// queue has only thought about.
    ///
    /// A finished record measures to its own `finishedAt` rather than to the
    /// clock, so a review that took four minutes still says four minutes a week
    /// later — the number is a fact about the run, not about how long ago it
    /// was, which is what the age pill on the same row already says.
    public static func elapsed(startedAt: Date?,
                               finishedAt: Date?,
                               now: Date) -> TimeInterval? {
        guard let startedAt else { return nil }
        return max(0, (finishedAt ?? now).timeIntervalSince(startedAt))
    }
}
