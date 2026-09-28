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
}
