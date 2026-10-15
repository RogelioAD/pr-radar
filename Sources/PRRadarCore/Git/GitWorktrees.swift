import Foundation

/// `git worktree list --porcelain`, read rather than guessed at.
///
/// The automatic-review sweep asks a different question of worktrees — "is this
/// one of mine, and may I delete it" — and answers it from a path prefix and a
/// pid marker (`Workspace.isWorktree`, `Workspace.isReapable`). None of that
/// applies here. Resolve runs in the developer's *own* checkout, which it did
/// not create and must never delete, so the only question is which of their
/// trees currently holds a branch. Git knows; this reads the answer.
///
/// Pure, because the format is the part worth being sure about: blank-line
/// separated blocks of `worktree <path>`, `HEAD <oid>`, then one of
/// `branch <ref>` or `detached`, with `bare`, `locked [reason]` and
/// `prunable [reason]` appearing as needed.
public enum GitWorktrees {

    public struct Entry: Equatable, Sendable {
        public let path: String
        public let head: String?
        /// The full ref — `refs/heads/feat/foo` — never shortened here. A
        /// branch may contain slashes, so shortening by taking the last path
        /// component turns `feat/foo` into `foo` and matches the wrong tree.
        public let branch: String?
        public let isBare: Bool
        public let isLocked: Bool
        public let lockReason: String?
        public let isPrunable: Bool

        public init(path: String, head: String? = nil, branch: String? = nil,
                    isBare: Bool = false, isLocked: Bool = false,
                    lockReason: String? = nil, isPrunable: Bool = false) {
            self.path = path
            self.head = head
            self.branch = branch
            self.isBare = isBare
            self.isLocked = isLocked
            self.lockReason = lockReason
            self.isPrunable = isPrunable
        }

        /// The branch without its `refs/heads/` prefix, for saying out loud.
        public var branchName: String? {
            guard let branch else { return nil }
            let prefix = "refs/heads/"
            return branch.hasPrefix(prefix) ? String(branch.dropFirst(prefix.count)) : branch
        }
    }

    public static func parse(porcelain: String) -> [Entry] {
        var entries: [Entry] = []
        var path: String?
        var head: String?
        var branch: String?
        var bare = false
        var locked = false
        var lockReason: String?
        var prunable = false

        func flush() {
            if let path {
                entries.append(Entry(path: path, head: head, branch: branch,
                                     isBare: bare, isLocked: locked,
                                     lockReason: lockReason, isPrunable: prunable))
            }
            path = nil; head = nil; branch = nil
            bare = false; locked = false; lockReason = nil; prunable = false
        }

        for rawLine in porcelain.replacingOccurrences(of: "\r\n", with: "\n")
                                .components(separatedBy: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { flush(); continue }

            let (key, value) = split(line)
            switch key {
            // A new `worktree` line without an intervening blank one still
            // starts a new block. Git always emits the blank, but trusting it
            // would merge two trees into one entry if it ever did not.
            case "worktree": flush(); path = value
            case "HEAD": head = value
            case "branch": branch = value
            case "detached": branch = nil
            case "bare": bare = true
            case "locked": locked = true; lockReason = value.isEmpty ? nil : value
            case "prunable": prunable = true
            default: break
            }
        }
        flush()
        return entries
    }

    private static func split(_ line: String) -> (String, String) {
        guard let space = line.firstIndex(of: " ") else { return (line, "") }
        return (String(line[..<space]),
                String(line[line.index(after: space)...]).trimmingCharacters(in: .whitespaces))
    }

    /// Why a branch could not be resolved to one tree to work in.
    public enum Trouble: Error, Equatable, Sendable {
        /// Git permits a branch in exactly one worktree, so this should be
        /// impossible — which is why it is reported rather than resolved by
        /// picking the first. A repository in a state git says cannot happen is
        /// not one to start editing files in.
        case severalTrees([String])
        case locked(path: String, reason: String?)
        case bare(path: String)
    }

    /// The tree holding `branch`, or nil when nothing does — which is a refusal
    /// rather than an invitation to check it out somewhere.
    public static func holding(branch: String,
                               in entries: [Entry]) -> Result<Entry?, Trouble> {
        let wanted = branch.hasPrefix("refs/heads/") ? branch : "refs/heads/\(branch)"
        let matches = entries.filter { $0.branch == wanted }
        guard let first = matches.first else { return .success(nil) }
        guard matches.count == 1 else {
            return .failure(.severalTrees(matches.map(\.path).sorted()))
        }
        if first.isBare { return .failure(.bare(path: first.path)) }
        if first.isLocked {
            return .failure(.locked(path: first.path, reason: first.lockReason))
        }
        return .success(first)
    }
}
