import Foundation

/// The reviewers whose approval unblocks a PR, chosen per repository.
///
/// Held as logins because that is what the API returns. A repo with no leads
/// has no lead gate: nothing lead-related shows on its PRs.
public enum Leads {
    /// Short names for chips — a full GitHub login is often too long for a row.
    /// Anything not listed falls back to the login itself.
    public static let displayNames: [String: String] = [:]

    public static func shortName(for login: String) -> String {
        displayNames[login] ?? login
    }

    /// The default host, and the one an unqualified key is assumed to name.
    public static let defaultHost = "github.com"

    /// Repo keys are `host/owner/repo`, lowercased.
    ///
    /// Host-qualified because `acme/app` on github.com and `acme/app` on an
    /// Enterprise host are two different repositories with two different sets
    /// of people, and the app can now be logged in to both at once. Keyed on
    /// `owner/repo` alone they would silently share one lead list, and the
    /// first repo to be configured would decide who unblocks the other.
    ///
    /// Lowercased because GitHub treats all three parts case-insensitively.
    public static func key(host: String, repo: String) -> String {
        "\(host)/\(repo)".lowercased()
    }

    /// Trims whitespace and a leading `@`. Nil when nothing is left.
    public static func normalize(login: String) -> String? {
        var text = login.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("@") { text.removeFirst() }
        return text.isEmpty ? nil : text
    }

    /// Falls back to the unqualified key, which is what this was stored under
    /// before hosts were part of it. Read-only: anything written goes back
    /// qualified, so a list migrates the first time it is edited.
    public static func leads(for repo: String, host: String = defaultHost,
                             in all: [String: [String]]) -> [String] {
        all[key(host: host, repo: repo)] ?? all[repo.lowercased()] ?? []
    }

    /// Adds a lead, ignoring case-insensitive duplicates.
    public static func add(_ login: String, to repo: String,
                           host: String = defaultHost,
                           in all: [String: [String]]) -> [String: [String]] {
        guard let login = normalize(login: login) else { return all }
        var result = all
        var list = leads(for: repo, host: host, in: all)
        guard !list.contains(where: { $0.caseInsensitiveCompare(login) == .orderedSame })
        else { return all }
        list.append(login)
        result[key(host: host, repo: repo)] = list
        return result
    }

    /// Removes a lead, dropping the repo's key once its list is empty.
    public static func remove(_ login: String, from repo: String,
                              host: String = defaultHost,
                              in all: [String: [String]]) -> [String: [String]] {
        var result = all
        let list = leads(for: repo, host: host, in: all).filter {
            $0.caseInsensitiveCompare(login) != .orderedSame
        }
        let qualified = key(host: host, repo: repo)
        result[qualified] = list.isEmpty ? nil : list
        // The pre-host key, if this list is migrating off it, so removing a
        // lead cannot leave the old entry behind to be read back as live.
        if all[repo.lowercased()] != nil { result[repo.lowercased()] = nil }
        return result
    }
}
