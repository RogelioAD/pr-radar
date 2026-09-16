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
                  nodes { isResolved isOutdated }
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
        fragment PRCore on PullRequest {
          number
          title
          url
          isDraft
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
            nodes { ... on PullRequestReview { createdAt state author { login } } }
          }
          myComments: timelineItems(last: 100, itemTypes: [ISSUE_COMMENT]) {
            nodes { ... on IssueComment { createdAt author { login } } }
          }
        }
        query {
        \(searches)
        }
        """
    }
}
