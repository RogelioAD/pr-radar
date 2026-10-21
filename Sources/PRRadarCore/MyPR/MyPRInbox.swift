import Foundation

/// Turns the raw my-PRs payload into domain models.
///
/// The one rule worth stating: approvals are counted from **live** review
/// state only. `latestReviews` happily reports a `DISMISSED` approval, and on
/// a real PR here two leads' approvals were dismissed by later commits while
/// `latestOpinionatedReviews` was empty. Counting a dismissed approval as an
/// approval would make the lead chip claim a PR is unblocked when GitHub
/// considers it blocked.
public struct MyPRInbox {
    /// Leads per repo, keyed by `Leads.key(host:repo:)`.
    public let leads: [String: [String]]

    /// The host every repo in this payload belongs to.
    ///
    /// One per inbox rather than one per row, because a payload comes from a
    /// single account and an account belongs to a single host. It is what
    /// separates `acme/app` on github.com from `acme/app` on an Enterprise
    /// host, which are two repositories and two sets of leads.
    public let host: String

    public init(leads: [String: [String]] = [:], host: String = Leads.defaultHost) {
        self.leads = leads
        self.host = host
    }

    public func build(from result: MyPRSearchResult) -> [MyPullRequest] {
        let items = result.nodes.compactMap(item(from:))
        return Self.linkStacks(items)
    }

    func item(from node: MyPRNode) -> MyPullRequest? {
        guard let repo = node.repository?.nameWithOwner,
              let number = node.number,
              let title = node.title,
              let urlString = node.url,
              let url = URL(string: urlString),
              let createdAt = node.createdAt,
              let head = node.headRefName,
              let base = node.baseRefName
        else { return nil }

        let repoLeads = Set(Leads.leads(for: repo, host: host, in: leads))

        let approvals = (node.latestReviews?.nodes ?? []).compactMap { review -> Approval? in
            guard let login = review.author?.login,
                  let raw = review.state,
                  let state = ReviewState(rawValue: raw)
            else { return nil }
            // Bot "COMMENTED" reviews are noise on this tab.
            if state == .commented { return nil }
            return Approval(login: login, state: state,
                            isLead: repoLeads.contains(login),
                            submittedAt: review.submittedAt)
        }

        let awaiting = (node.reviewRequests?.nodes ?? []).compactMap { request -> String? in
            guard let reviewer = request.requestedReviewer else { return nil }
            return reviewer.typename == "Team" ? reviewer.slug : reviewer.login
        }

        let threads = node.reviewThreads?.nodes ?? []
        let openThreads = threads.filter { $0.isResolved == false }
        let unresolved = openThreads.count
        // Only the ones GitHub gave an id to. Without one a thread cannot keep
        // its place across a refresh, and a row that reshuffles every sixty
        // seconds is worse than one that lists one thread fewer.
        let unresolvedThreads = openThreads.compactMap { thread -> UnresolvedThread? in
            guard let id = thread.id else { return nil }
            let comments = thread.comments?.nodes ?? []
            return UnresolvedThread(
                id: id,
                path: thread.path,
                line: thread.line,
                isOutdated: thread.isOutdated ?? false,
                comments: comments.map {
                    UnresolvedThread.Comment(
                        author: $0.author?.login ?? "someone",
                        body: UnresolvedThread.trimmed($0.body ?? ""),
                        id: $0.id,
                        createdAt: $0.createdAt)
                },
                moreComments: max(0, (thread.comments?.totalCount ?? 0) - comments.count),
                excerpt: thread.path.flatMap { path in
                    thread.hunk?.nodes.first?.diffHunk.flatMap {
                        DiffExcerpt.parse(diffHunk: $0, path: path, line: thread.line)
                    }
                })
        }

        var item = MyPullRequest(
            repo: repo,
            number: number,
            title: title,
            url: url,
            isDraft: node.isDraft ?? false,
            createdAt: createdAt,
            updatedAt: node.updatedAt ?? createdAt,
            headRefName: head,
            baseRefName: base,
            reviewDecision: node.reviewDecision
                .flatMap(ReviewDecision.init(rawValue:)) ?? .none,
            mergeBlocker: node.mergeStateStatus
                .flatMap(MergeBlocker.init(rawValue:)) ?? .unknown,
            approvals: approvals,
            hasLeadGate: !repoLeads.isEmpty,
            awaitingReviewers: awaiting,
            unresolvedThreadCount: unresolved,
            unresolvedThreads: unresolvedThreads,
            totalThreadCount: node.reviewThreads?.totalCount ?? threads.count,
            checks: Self.checks(from: node.commits?.nodes.first?.commit?.statusCheckRollup),
            additions: node.additions ?? 0,
            deletions: node.deletions ?? 0,
            changedFiles: node.changedFiles ?? 0
        )
        item.nodeID = node.id
        item.requestedAt = Self.requestedAt(in: node.requests)
        item.headOid = node.commits?.nodes.first?.commit?.oid
        item.headRepositoryOwner = node.headRepositoryOwner?.login
        return item
    }

