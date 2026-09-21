import Foundation

/// A review someone has left, reduced to what a row needs.
public struct Approval: Identifiable, Equatable, Sendable {
    public let login: String
    public let state: ReviewState
    public let isLead: Bool

    public var id: String { login }
    public var shortName: String { Leads.shortName(for: login) }

    public init(login: String, state: ReviewState, isLead: Bool) {
        self.login = login
        self.state = state
        self.isLead = isLead
    }
}

public enum ReviewState: String, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"
    case dismissed = "DISMISSED"
    case pending = "PENDING"

    /// Only these two are opinions GitHub counts toward a review decision.
    /// `DISMISSED` explicitly does not — a dismissed approval is not an
    /// approval, and treating it as one is the way this feature would lie.
    public var isLiveOpinion: Bool {
        self == .approved || self == .changesRequested
    }
}

public enum ReviewDecision: String, Sendable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
    case none = "NONE"

    public var label: String {
        switch self {
        case .approved: return "approved"
        case .changesRequested: return "changes requested"
        case .reviewRequired: return "review required"
        case .none: return "no review required"
        }
    }

    public var health: Health {
        switch self {
        case .approved: return .good
        case .changesRequested: return .bad
        case .reviewRequired: return .attention
        case .none: return .neutral
        }
    }
}

/// Why a PR cannot merge, from `mergeStateStatus`.
public enum MergeBlocker: String, Sendable {
    case clean = "CLEAN"
    case blocked = "BLOCKED"
    case behind = "BEHIND"
    case dirty = "DIRTY"
    case draft = "DRAFT"
    case unstable = "UNSTABLE"
    case hasHooks = "HAS_HOOKS"
    case unknown = "UNKNOWN"

    public var label: String {
        switch self {
        case .clean: return "ready"
        case .blocked: return "needs review"
        case .behind: return "behind base"
        case .dirty: return "conflicts"
        case .draft: return "draft"
        case .unstable: return "checks failing"
        case .hasHooks: return "ready"
        case .unknown: return "unknown"
        }
    }

    public var health: Health {
        switch self {
        case .clean, .hasHooks: return .good
        case .blocked, .behind: return .attention
        case .dirty, .unstable: return .bad
        case .draft, .unknown: return .neutral
        }
    }

    /// Whether a rebase would plausibly help.
    public var wantsRebase: Bool { self == .behind || self == .dirty }
}

/// Tallied CI state for the PR's head commit.
public struct ChecksSummary: Equatable, Sendable {
    public let passing: Int
    public let failing: Int
    public let running: Int
    public let skipped: Int
    public let failingNames: [String]
    /// nil when the head commit has no checks at all.
    public let rollupState: String?

    public var total: Int { passing + failing + running + skipped }
    public var hasAny: Bool { total > 0 }

    public var health: Health {
        if failing > 0 { return .bad }
        if running > 0 { return .running }
        if passing > 0 { return .good }
        return .neutral
    }

    public init(passing: Int, failing: Int, running: Int, skipped: Int,
                failingNames: [String], rollupState: String?) {
        self.passing = passing
        self.failing = failing
        self.running = running
        self.skipped = skipped
        self.failingNames = failingNames
        self.rollupState = rollupState
    }

    public static let empty = ChecksSummary(passing: 0, failing: 0, running: 0,
                                           skipped: 0, failingNames: [],
                                           rollupState: nil)
}

/// One of the viewer's own open pull requests.
public struct MyPullRequest: Identifiable, Equatable, Sendable {
    public let repo: String
    public let number: Int
    public let title: String
    public let url: URL
    public let isDraft: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let headRefName: String
    public let baseRefName: String
    public let reviewDecision: ReviewDecision
    public var mergeBlocker: MergeBlocker
    public let approvals: [Approval]
    /// Whether this repo has any leads configured. Without one, no lead
    /// state is shown or counted.
    public let hasLeadGate: Bool
    public let awaitingReviewers: [String]
    public let unresolvedThreadCount: Int
    public let totalThreadCount: Int
    public let checks: ChecksSummary
    public let additions: Int
    public let deletions: Int
    public let changedFiles: Int

