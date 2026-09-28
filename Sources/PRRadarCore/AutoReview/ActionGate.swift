import Foundation

/// One mutation per row at a time.
///
/// Every button on a reviewed row is a network round trip, and for the second
/// or so it takes, nothing about the row changes: posting leaves the record at
/// `ready` until the mutation returns, so the row goes on drawing an enabled
/// "Post" button over a review that is already on its way. A second press there
/// recomposes the same review and submits it again, and GitHub has no opinion
/// about being asked twice — the pull request ends up carrying two identical
/// reviews, inline comments and all, a second apart. That is exactly how it
/// happened: two reviews, same body, same two threads, 18:50:12 and 18:50:13.
///
/// Dropped rather than queued, because the second press is the *same* press —
/// somebody prodding a button that looked like it had not worked, not somebody
/// asking for a second review. Queueing it would post twice a little later.
///
/// Keyed by ping rather than by pull request: two pings on one pull request are
/// two separate pieces of work, and the row is drawn per ping.
public struct ActionGate: Equatable, Sendable {
    private var inFlight: Set<String> = []

    public init() {}

    /// Claims a row, or reports that it is already claimed. The return value is
    /// the whole of the guard: `false` means somebody else got there first and
    /// this press does nothing.
    @discardableResult
    public mutating func begin(_ key: String) -> Bool {
        inFlight.insert(key).inserted
    }

    /// Releases a row, *however* the action ended. A failure that did not
    /// release would wedge the row shut with no way back short of a relaunch —
    /// worse than the double post it is guarding against, because at least the
    /// double post did the thing that was asked.
    public mutating func end(_ key: String) {
        inFlight.remove(key)
    }

    /// Whether this row has something in flight, so the buttons that started it
    /// can say so instead of inviting the second press.
    public func isActing(on key: String) -> Bool {
        inFlight.contains(key)
    }
}