    /// When each reviewer was last asked, from the review-request events.
    ///
    /// *Last*, not first: being re-requested restarts that person's clock,
    /// exactly as a re-request restarts yours on the Reviews tab. Keyed by
    /// login for a user and by slug for a team, which is how
    /// `awaitingReviewers` keys them too — the two have to agree or the
    /// lookup silently misses and the row quietly stops claiming a duration.
    static func requestedAt(in timeline: TimelineConn?) -> [String: Date] {
        var latest: [String: Date] = [:]
        for event in timeline?.nodes ?? [] {
            guard let createdAt = event.createdAt,
                  let reviewer = event.requestedReviewer
            else { continue }
            let key = reviewer.typename == "Team" ? reviewer.slug : reviewer.login
            guard let key else { continue }
            if let existing = latest[key], existing >= createdAt { continue }
            latest[key] = createdAt
        }
        return latest
    }

    /// The contexts GitHub is actually showing, one per check.
    ///
    /// The rollup returns *every* run against the head commit, not the current
    /// one per check. Push while a run is in flight and the first is cancelled
    /// and replaced seconds later — and both come back here, so a PR whose
    /// checks had all been re-run and passed was reported as a dozen failures,
    /// one per cancelled run, against a GitHub page showing none. Superseded
    /// runs are dropped the way GitHub drops them: latest wins, per check.
    ///
    /// Keyed on workflow *and* name rather than name alone, so two workflows
    /// that each define a `build` keep both — see `ContextNode.identity`.
    static func currentContexts(_ nodes: [ContextNode]) -> [ContextNode] {
        var latest: [String: ContextNode] = [:]
        for node in nodes {
            guard let previous = latest[node.identity] else {
                latest[node.identity] = node
                continue
            }
            // `>=` so that when two runs carry the same timestamp — or neither
            // carries one at all — the later arrival wins. GitHub returns a
            // commit's contexts oldest first, so that is still the current one.
            if node.occurredAt >= previous.occurredAt {
                latest[node.identity] = node
            }
        }
        // Back into the order they arrived, so `failingNames` reads the way the
        // checks list does rather than in dictionary order.
        var seen = Set<String>()
        return nodes.compactMap { node in
            guard !seen.contains(node.identity) else { return nil }
            seen.insert(node.identity)
            return latest[node.identity]
        }
    }

    /// Tallies a check rollup. CheckRun and StatusContext report their verdict
    /// in different fields, which `ContextNode.verdict` already normalises.
    static func checks(from rollup: RollupNode?) -> ChecksSummary {
        guard let rollup else { return .empty }
        var passing = 0, failing = 0, running = 0, skipped = 0
        var failingNames: [String] = []

        for context in currentContexts(rollup.contexts?.nodes ?? []) {
            if isFailure(context.verdict) {
                failing += 1
                failingNames.append(context.displayName)
                continue
            }
            switch context.verdict {
            case "SUCCESS":
                passing += 1
            case "IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "REQUESTED":
                running += 1
            case "SKIPPED", "NEUTRAL", "STALE":
                skipped += 1
            default:
                break
            }
        }

        return ChecksSummary(passing: passing, failing: failing, running: running,
                             skipped: skipped, failingNames: failingNames,
                             rollupState: rollup.state)
    }

