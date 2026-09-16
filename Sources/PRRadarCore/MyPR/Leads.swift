import Foundation

/// The reviewers whose approval actually unblocks a PR.
///
/// Held as logins because that is what the API returns, with display names for
/// the UI. Overridable through `Prefs` so the set does not need a rebuild when
/// the team changes.
public enum Leads {
    public static let defaultLogins: [String] = [
        "ec-boston",
        "ulises-codes",
        "mattiatelevation",
        "ec-danjocha",
    ]

    /// Short names for chips — the full GitHub name is too long for a row.
    public static let displayNames: [String: String] = [
        "ec-boston": "Boston",
        "ulises-codes": "Ulises",
        "mattiatelevation": "Matti",
        "ec-danjocha": "Daniel",
    ]

    public static func shortName(for login: String) -> String {
        displayNames[login] ?? login
    }
}
