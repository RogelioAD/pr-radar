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
                # The node id, which every mutation on your own PR needs as its
                # subject. The reviews query has always asked for it; this one
                # had nothing to mutate until the row grew buttons.
                id
                number
                title
                url
                isDraft
                createdAt
                updatedAt
                headRefName
                baseRefName
                # Whose repository the head branch lives in. A fork's is not
                # yours, and resolve has to refuse there rather than discover
                # it cannot push a quarter of an hour in.
                headRepositoryOwner { login }
                reviewDecision
                mergeStateStatus
                mergeable
                additions
                deletions
                changedFiles
                repository { nameWithOwner }
                latestReviews(first: 30) {
                  nodes {
                    # `id` through an inline fragment, because `author` is an
                    # Actor and only a User has one here. A bot comes back
                    # without it, which is right: there is nobody to ask.
                    author { login ... on User { id } }
                    state
                    submittedAt
                  }
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
                # When each of them was asked. `ReviewRequest` carries no
                # timestamp of its own — the live set says who is outstanding
                # and never since when — so the timeline is the only place the
                # other half of the clock is recorded.
                #
                # Its own aliased connection rather than more fields above,
                # and `last` rather than `first`, because what is wanted is the
                # most recent time each person was asked.
                requests: timelineItems(last: 50, itemTypes: [REVIEW_REQUESTED_EVENT]) {
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
                      # `id` and `createdAt` are for the notification rather
                      # than the row: a comment has to be the same comment next
                      # poll or it is announced once a minute for ever, and the
                      # node id is the only thing about it that is stable.
                      nodes { id createdAt author { login } body }
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
                            # `startedAt` and the workflow name are what let a
                            # superseded run be told from a live one. A cancelled
                            # run and the re-run that replaced it both come back
                            # here, and without these two the tally counts both.
                            ... on CheckRun {
                              name conclusion status startedAt
                              checkSuite { workflowRun { workflow { name } } }
                            }
                            ... on StatusContext { context state createdAt }
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

    /// Which of each pull request's checks are *required*, one alias per PR.
    ///
    /// Aliased `r<index>` against the **full** item array, exactly as
    /// `compares` aliases `c<index>`, and emitted only for the items that have
    /// a failing check. So the index always names the same item whether or not
    /// it was asked about, and a missing alias reads as *not asked* — which is
    /// the same thing as *not known*, and must not be read as *not required*.
    ///
    /// Only the failing ones, because most pull requests are green and a query
    /// that re-fetches a hundred context nodes per row per minute to learn
    /// nothing is the kind of cost the conflict counter already refuses to
    /// pay. The common path stays free and this phase is usually absent.
    ///
    /// It re-fetches the contexts the main query already tallied rather than
    /// replacing it. The main tally has to survive this phase failing, for the
    /// reason `behindBy` is optional — and a row that said nothing about its
    /// checks because a second request timed out would be worse than one that
    /// says what it has always said.
    public static func requiredChecks(
        _ targets: [(index: Int, repo: String, number: Int)]
    ) -> String? {
        var body = ""
        for target in targets {
            let parts = target.repo.split(separator: "/")
            guard parts.count == 2 else { continue }
            body += """

              r\(target.index): repository(owner: "\(parts[0])", name: "\(parts[1])") {
                pullRequest(number: \(target.number)) {
                  commits(last: 1) {
                    nodes {
                      commit {
                        statusCheckRollup {
                          contexts(first: 100) {
                            totalCount
                            nodes {
                              __typename
                              # The same fields the main tally reads, because
                              # the same superseded-run rule has to run over
                              # them — a cancelled run and the re-run that
                              # replaced it both come back here too.
                              ... on CheckRun {
                                name conclusion status startedAt
                                isRequired(pullRequestNumber: \(target.number))
                                checkSuite { workflowRun { workflow { name } } }
                              }
                              ... on StatusContext {
                                context state createdAt
                                isRequired(pullRequestNumber: \(target.number))
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
          # What the review will cost to do. The three numbers the My PRs side
          # has always carried and this side never did, so a forty-line row and
          # a fourteen-hundred-line one were the same row.
          additions
          deletions
          changedFiles
          # The description, for the line of it that decides whether to start
          # now — "don't review yet", "part 2 of 3", "only the last commit is
          # new".
          #
          # The raw markdown, not `bodyText`. `bodyText` was the obvious choice
          # — smaller on the wire, and the markdown is furniture at one line —
          # and it is wrong for exactly that reason: it strips the `##` off a
          # template heading, so the first line of a real pull request came
          # back as the bare word `What` and the row printed it.
          #
          # It is the one genuinely heavy field in this fragment. There is no
          # way to ask for a prefix, so a templated repository sends a few
          # kilobytes a row — only the first useful line is kept, and the rest
          # is dropped the moment it is parsed.
          body
          # The rollup's verdict and nothing under it. Triage asks "is this
          # even reviewable yet", which is one word; the per-check breakdown is
          # the My PRs tab's job and costs a hundred nodes a pull request —
          # here that would be a hundred times thirty times one alias per team.
          #
          # Aliased because a second `commits` connection sits beside it below,
          # and the two want different page sizes.
          head: commits(last: 1) {
            nodes { commit { oid statusCheckRollup { state } } }
          }
          # The tail of the branch, for counting what has been pushed since you
          # last reviewed. Dates only, and twenty of them: the count exists to
          # tell twelve lines from a rewrite, and a row that says `20+` is a
          # better answer than one that spends a hundred nodes being exact.
          recent: commits(last: 20) {
            totalCount
            nodes { commit { committedDate } }
          }
          # Who has already signed off, so a row can say you may be the sixth
          # opinion on something two leads have approved.
          latestReviews(first: 20) { nodes { author { login } state } }
          # Who else is still being waited on. `reviewRequests` is the live
          # set — GitHub removes a reviewer from it the moment they submit —
          # which is exactly the question "am I the only one left".
          reviewRequests(first: 20) {
            totalCount
            nodes {
              requestedReviewer {
                __typename
                ... on User { login }
                ... on Team { slug }
              }
            }
          }
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
            nodes {
              ... on PullRequestReview {
                id createdAt state author { login }
                # The commit the review was made against — the anchor for the
                # diff of what has changed since. Null on a review whose commit
                # was force-pushed out of the branch, which is a case the row
                # has to survive rather than link into a 404.
                commit { oid }
              }
            }
          }
          myComments: timelineItems(last: 100, itemTypes: [ISSUE_COMMENT]) {
            nodes { ... on IssueComment { id createdAt author { login } } }
          }
        }
        """
}
