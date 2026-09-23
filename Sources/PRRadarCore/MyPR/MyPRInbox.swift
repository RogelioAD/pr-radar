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
                            isLead: repoLeads.contains(login))
        }

        let awaiting = (node.reviewRequests?.nodes ?? []).compactMap { request -> String? in
            guard let reviewer = request.requestedReviewer else { return nil }
            return reviewer.typename == "Team" ? reviewer.slug : reviewer.login
        }

        let threads = node.reviewThreads?.nodes ?? []
        let unresolved = threads.filter { $0.isResolved == false }.count

        return MyPullRequest(
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
            totalThreadCount: node.reviewThreads?.totalCount ?? threads.count,
            checks: Self.checks(from: node.commits?.nodes.first?.commit?.statusCheckRollup),
            additions: node.additions ?? 0,
            deletions: node.deletions ?? 0,
            changedFiles: node.changedFiles ?? 0
        )
    }

    /// Tallies a check rollup. CheckRun and StatusContext report their verdict
    /// in different fields, which `ContextNode.verdict` already normalises.
    ///
    /// `CANCELLED` is *not* a failure. A cancelled run did not decide anything
    /// — most of them are runs a concurrency group killed a second after they
    /// started, and calling that a failure puts a red count on a PR whose live
    /// run is green.
    static func checks(from rollup: RollupNode?) -> ChecksSummary {
        guard let rollup else { return .empty }
        var passing = 0, failing = 0, running = 0, skipped = 0
        var failingNames: [String] = []

        for context in live(rollup.contexts?.nodes ?? []) {
            switch context.verdict {
            case "SUCCESS":
                passing += 1
            case "FAILURE", "ERROR", "TIMED_OUT",
                 "ACTION_REQUIRED", "STARTUP_FAILURE":
                failing += 1
                failingNames.append(context.displayName)
            case "IN_PROGRESS", "QUEUED", "PENDING", "WAITING", "REQUESTED":
                running += 1
            case "SKIPPED", "NEUTRAL", "STALE", "CANCELLED":
                skipped += 1
            default:
                break
            }
        }

        return ChecksSummary(passing: passing, failing: failing, running: running,
                             skipped: skipped, failingNames: failingNames,
                             rollupState: rollup.state)
    }

    /// Drops checks belonging to a superseded run of a workflow.
    ///
    /// The rollup lists every check run on the head commit, including ones from
    /// runs that a re-run or a concurrency group has already replaced. Both runs
    /// are on the same commit, so nothing in a single check says which is
    /// current — only the run it came from does. Keeping the newest run per
    /// workflow is what makes a count match what the workflow is actually
    /// doing now.
    ///
    /// Filtering by run rather than by check name is deliberate: a matrix job
    /// legitimately repeats a name within one run, and those are all live.
    /// Anything with no run to compare — a StatusContext, or a check posted by
    /// an app that does not run on Actions — is always kept.
    static func live(_ contexts: [ContextNode]) -> [ContextNode] {
        var newest: [String: (Date, Int)] = [:]
        for context in contexts {
            guard let workflow = context.workflow, let order = context.runOrder
            else { continue }
            if let seen = newest[workflow], seen >= order { continue }
            newest[workflow] = order
        }

        return contexts.filter { context in
            guard let workflow = context.workflow, let order = context.runOrder
            else { return true }
            return newest[workflow].map { $0 == order } ?? true
        }
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
