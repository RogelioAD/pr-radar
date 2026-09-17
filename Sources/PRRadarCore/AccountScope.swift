import Foundation

/// Narrowing both lists to one account.
///
/// Deliberately the same shape as `RepoScope` rather than a new mechanism: an
/// account is a scope in exactly the sense a repository is — "I am working as
/// this identity today" — and scoping already means one thing in this app, that
/// the badge and the tab counts move together. A second, differently-behaved
/// filter would be the thing that lets them disagree.
public enum AccountScope {

    /// Filters to `account`, or returns everything when it is nil.
    public static func apply<T>(_ account: String?,
                                to items: [T],
                                accountOf: (T) -> String) -> [T] {
        guard let account else { return items }
        return items.filter { accountOf($0) == account }
    }

    /// Whether what is on screen is missing an account's contribution.
    ///
    /// Scoped to one account, only that account's failure shortens the list —
    /// another identity being unreachable changes nothing you are looking at,
    /// and warning about it would train the warning to be ignored. Unscoped,
    /// any failure does, because the list claims to be everything.
    public static func isPartial(failed: Set<String>, scope: String?) -> Bool {
        guard !failed.isEmpty else { return false }
        guard let scope else { return true }
        return failed.contains(scope)
    }
}
