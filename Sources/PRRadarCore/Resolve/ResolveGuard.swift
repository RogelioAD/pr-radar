import Foundation

/// Why a resolve run will not start.
///
/// Every case carries the sentence the row shows, because the sentence *is* the
/// feature here. Automatic review can afford a vague skip reason — the cost of
/// one is a review that did not happen. This refuses to edit somebody's working
/// tree, and a refusal that does not say which tree, or what about it, leaves
/// them with a greyed-out button and nowhere to go.
public enum ResolveBlock: Equatable, Sendable {
    case noClaude
    case noSkill
    case notAllowed(repo: String)
    case fork(owner: String)
    case noWorkspace
    case noClone(repo: String)
    case notCheckedOut(branch: String, clone: String)
    case severalTrees(branch: String, paths: [String])
    case lockedTree(path: String, reason: String?)
    case bareTree(path: String)
    case operationInProgress(GitOperation, path: String)
    case dirty(path: String, count: Int)
    case conflicted(path: String, count: Int)
    case headMismatch(path: String, local: String, expected: String)
    case noUpstream(branch: String, path: String)
    case alreadyRunning(path: String)

    /// What the row says. One sentence, and where there is a thing to go and
    /// do, it names it.
    public var reason: String {
        switch self {
        case .noClaude:
            return "Claude Code was not found"
        case .noSkill:
            return "No resolve skill is configured"
        case .notAllowed(let repo):
            return "\(RepoScope.shortName(repo)) is not ticked for resolving"
        case .fork(let owner):
            return "The branch is on \(owner)'s fork, which this cannot push to"
        case .noWorkspace:
            return "No clones folder is set"
        case .noClone(let repo):
            return "No local clone of \(RepoScope.shortName(repo))"
        case .notCheckedOut(let branch, _):
            return "\(branch) is not checked out anywhere"
        case .severalTrees(let branch, let paths):
            return "\(branch) is checked out in \(paths.count) trees"
        case .lockedTree(let path, let reason):
            return reason.map { "That worktree is locked — \($0)" }
                ?? "The worktree at \(Self.short(path)) is locked"
        case .bareTree:
            return "That checkout is bare, so there is nothing to edit"
        case .operationInProgress(let operation, let path):
            return "\(operation.spoken.capitalizedFirst) is in progress in \(Self.short(path))"
        case .dirty(let path, let count):
            return "\(count) uncommitted change\(count == 1 ? "" : "s") in \(Self.short(path))"
        case .conflicted(let path, let count):
            return "\(count) conflicted file\(count == 1 ? "" : "s") in \(Self.short(path))"
        case .headMismatch(_, let local, let expected):
            return "That checkout is at \(Self.oid(local)); the PR is at \(Self.oid(expected))"
        case .noUpstream(let branch, _):
            return "\(branch) has no upstream to push to"
        case .alreadyRunning(let path):
            return "A resolve run is already working in \(Self.short(path))"
        }
    }

    /// What to do about it, when there is something. Shown as the row's tooltip
    /// rather than crammed into the chip.
    public var remedy: String? {
        switch self {
        case .noClaude:
            return "Point the wand room at the claude binary."
        case .noSkill:
            return "Name a resolve skill in the wand room."
        case .notAllowed:
            return "Tick it under Repositories in the wand room."
        case .fork:
            return "Resolve answers threads on branches you can push to. "
                 + "A fork's branch is the author's."
        case .noWorkspace:
            return "Pick the folder your clones live in, in the wand room."
        case .noClone(let repo):
            return "Clone \(repo) under your clones folder."
        case .notCheckedOut(let branch, let clone):
            return "Check it out first: git -C \(clone) worktree add ../\(Self.slug(branch)) \(branch)"
        case .severalTrees(_, let paths):
            return "Git allows one: " + paths.joined(separator: ", ")
        case .lockedTree(let path, _):
            return "git -C \(path) worktree unlock"
        case .bareTree:
            return nil
        case .operationInProgress(let operation, let path):
            return operation == .indexLocked
                ? "Another git command is running there, or one died and left "
                  + "\(path)/.git/index.lock behind."
                : "Finish or abort it in \(path) first."
        case .dirty(let path, _):
            return "Commit or move them first. Resolve will not touch a tree "
                 + "with work in it — \(path)"
        case .conflicted(let path, _):
            return "Finish the merge in \(path) first."
        case .headMismatch:
            return "Pull, or push what is local, so the checkout and the pull "
                 + "request agree before anything edits it."
        case .noUpstream(let branch, let path):
            return "git -C \(path) push -u origin \(branch)"
        case .alreadyRunning:
            return "One run per worktree. Wait for it, or quit it."
        }
    }

    /// Whether this is something the user can fix from inside the app. Those
    /// read as configuration; the rest read as the state of their checkout.
    public var isConfiguration: Bool {
        switch self {
        case .noClaude, .noSkill, .notAllowed, .noWorkspace: return true
        default: return false
        }
    }

