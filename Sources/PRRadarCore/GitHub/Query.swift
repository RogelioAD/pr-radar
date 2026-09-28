import Foundation

public enum Query {

    /// Discovers the viewer's login and every team they belong to.
    /// Note: `teams(...)` takes no `role:` argument here — `ALL` is not a valid
    /// `TeamRole` and the server rejects the query.
    public static let viewerAndTeams = """
    query {
      viewer {
        login
        organizations(first: 20) {
          nodes {
            login
            teams(first: 50, userLogins: ["@me"]) { nodes { slug } }
          }
        }
      }
    }
    """

    /// The viewer's login has to be substituted in, since `userLogins` needs a
    /// literal and does not understand `@me`.
    public static func viewerAndTeams(login: String) -> String {
        viewerAndTeams.replacingOccurrences(of: "@me", with: login)
    }

    /// The newest published release of PR Radar itself, for the update check.
    /// `latestRelease` is null when a repo has no releases, which reads as
    /// "nothing newer" rather than as a failure.
    public static func latestRelease(repo: String) -> String? {
        let parts = repo.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return """
        query {
          repository(owner: "\(parts[0])", name: "\(parts[1])") {
            latestRelease { tagName name url publishedAt }
          }
        }
        """
    }

    /// Users who can be mentioned in a repo, narrowed server-side by `text`.
    /// Backs the lead picker; it is a suggestion list, not a gate.
    public static func mentionableUsers(repo: String, matching text: String,
                                        first: Int = 30) -> String? {
        let parts = repo.split(separator: "/")
        guard parts.count == 2 else { return nil }
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        query {
          repository(owner: "\(parts[0])", name: "\(parts[1])") {
            mentionableUsers(first: \(first), query: "\(escaped)") {
              nodes { login name }
            }
          }
        }
        """
    }

    /// The viewer's own open pull requests, with everything a My PRs row needs.
    ///
    /// Sent as its own request rather than another alias on the reviews
    /// document: that one carries dynamically-named team aliases and so decodes
    /// as a homogeneous dictionary, which a differently-shaped alias would
    /// break.
    public static func myPullRequests(first: Int = 30) -> String {
        """
        query {
          mine: search(query: "is:open is:pr author:@me", type: ISSUE, first: \(first)) {
            issueCount
            nodes {
              ... on PullRequest {
                number
                title
                url
                isDraft
                createdAt
                updatedAt
                headRefName
                baseRefName
                reviewDecision
                mergeStateStatus
                mergeable
                additions
                deletions
                changedFiles
                repository { nameWithOwner }
                latestReviews(first: 30) {
                  nodes { author { login } state submittedAt }
                }
                reviewRequests(first: 30) {
                  nodes {
                    requestedReviewer {
                      __typename
                      ... on User { login }
                      ... on Team { slug }
                    }
                  }
                }
                reviewThreads(first: 100) {
                  totalCount
                  nodes {
                    id isResolved isOutdated path line
                    # Three, not all of them. This query runs on the sixty
                    # second poll for every pull request of yours at once, and
                    # a thread's worth of prose per row per minute is a real
                    # cost for something most rows never open. Three is the
                    # shape of a conversation — what was asked, and whether it
                    # was answered — and `totalCount` says how much is left.
                    comments(first: 3) {
                      totalCount
                      nodes { author { login } body }
                    }
                    # Aliased and asked for once. `diffHunk` is a property of
                    # the comment in the schema but a property of the *thread*
                    # in fact — every comment on a thread carries the same one —
                    # so fetching it with the bodies above would pull three
                    # copies of the same hunk per thread, per pull request,
                    # every sixty seconds.
                    hunk: comments(first: 1) {
                      nodes { diffHunk }
                    }
                  }
                }
                commits(last: 1) {
                  nodes {
                    commit {
                      oid
                      statusCheckRollup {
                        state
                        contexts(first: 100) {
                          totalCount
                          nodes {
                            __typename
                            ... on CheckRun { name conclusion status }
                            ... on StatusContext { context state }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """
    }

    /// How many pull requests the viewer has ever merged.
    ///
    /// `issueCount` is the *total* a search matched, not the number of nodes
    /// it returned — so one page of one is enough to learn a lifetime figure,
    /// and the trophy ladder is true on the day PR Radar is installed instead
    /// of starting everyone at zero.
    ///
    /// One alias, not several. The review ladder that would have wanted
    /// `reviewed-by:@me` is not in the roster, and a query that fetches a
    /// number nothing reads is a request per refresh spent on nothing.
    public static let mergedCount = """
    query {
      merged: search(query: "is:pr is:merged author:@me", type: ISSUE, first: 1) {
        issueCount
      }
    }
    """

    /// One aliased `compare` per pull request, to learn how far behind each head
    /// branch is. Aliases are `c0`, `c1`, … matching the input order.
    public static func compares(
        _ targets: [(repo: String, base: String, head: String)]
    ) -> String? {
        guard !targets.isEmpty else { return nil }
        var body = ""
        for (index, target) in targets.enumerated() {
            let parts = target.repo.split(separator: "/")
            guard parts.count == 2 else { continue }
            body += """

              c\(index): repository(owner: "\(parts[0])", name: "\(parts[1])") {
                ref(qualifiedName: "refs/heads/\(target.base)") {
                  compare(headRef: "\(target.head)") { aheadBy behindBy status }
                }
              }
            """
        }
        guard !body.isEmpty else { return nil }
        return "query {\(body)\n}"
    }

    /// The pull requests a decision is still owed on, fetched by node id.
    ///
    /// Its own request rather than another alias on the reviews document, for
    /// the reason `fetchMergedCount` gives: that document decodes as a
    /// homogeneous dictionary of `SearchResult` and a differently-shaped alias
    /// breaks it. A root `nodes` field is the one shape that does not — it
    /// returns `{"nodes": [...]}`, which is exactly `SearchResult`.
    ///
    /// Needed at all because these PRs are unreachable by search: submitting a
    /// review fulfils the request, so `review-requested:@me` stops matching
    /// them. Asking by id is the only way left to find out whether the PR is
    /// still open and so whether its row should still be standing.
    public static func pinnedPullRequests(ids: [String], first: Int = 30) -> String? {
        guard !ids.isEmpty else { return nil }
        let quoted = ids.prefix(first).map { "\"\($0)\"" }.joined(separator: ", ")
        return """
        \(prCoreFragment)
        query {
          nodes(ids: [\(quoted)]) {
            ... on PullRequest { ...PRCore }
          }
        }
        """
    }

    /// One document, one round trip: a shared fragment plus one aliased `search`
    /// per scope (direct request, then one per team).
    ///
    /// The three separate `timelineItems` aliases matter — a single combined
    /// connection lets bot review noise crowd out the review-request events we
    /// actually need (one real PR had 17 `github-actions` reviews).
    public static func pullRequests(teams: [TeamRef], first: Int = 30) -> String {
        var searches = """
          direct: search(query: "is:open is:pr review-requested:@me", type: ISSUE, first: \(first)) {
            nodes { ...PRCore }
          }
        """
        for (index, team) in teams.enumerated() {
            searches += """

              t\(index): search(query: "is:open is:pr team-review-requested:\(team.qualified)", type: ISSUE, first: \(first)) {
                nodes { ...PRCore }
              }
            """
        }

        return """
        \(prCoreFragment)
        query {
        \(searches)
        }
        """
    }

    /// The shape both review documents read a pull request in.
    private static let prCoreFragment = """
        fragment PRCore on PullRequest {
          id
          number
          title
          url
          isDraft
          state
          baseRefName
          author { login avatarUrl }
          repository { nameWithOwner }
          requests: timelineItems(last: 100, itemTypes: [REVIEW_REQUESTED_EVENT]) {
            nodes {
              ... on ReviewRequestedEvent {
                createdAt
                requestedReviewer {
                  __typename
                  ... on User { login }
                  ... on Team { slug }
                }
              }
            }
          }
          myReviews: timelineItems(last: 100, itemTypes: [PULL_REQUEST_REVIEW]) {
            nodes { ... on PullRequestReview { id createdAt state author { login } } }
          }
          myComments: timelineItems(last: 100, itemTypes: [ISSUE_COMMENT]) {
            nodes { ... on IssueComment { id createdAt author { login } } }
          }
        }
        """
}
