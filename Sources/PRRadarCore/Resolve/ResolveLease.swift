import Foundation

/// A claim on one worktree, held for as long as a resolve run is using it.
///
/// **Kept outside the tree**, unlike the automatic-review sweep's owner marker
/// (`Workspace.ownerMarker`), which is written *inside* the checkout it claims.
/// That is right there and wrong here for the same reason: a review worktree is
/// a throwaway in `/tmp` that PR Radar created and will delete, so a stray file
/// in it costs nothing. This runs in the developer's own checkout, where a
/// stray `.pr-radar-owner` would be an untracked file sitting next to work the
/// skill is told to stage selectively — and the one thing this feature must not
/// do is put something in somebody's repository that they did not put there.
///
/// So it lives in Application Support, keyed by a hash of the tree's path.
public struct ResolveLease: Codable, Equatable, Sendable {
    public var appPID: Int32
    /// The `claude` process itself, when it is known.
    ///
    /// Usually nil, because `ProcessRunner` does not hand its child's pid back
    /// and widening it to do so would be a change to the path every review also
    /// takes. `owner` therefore falls back to `appPID`, which answers the
    /// question that actually matters at launch — *is anybody still using this
    /// tree* — correctly in both directions: a previous launch's pid is gone,
    /// and a second copy of PR Radar running alongside this one is not.
    public var claudePID: Int32?
    public var startedAt: Date
    public var repo: String
    public var number: Int
    public var branch: String
    public var treePath: String
    /// What the branch was at before anything ran. The field that makes an
    /// abandoned run diagnosable.
    public var preRunOid: String?
    public var mode: ResolveMode

    public init(appPID: Int32, claudePID: Int32? = nil, startedAt: Date = Date(),
                repo: String, number: Int, branch: String, treePath: String,
                preRunOid: String? = nil, mode: ResolveMode) {
        self.appPID = appPID
        self.claudePID = claudePID
        self.startedAt = startedAt
        self.repo = repo
        self.number = number
        self.branch = branch
        self.treePath = treePath
        self.preRunOid = preRunOid
        self.mode = mode
    }

    /// Who, if anyone, is still using a tree.
    ///
    /// The same three-case shape, and the same `kill(pid, 0)` reasoning, as
    /// `Workspace.WorktreeOwner`: the signal is not sent, it only reports
    /// whether the process is there. A recycled pid reads as `live`, which
    /// leaves a lease standing that could have been cleared — the harmless way
    /// round, and the reason the test is framed this way rather than the other.
    public enum Holder: Equatable, Sendable {
        case live
        case abandoned
        case none
    }

    /// The pid to ask about. The session's own when it is known, and otherwise
    /// the app that started it.
    public var owningPID: Int32 { claudePID ?? appPID }

    /// Whether anybody is still using the tree this lease claims.
    ///
    /// `alive` is supplied rather than tested here so the rule stays pure; the
    /// caller passes `kill(pid, 0) == 0`, which signals nothing and only reports
    /// whether the process is there. A recycled pid reads as `live`, which
    /// leaves a lease standing that could have been cleared — the harmless way
    /// round to be wrong, and the reason the test is framed this way.
    public func holder(alive: (Int32) -> Bool, selfPID: Int32) -> Holder {
        // Our own lease is not somebody else holding the tree.
        guard owningPID != selfPID else { return .none }
        return alive(owningPID) ? .live : .abandoned
    }

    /// A stable filename for a path, without putting the path in the filename —
    /// which would be unbounded and would leak the user's directory layout into
    /// a place it does not need to be.
    public static func filename(forTree path: String) -> String {
        "\(SimpleHash.hex(path)).json"
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    public static func decoded(from data: Data?) -> ResolveLease? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(ResolveLease.self, from: data)
    }
}

/// A small, stable, non-cryptographic hash, for naming a file after a path.
///
/// FNV-1a rather than anything from CryptoKit: the only requirements are that
/// the same path gives the same name every launch and that two paths are
/// unlikely to collide. Nothing here is a security boundary — a collision would
/// mean two worktrees sharing a lease, which refuses a run that could have
/// proceeded rather than permitting one that should not have.
public enum SimpleHash {
    public static func hex(_ text: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return String(format: "%016llx", hash)
    }
}