    /// Links PRs whose base is another of these PRs' head branches, in both
    /// directions: the child learns what it sits on, the parent learns which
    /// PRs a rebase of it would strand.
    static func linkStacks(_ items: [MyPullRequest]) -> [MyPullRequest] {
        var result = items
        // Head branch -> PR number, scoped by repo so two repos cannot cross-link.
        var byHead: [String: Int] = [:]
        for item in items {
            byHead["\(item.repo)|\(item.headRefName)"] = item.number
        }

        for index in result.indices {
            let key = "\(result[index].repo)|\(result[index].baseRefName)"
            if let parent = byHead[key], parent != result[index].number {
                result[index].stackedOn = parent
            }
        }

        let children = result.filter { $0.stackedOn != nil }
        for index in result.indices {
            let number = result[index].number
            result[index].blocksRestackOf = children
                .filter { $0.stackedOn == number && $0.repo == result[index].repo }
                .map(\.number)
                .sorted()
        }
        return result
    }

    /// Which pull requests are worth asking the required-checks phase about.
    ///
    /// Only the ones with a failing check. Most pull requests are green, and
    /// re-fetching a hundred context nodes per row per minute to learn that
    /// nothing is failing is the cost the conflict counter already refuses to
    /// pay. Indexed against the full array so an alias always names the same
    /// item whether or not it was asked about.
    public static func requiredCheckTargets(
        _ items: [MyPullRequest]
    ) -> [(index: Int, repo: String, number: Int)] {
        items.enumerated().compactMap { index, item in
            guard item.checks.failing > 0 else { return nil }
            return (index: index, repo: item.repo, number: item.number)
        }
    }

    /// Applies second-phase required-checks results, keyed by the `r<index>`
    /// aliases `Query.requiredChecks` produced.
    ///
    /// A missing alias leaves `requiredFailingNames` nil — *not asked*, which
    /// is the same thing as *not known* and must never be read as *nothing is
    /// required*. An alias that came back but listed no required failures is
    /// the opposite: a verified empty, which is what lets a row say the red
    /// checks on it are not what is holding it up.
    ///
    /// The superseded-run rule runs over these contexts too. A cancelled run
    /// and the re-run that replaced it both come back from this query as well,
    /// and counting the cancelled one as a required failure would re-create
    /// the bug the main tally already fixed.
    public static func applyRequiredChecks(
        _ results: [String: RequiredChecksResult],
        to items: [MyPullRequest]
    ) -> [MyPullRequest] {
        var result = items
        for index in result.indices {
            guard let contexts = results["r\(index)"]?.pullRequest?
                    .commits?.nodes.first?.commit?.statusCheckRollup?.contexts?.nodes
            else { continue }
            let required = currentContexts(contexts)
                .filter { $0.isRequired == true && isFailure($0.verdict) }
                .map(\.displayName)
            result[index].checks = result[index].checks.knowingRequired(required)
        }
        return result
    }

    /// The verdicts that count as a failure. One list, read by the tally and
    /// by the required-checks phase, so the two cannot disagree about what
    /// failing means.
    static func isFailure(_ verdict: String?) -> Bool {
        switch verdict {
        case "FAILURE", "ERROR", "TIMED_OUT", "CANCELLED",
             "ACTION_REQUIRED", "STARTUP_FAILURE":
            return true
        default:
            return false
        }
    }

    /// Applies second-phase compare results, keyed by the `c<index>` aliases
    /// that `Query.compares` produced. A missing alias leaves `behindBy` nil —
    /// *unknown*, which the UI must not render as "up to date".
    public static func applyCompares(_ compares: [String: CompareResult],
                                     to items: [MyPullRequest]) -> [MyPullRequest] {
        var result = items
        for (index, _) in result.enumerated() {
            if let comparison = compares["c\(index)"]?.ref?.compare {
                result[index].behindBy = comparison.behindBy
            }
        }
        return result
    }
}
