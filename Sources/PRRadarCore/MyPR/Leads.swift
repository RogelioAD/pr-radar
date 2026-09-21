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

    /// Repo keys are lowercase: GitHub treats `owner/repo` case-insensitively.
    public static func key(for repo: String) -> String {
        repo.lowercased()
    }

    /// Trims whitespace and a leading `@`. Nil when nothing is left.
    public static func normalize(login: String) -> String? {
        var text = login.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("@") { text.removeFirst() }
        return text.isEmpty ? nil : text
    }

    public static func leads(for repo: String, in all: [String: [String]]) -> [String] {
        all[key(for: repo)] ?? []
    }

    /// Adds a lead, ignoring case-insensitive duplicates.
    public static func add(_ login: String, to repo: String,
                           in all: [String: [String]]) -> [String: [String]] {
        guard let login = normalize(login: login) else { return all }
        var result = all
        var list = leads(for: repo, in: all)
        guard !list.contains(where: { $0.caseInsensitiveCompare(login) == .orderedSame })
        else { return all }
        list.append(login)
        result[key(for: repo)] = list
        return result
    }

    /// Removes a lead, dropping the repo's key once its list is empty.
    public static func remove(_ login: String, from repo: String,
                              in all: [String: [String]]) -> [String: [String]] {
        var result = all
        let list = leads(for: repo, in: all).filter {
            $0.caseInsensitiveCompare(login) != .orderedSame
        }
        result[key(for: repo)] = list.isEmpty ? nil : list
        return result
    }
}
