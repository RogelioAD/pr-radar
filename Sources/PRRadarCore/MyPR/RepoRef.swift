import Foundation

/// A repository and the host it lives on — together, what a lead list is
/// keyed by.
///
/// A pair rather than a bare `owner/repo` string because the app can be logged
/// in to github.com and an Enterprise host at once, and the same `owner/repo`
/// on each is two different repositories with two different sets of people.
/// Everywhere the *filter* narrows by repository a bare name is still right —
/// "I am working in this repo today" is not a question about hosts — so this
/// exists alongside that rather than replacing it.
public struct RepoRef: Hashable, Identifiable, Sendable {
    /// `owner/name`, as GitHub spells it.
    public let repo: String
    public let host: String

    public init(repo: String, host: String = Leads.defaultHost) {
        self.repo = repo
        self.host = host
    }

    public var id: String { Leads.key(host: host, repo: repo) }

    /// The host is shown only when it is not the default one. On the machines
    /// that have never seen an Enterprise host — which is most of them — a
    /// parenthesised "github.com" after every repository would be noise
    /// repeated once per row.
    public var label: String {
        host == Leads.defaultHost ? repo : "\(repo) (\(host))"
    }

    /// Sorted by what the reader sees, case-insensitively.
    public static func sorted(_ refs: [RepoRef]) -> [RepoRef] {
        refs.sorted { $0.label.lowercased() < $1.label.lowercased() }
    }
}