    /// Filled by the second-phase compare query. nil means *unknown*, which
    /// must not be rendered as "up to date" — that phase can fail on its own.
    public var behindBy: Int?
    /// My other open PR this one is stacked on, if any.
    public var stackedOn: Int?
    /// My other open PRs stacked on this one; rebasing this strands them.
    public var blocksRestackOf: [Int] = []

    public var id: String { "\(repo)#\(number)" }
    public var repoShortName: String {
        repo.split(separator: "/").last.map(String.init) ?? repo
    }

    // MARK: - Derived state

    /// Live approvals only — dismissed ones are excluded by `isLiveOpinion`.
    public var liveApprovals: [Approval] {
        approvals.filter { $0.state == .approved }
    }

    public var dismissedApprovals: [Approval] {
        approvals.filter { $0.state == .dismissed }
    }

    public var changesRequestedBy: [Approval] {
        approvals.filter { $0.state == .changesRequested }
    }

    /// The lead whose live approval unblocks this, if one has approved.
    public var approvingLead: Approval? {
        liveApprovals.first { $0.isLead }
    }

    public var needsLead: Bool { hasLeadGate && approvingLead == nil }

    public var isStacked: Bool { stackedOn != nil }

    /// What, if anything, the branch needs doing to it before it can merge.
    ///
    /// Read straight off what GitHub already reports — `mergeStateStatus` and
    /// the compare count — so it needs no local checkout.
    public enum BranchState: Equatable, Sendable {
        case upToDate
        case needsRebase(behindBy: Int?)
        case conflicts
        /// The compare request didn't answer, so we genuinely don't know.
        case unknown
    }

    public var branchState: BranchState {
        if mergeBlocker == .dirty { return .conflicts }
        if let behind = behindBy {
            return behind > 0 ? .needsRebase(behindBy: behind) : .upToDate
        }
        // No count: fall back to GitHub's own verdict.
        if mergeBlocker == .behind { return .needsRebase(behindBy: nil) }
        return .unknown
    }

    /// Worst signal on the row, used for the accent and for the badge dot.
    public var health: Health {
        Health.worst([
            checks.health,
            mergeBlocker.health,
            reviewDecision.health,
            hasLeadGate ? (needsLead ? .attention : .good) : .neutral,
            unresolvedThreadCount > 0 ? .attention : .neutral,
        ])
    }

    /// Whether this PR is mergeable — the signal the badge's dot carries.
    ///
    /// `CLEAN` is GitHub's own verdict that nothing stands in the way:
    /// approvals satisfied, checks green, branch current. `HAS_HOOKS` is the
    /// same state on a repo with pre-receive hooks.
    public var isReadyToMerge: Bool {
        !isDraft && (mergeBlocker == .clean || mergeBlocker == .hasHooks)
    }

    public init(repo: String, number: Int, title: String, url: URL, isDraft: Bool,
                createdAt: Date, updatedAt: Date, headRefName: String,
                baseRefName: String, reviewDecision: ReviewDecision,
                mergeBlocker: MergeBlocker, approvals: [Approval],
                hasLeadGate: Bool = false,
                awaitingReviewers: [String], unresolvedThreadCount: Int,
                totalThreadCount: Int, checks: ChecksSummary,
                additions: Int, deletions: Int, changedFiles: Int,
                behindBy: Int? = nil, stackedOn: Int? = nil,
                blocksRestackOf: [Int] = []) {
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.reviewDecision = reviewDecision
        self.mergeBlocker = mergeBlocker
        self.approvals = approvals
        self.hasLeadGate = hasLeadGate
        self.awaitingReviewers = awaitingReviewers
        self.unresolvedThreadCount = unresolvedThreadCount
        self.totalThreadCount = totalThreadCount
        self.checks = checks
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.behindBy = behindBy
        self.stackedOn = stackedOn
        self.blocksRestackOf = blocksRestackOf
    }
}
