import Foundation

/// Finding the clone a pull request's code lives in.
///
/// PR Radar reviews in the user's own checkouts rather than cloning its own
/// copies: a developer's clone already has the remotes, the LFS objects and the
/// submodules their repo actually needs, and a background app quietly filling a
/// disk with shallow clones of every repo it sees is a worse neighbour than one
/// that says "I could not find this one".
public enum Workspace {

    /// Where `owner/repo` might live under a workspace root, in the order worth
    /// trying. Pure, so the layouts this supports are a list that can be argued
    /// with rather than a walk of somebody's home directory.
    ///
    /// Flat first (`~/Developer/repo`), because that is what most people have;
    /// then owner-nested, which is what anyone with two same-named repos ends
    /// up with; then the hyphenated form some tools produce.
    public static func candidates(root: String, repo: String) -> [String] {
        let base = (root as NSString).expandingTildeInPath
        let trimmed = base.hasSuffix("/") ? String(base.dropLast()) : base
        let parts = repo.split(separator: "/")
        guard parts.count == 2, !trimmed.isEmpty else { return [] }
        let owner = String(parts[0]), name = String(parts[1])
        return [
            "\(trimmed)/\(name)",
            "\(trimmed)/\(owner)/\(name)",
            "\(trimmed)/\(owner)-\(name)",
        ]
    }

    /// The `owner/repo` a git remote URL names, or nil if it does not name one.
    ///
    /// Matching a checkout to a pull request by its *remote* rather than by the
    /// name of the folder it sits in is the only thing that actually works.
    /// Folder names are a convention, and a common one is to have none: a
    /// worktree is usually named after the branch, so a directory full of them
    /// contains a dozen checkouts of one repository and not one of them is
    /// called after it. Renamed clones and the `owner-repo` layouts have the
    /// same problem. The remote is what the checkout says about itself.
    ///
    /// Handles the three spellings git hands out — `https://host/owner/repo.git`,
    /// `git@host:owner/repo.git`, and `ssh://git@host/owner/repo` — plus the
    /// optional `.git` and trailing slash on any of them.
    public static func repoSlug(fromRemote url: String) -> String? {
        var text = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasSuffix("/") { text = String(text.dropLast()) }
        if text.lowercased().hasSuffix(".git") { text = String(text.dropLast(4)) }

        // `git@host:owner/repo` — the colon is the separator, not a port.
        if !text.contains("://"), let colon = text.firstIndex(of: ":") {
            text = String(text[text.index(after: colon)...])
        } else if let range = text.range(of: "://") {
            // Drop the scheme, then the host, leaving the path.
            let afterScheme = String(text[range.upperBound...])
            guard let slash = afterScheme.firstIndex(of: "/") else { return nil }
            text = String(afterScheme[afterScheme.index(after: slash)...])
        }

        let parts = text.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 2 else { return nil }
        // The last two, so a self-hosted path prefix does not break it.
        let owner = parts[parts.count - 2], name = parts[parts.count - 1]
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        return "\(owner)/\(name)"
    }

    /// Whether a remote names this repository, ignoring case the way GitHub does.
    public static func remote(_ url: String, names repo: String) -> Bool {
        guard let slug = repoSlug(fromRemote: url) else { return false }
        return slug.lowercased() == repo.lowercased()
    }

    /// The prefix every throwaway review checkout is named with.
    ///
    /// A shared constant rather than a literal at the point the worktree is
    /// created, because the launch-time sweep that removes the ones a killed
    /// app left behind has to recognise exactly what the creating side
    /// produces. Two spellings of the same string is how a reaper quietly
    /// stops matching and the litter comes back.
    public static let worktreePrefix = "pr-radar-"

    /// What to call the throwaway worktree for one pull request.
    ///
    /// `token` keeps two checkouts of the same PR from colliding — a re-run can
    /// begin while the last one's directory is still being removed.
    public static func worktreeName(forPR number: Int, token: String) -> String {
        "\(worktreePrefix)\(number)-\(token)"
    }

    /// Whether a path is one of ours, and so safe to delete unasked.
    ///
    /// Matched on the last component only. Testing the whole path would sweep
    /// up every checkout belonging to anyone whose temporary directory happens
    /// to sit inside a folder whose name starts the same way.
    public static func isWorktree(path: String) -> Bool {
        (path as NSString).lastPathComponent.hasPrefix(worktreePrefix)
    }

    /// The file a review leaves in its worktree naming the process that owns it.
    ///
    /// A dotfile inside the checkout rather than a sibling beside it, so it goes
    /// when the tree goes and cannot itself become the litter. It is untracked
    /// and the review diffs a commit range, so it never reaches a finding.
    public static let ownerMarker = ".pr-radar-owner"

    /// Who, if anyone, is still using a review worktree.
    public enum WorktreeOwner: Equatable, Sendable {
        /// The marker names a process that is still running.
        case live
        /// The marker names a process that has gone.
        case abandoned
        /// No marker — written by a build from before there was one.
        case unmarked
    }

    /// Whether a review worktree may be deleted.
    ///
    /// The sweep cannot simply take everything it finds. `make run` starts an
    /// unbundled debug copy *alongside* the installed one — the app is built to
    /// allow exactly that — and the two share one temporary directory, so a
    /// launching copy that deleted every worktree it saw would cut the legs off
    /// a review the other copy was in the middle of.
    ///
    /// An unmarked tree is given a grace period instead of being trusted or
    /// condemned outright. It cannot be matched to a process, so the only thing
    /// known about it is its age, and no live review can be older than the
    /// fifteen-minute timeout that ends one. The default leaves double that.
    public static func isReapable(_ owner: WorktreeOwner,
                                  age: TimeInterval,
                                  grace: TimeInterval = 1_800) -> Bool {
        switch owner {
        case .live: return false
        case .abandoned: return true
        case .unmarked: return age > grace
        }
    }

    /// The ref a fetched pull request head is parked on.
    ///
    /// Its own namespace rather than a branch: `refs/pr-radar/*` cannot collide
    /// with anything the user has, does not show up in their branch list, and
    /// makes it obvious who left it there.
    public static func ref(forPR number: Int) -> String { "refs/pr-radar/\(number)" }

    /// What to fetch, and where to put it.
    public static func fetchRefspec(forPR number: Int) -> String {
        "pull/\(number)/head:\(ref(forPR: number))"
    }

    /// Where a pull request's *base* branch is parked.
    ///
    /// Its own ref, and fetched per pull request, because the base is a
    /// property of the pull request and not of the repository. Reviewing
    /// against the default branch instead is not a near-miss: a pull request
    /// onto a long-running sprint branch then appears to change every file
    /// that branch has touched since it forked, and the map of what can carry
    /// an inline comment is wrong by two orders of magnitude.
    public static func baseRef(forPR number: Int) -> String {
        "refs/pr-radar/base-\(number)"
    }

    /// Fetching that base branch into it.
    public static func baseRefspec(branch: String, forPR number: Int) -> String {
        "\(branch):\(baseRef(forPR: number))"
    }
}
