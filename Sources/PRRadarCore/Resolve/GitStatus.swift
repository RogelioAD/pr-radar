import Foundation

/// `git status --porcelain=v2 --branch`, reduced to the question being asked:
/// is this tree safe for something else to start editing in.
///
/// **Untracked files are counted and do not block, and that is the whole point
/// of parsing rather than testing for empty output.** The obvious rule — refuse
/// unless `git status --porcelain` prints nothing — refuses every real
/// checkout. A repository with generated bindings deliberately untracked, a
/// `target/` or `build/` directory, an `.env`, a scratch file: all of them make
/// the output non-empty and none of them is work that a run could destroy.
/// What a run can destroy is a *tracked* change nobody has committed, so that
/// is what is counted.
public struct GitStatus: Equatable, Sendable {
    /// Tracked files changed, staged, deleted or renamed. The number that
    /// decides.
    public let tracked: [String]
    /// Files git is not tracking. Reported so the row can say what it saw, and
    /// deliberately not a reason to refuse.
    public let untracked: [String]
    /// Files in a conflicted state. Counted separately from `tracked` because
    /// the sentence a row should say is different: an unfinished merge is a
    /// state to get out of, not work to put somewhere.
    public let conflicted: [String]
    public let branch: String?
    public let upstream: String?
    public let ahead: Int
    public let behind: Int

    public init(tracked: [String] = [], untracked: [String] = [],
                conflicted: [String] = [], branch: String? = nil,
                upstream: String? = nil, ahead: Int = 0, behind: Int = 0) {
        self.tracked = tracked
        self.untracked = untracked
        self.conflicted = conflicted
        self.branch = branch
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
    }

    /// Whether a run may start here. Untracked files are not consulted.
    public var isSafeToWorkIn: Bool { tracked.isEmpty && conflicted.isEmpty }

    public static func parse(porcelainV2: String) -> GitStatus {
        var tracked: [String] = []
        var untracked: [String] = []
        var conflicted: [String] = []
        var branch: String?
        var upstream: String?
        var ahead = 0
        var behind = 0

        for rawLine in porcelainV2.replacingOccurrences(of: "\r\n", with: "\n")
                                  .components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let marker = fields.first else { continue }

            switch marker {
            case "#":
                guard fields.count >= 2 else { break }
                switch fields[1] {
                case "branch.head":
                    // "(detached)" is git's own word for no branch, not a name.
                    let name = fields.count > 2 ? String(fields[2]) : ""
                    branch = (name == "(detached)" || name.isEmpty) ? nil : name
                case "branch.upstream":
                    upstream = fields.count > 2 ? String(fields[2]) : nil
                case "branch.ab":
                    for field in fields.dropFirst(2) {
                        if field.hasPrefix("+") { ahead = Int(field.dropFirst()) ?? 0 }
                        if field.hasPrefix("-") { behind = Int(field.dropFirst()) ?? 0 }
                    }
                default: break
                }
            // Ordinary change, rename/copy. The path is the last field, which
            // is right for both: a rename prints `<new>\t<old>` and the new
            // name is the one worth naming.
            case "1", "2":
                if let path = trailingPath(of: line) { tracked.append(path) }
            case "u":
                if let path = trailingPath(of: line) { conflicted.append(path) }
            case "?":
                if let path = trailingPath(of: line) { untracked.append(path) }
            default: break
            }
        }

        return GitStatus(tracked: tracked, untracked: untracked,
                         conflicted: conflicted, branch: branch,
                         upstream: upstream, ahead: ahead, behind: behind)
    }

    /// The path at the end of a porcelain-v2 line.
    ///
    /// Everything before it is fixed-width fields, so the path is whatever
    /// follows them — and a rename puts the old name after a tab, which is
    /// dropped. Paths with spaces survive, which splitting on spaces would not.
    private static func trailingPath(of line: String) -> String? {
        let withoutOldName = line.split(separator: "\t").first.map(String.init) ?? line
        let fields = withoutOldName.split(separator: " ", omittingEmptySubsequences: true)
        guard let marker = fields.first else { return nil }
        // How many space-separated fields come before the path, by line kind.
        let leading: Int
        switch marker {
        case "1": leading = 8
        case "2": leading = 9
        case "u": leading = 10
        case "?": leading = 1
        default: return nil
        }
        guard fields.count > leading else { return nil }
        // Rejoined rather than taken as one field: a path may contain spaces.
        let path = fields.dropFirst(leading).joined(separator: " ")
        return path.isEmpty ? nil : path
    }
}

/// Something half-finished in the tree that a run must not start on top of.
///
/// Detected by asking the filesystem about git's own marker files rather than
/// by parsing status, because status does not report a rebase that has stopped
/// between commits — and that is exactly the state where an unattended run
/// would do the most damage.
public enum GitOperation: String, Equatable, Sendable, CaseIterable {
    case merge
    case rebase
    case cherryPick
    case revert
    case bisect
    case indexLocked

    /// Paths relative to the tree's git directory, any of which existing means
    /// this operation is in progress.
    public var markers: [String] {
        switch self {
        case .merge: return ["MERGE_HEAD"]
        case .rebase: return ["rebase-merge", "rebase-apply"]
        case .cherryPick: return ["CHERRY_PICK_HEAD"]
        case .revert: return ["REVERT_HEAD"]
        case .bisect: return ["BISECT_LOG"]
        case .indexLocked: return ["index.lock"]
        }
    }

    public var spoken: String {
        switch self {
        case .merge: return "a merge"
        case .rebase: return "a rebase"
        case .cherryPick: return "a cherry-pick"
        case .revert: return "a revert"
        case .bisect: return "a bisect"
        case .indexLocked: return "another git command"
        }
    }
}