    private static func short(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    private static func oid(_ value: String) -> String {
        String(value.prefix(7))
    }

    private static func slug(_ branch: String) -> String {
        branch.replacingOccurrences(of: "/", with: "-")
    }
}

/// Everything about the world a resolve run's guards depend on, gathered once.
///
/// A struct rather than a pile of arguments so the rule below is a pure
/// function over a value a test can construct — which is the division this
/// codebase already draws between `AutoReviewQueue` and the coordinator that
/// feeds it.
public struct ResolveProbe: Equatable, Sendable {
    public var claudePath: String?
    public var skill: String?
    public var isAllowed = false
    public var workspace: String?
    public var clone: String?
    public var worktrees: [GitWorktrees.Entry] = []
    public var localHead: String?
    public var status: GitStatus?
    public var operation: GitOperation?
    public var leaseHeldAt: String?

    public init() {}
}

/// The ordered rule. First refusal wins, and the order is the order in which
/// each becomes knowable: configuration before the filesystem, the filesystem
/// before the tree's contents.
public enum ResolveGuard {

    public static func evaluate(_ probe: ResolveProbe,
                                pr: MyPullRequest,
                                baseOwner: String? = nil) -> ResolveBlock? {
        // Configuration. Free to check, and the only kind the user fixes from
        // inside the app, so it is asked about first.
        guard probe.claudePath != nil else { return .noClaude }
        guard let skill = probe.skill, !skill.isEmpty else { return .noSkill }
        guard probe.isAllowed else { return .notAllowed(repo: pr.repo) }

        // A fork is refused before anything touches the disk: no amount of
        // local tidiness makes a branch you cannot push to pushable.
        let owner = baseOwner ?? pr.repo.split(separator: "/").first.map(String.init)
        if let head = pr.headRepositoryOwner, let owner, head != owner {
            return .fork(owner: head)
        }

        guard probe.workspace != nil else { return .noWorkspace }
        guard let clone = probe.clone else { return .noClone(repo: pr.repo) }

        let tree: GitWorktrees.Entry
        switch GitWorktrees.holding(branch: pr.headRefName, in: probe.worktrees) {
        case .success(let found):
            guard let found else {
                return .notCheckedOut(branch: pr.headRefName, clone: clone)
            }
            tree = found
        case .failure(.severalTrees(let paths)):
            return .severalTrees(branch: pr.headRefName, paths: paths)
        case .failure(.locked(let path, let reason)):
            return .lockedTree(path: path, reason: reason)
        case .failure(.bare(let path)):
            return .bareTree(path: path)
        }

        // Before anything about the tree's contents, because if somebody else
        // is working in it then everything else this would report is *their*
        // doing. A run that has committed leaves the head ahead of the pull
        // request, and reporting that as "your checkout is stale" sends the
        // user to fix a tree that is being used exactly as intended.
        if let held = probe.leaseHeldAt { return .alreadyRunning(path: held) }

        // Then: an unfinished rebase makes every other reading of the tree a
        // reading of a state nobody meant to leave.
        if let operation = probe.operation {
            return .operationInProgress(operation, path: tree.path)
        }

        if let status = probe.status {
            if !status.conflicted.isEmpty {
                return .conflicted(path: tree.path, count: status.conflicted.count)
            }
            if !status.tracked.isEmpty {
                return .dirty(path: tree.path, count: status.tracked.count)
            }
            // An upstream is what makes a reply true: the skill cites a sha,
            // and a sha is only true once it is somewhere other people can see.
            guard let upstream = status.upstream, !upstream.isEmpty else {
                return .noUpstream(branch: pr.headRefName, path: tree.path)
            }
        }

        // Both directions. Behind means the threads were written against code
        // this tree has not got; ahead means local commits nobody has seen,
        // which a run would silently build on and then push.
        if let local = probe.localHead, let expected = pr.headOid, local != expected {
            return .headMismatch(path: tree.path, local: local, expected: expected)
        }

        return nil
    }

    /// The guards that can be answered without touching the disk.
    ///
    /// What decides whether the button is drawn enabled at all. The rest need a
    /// probe, and a probe per row per poll would be a subprocess storm — so the
    /// row offers the press, and the press is where the tree is inspected.
    public static func configuration(_ probe: ResolveProbe,
                                     pr: MyPullRequest) -> ResolveBlock? {
        guard probe.claudePath != nil else { return .noClaude }
        guard let skill = probe.skill, !skill.isEmpty else { return .noSkill }
        guard probe.isAllowed else { return .notAllowed(repo: pr.repo) }
        return nil
    }
}

extension String {
    /// Capitalises only the first character, leaving the rest alone — unlike
    /// `capitalized`, which would turn "a cherry-pick" into "A Cherry-Pick".
    var capitalizedFirst: String {
        guard let first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
