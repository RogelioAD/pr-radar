import Foundation

/// Narrowing a list to one repository, and describing which repositories are
/// available to narrow to.
///
/// Pure and generic over both tabs' row types, because the interesting cases —
/// several repositories, a repo present in one tab but not the other, two
/// repos sharing a short name under different owners — cannot be reproduced
/// against an account whose work all lives in a single repo.
public enum RepoScope {

    /// Filters to `repo`, or returns everything when it is nil.
    public static func apply<T>(_ repo: String?,
                                to items: [T],
                                repoOf: (T) -> String) -> [T] {
        guard let repo else { return items }
        return items.filter { repoOf($0) == repo }
    }

    /// Every distinct repository across both lists, sorted case-insensitively.
    public static func names(reviews: [String], mine: [String]) -> [String] {
        Array(Set(reviews + mine)).sorted { $0.lowercased() < $1.lowercased() }
    }

    /// The trailing path segment — `owner/name` becomes `name`.
    ///
    /// Only for display. Filtering always uses the full `owner/name`, since two
    /// owners can have repositories with the same short name.
    public static func shortName(_ repo: String) -> String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }
}
