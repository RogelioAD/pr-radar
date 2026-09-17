import Foundation

/// Combining several accounts' rows into the one list each tab shows.
public enum AccountMerge {

    /// Concatenates in account order, dropping a row already contributed by an
    /// earlier account.
    ///
    /// Two accounts can genuinely surface the same pull request: a review asked
    /// of a team that both identities belong to arrives once per account, with
    /// the same `owner/repo#number`. Left in, the duplicate would inflate the
    /// badge and — because rows are `Identifiable` by that same id — hand
    /// SwiftUI two rows claiming one identity.
    ///
    /// The first account to surface a row keeps it, which is why order matters
    /// upstream: the active account leads, so a shared row is attributed to the
    /// identity the app used to show on its own. The cost is that scoping to the
    /// *other* account hides a row that account can genuinely see. That is the
    /// honest trade — one row, one owner — and it is preferred to a count that
    /// double-reports the same review.
    public static func merge<T: Identifiable>(_ perAccount: [[T]]) -> [T] {
        var seen = Set<T.ID>()
        var result: [T] = []
        for rows in perAccount {
            for row in rows where !seen.contains(row.id) {
                seen.insert(row.id)
                result.append(row)
            }
        }
        return result
    }
}
