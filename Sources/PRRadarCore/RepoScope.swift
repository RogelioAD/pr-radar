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
    ///
    /// Kept beside the set form below, rather than replaced by it, because a
    /// single repository is still what most of the app asks about: the count
    /// beside one name in the menu, and the test for whether a stack exists
    /// somewhere, are both questions about one repo and not about the scope.
    public static func apply<T>(_ repo: String?,
                                to items: [T],
                                repoOf: (T) -> String) -> [T] {
        guard let repo else { return items }
        return items.filter { repoOf($0) == repo }
    }

    /// Filters to any of `repos`, or returns everything when it is empty.
    ///
    /// Empty means *all*, which is the same thing nil meant before and keeps
    /// the scope's two states to two: narrowed to something, or not narrowed.
    /// A scope that could be narrowed to nothing would be a drawer that is
    /// empty with no filter visibly set.
    public static func apply<T>(_ repos: Set<String>,
                                to items: [T],
                                repoOf: (T) -> String) -> [T] {
        guard !repos.isEmpty else { return items }
        return items.filter { repos.contains(repoOf($0)) }
    }

    /// What a pill says for a scope of this size.
    ///
    /// One repository is named; several are counted. Naming two would not fit
    /// — the bar has 68 points for this label and `elevation-church-mobile-rust`
    /// alone already fills it — and naming the first with "+2" after it reads
    /// as though the first one were the important one.
    public static func label(_ repos: Set<String>, all: String = "All repos") -> String {
        switch repos.count {
        case 0: return all
        case 1: return shortName(repos.first ?? "")
        default: return "\(repos.count) repos"
        }
    }

    /// Drops names that are no longer in either list.
    ///
    /// Per name rather than all-or-nothing: with three repositories picked and
    /// one of them finished, the other two are still exactly what you asked
    /// for, and clearing the scope because part of it went stale would throw
    /// away a choice that is still good.
    public static func validated(_ repos: Set<String>,
                                 against available: [String]) -> Set<String> {
        repos.intersection(available)
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
