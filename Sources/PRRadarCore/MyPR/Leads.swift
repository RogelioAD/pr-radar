import Foundation

/// The reviewers whose approval actually unblocks a PR.
///
/// Held as logins because that is what the API returns, with display names for
/// the UI. Overridable through `Prefs` so the set does not need a rebuild when
/// the team changes.
public enum Leads {
    /// Placeholders on purpose. Set your team's real leads without rebuilding:
    ///
    ///     defaults write <bundle-id> leads.logins -array alice bob carol
    ///
    /// An empty list is fine too — the lead chip then always reads
    /// "lead needed" and nothing else depends on it.
    public static let defaultLogins: [String] = []

    /// Short names for chips — a full GitHub login is often too long for a row.
    /// Anything not listed falls back to the login itself.
    public static let displayNames: [String: String] = [:]

    public static func shortName(for login: String) -> String {
        displayNames[login] ?? login
    }
}
