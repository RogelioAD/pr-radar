import Foundation

/// A review someone has left, reduced to what a row needs.
public struct Approval: Identifiable, Equatable, Sendable {
    public let login: String
    public let state: ReviewState
    public let isLead: Bool
    /// When it was submitted. Optional and defaulted, because no row has ever
    /// drawn it — it is here so a verdict can be announced once rather than on
    /// every poll, and a review with no timestamp is simply never announced.
    public var submittedAt: Date?

    public var id: String { login }
    public var shortName: String { Leads.shortName(for: login) }

    public init(login: String, state: ReviewState, isLead: Bool,
                submittedAt: Date? = nil) {
        self.login = login
        self.state = state
        self.isLead = isLead
        self.submittedAt = submittedAt
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

    /// Which of the failing checks the branch protection rules insist on.
    ///
    /// nil means **not known**, which is the state every row is in until the
    /// second phase answers, and the state it stays in if that phase fails.
    /// Deliberately not the same as an empty array: `[]` is the verified claim
    /// that nothing failing is blocking the merge, and a row that made that
    /// claim without checking would be the same lie as a failed branch compare
    /// rendered as "up to date".
    public let requiredFailingNames: [String]?

    public var total: Int { passing + failing + running + skipped }
    public var hasAny: Bool { total > 0 }

    /// Whether any failing check actually stands between this and a merge.
    /// nil while it is unknown, so a caller has to decide what to do about
    /// not knowing rather than being handed a `false`.
    public var hasBlockingFailure: Bool? {
        requiredFailingNames.map { !$0.isEmpty }
    }

    /// How severe the checks are.
    ///
    /// A failure that nothing requires is a real failure and a lesser one: the
    /// branch can still merge, and a red lint job nobody gates on should not
    /// rank beside a broken build. It drops to `attention` rather than
    /// disappearing, because red is still red and somebody put that check
    /// there. While required-ness is unknown, every failure is treated as the
    /// worst it could be — the honest reading of a question not yet asked.
    public var health: Health {
        if failing > 0 { return hasBlockingFailure == false ? .attention : .bad }
        if running > 0 { return .running }
        if passing > 0 { return .good }
        return .neutral
    }

    /// What the chip says after the count, or nil while nothing is known.
    public var blockingLabel: String? {
        guard let required = requiredFailingNames else { return nil }
        return required.isEmpty ? "none blocking" : "\(required.count) blocking"
    }

    public init(passing: Int, failing: Int, running: Int, skipped: Int,
                failingNames: [String], rollupState: String?,
                requiredFailingNames: [String]? = nil) {
        self.passing = passing
        self.failing = failing
        self.running = running
        self.skipped = skipped
        self.failingNames = failingNames
        self.rollupState = rollupState
        self.requiredFailingNames = requiredFailingNames
    }

    /// The same tally, with the second phase's answer folded in.
    public func knowingRequired(_ names: [String]) -> ChecksSummary {
        ChecksSummary(passing: passing, failing: failing, running: running,
                      skipped: skipped, failingNames: failingNames,
                      rollupState: rollupState, requiredFailingNames: names)
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
    /// The threads behind that count.
    ///
    /// Optional in effect — defaulted, like `account` beside it — so every
    /// existing construction site and test goes on compiling. An empty list
    /// where the count is not zero simply means the row can say how many there
    /// are but not what they say.
    public var unresolvedThreads: [UnresolvedThread] = []

    /// The commit the pull request's head branch is actually at.
    ///
    /// Fetched since the checks rollup existed — `commits(last: 1)` carries it
    /// — and thrown away until something needed it. Resolve needs it: it runs
    /// in the user's own checkout, and a checkout that is not at this commit is
    /// a different tree than the one the threads were written against.
    ///
    /// Optional and defaulted, like everything else added to this type after
    /// the fact, so no construction site has to change.
    public var headOid: String?

    /// What a merge of the base into this branch would conflict on.
    ///
    /// Worked out locally by `MergeTree`, because GitHub reports *that* a pull
    /// request is dirty and never what or how much. nil means the question was
    /// not answered — no clone, no local copy of the base ref, or the row is
    /// not conflicted in the first place — and is deliberately not the same as
    /// an empty array, for the reason `behindBy` is optional: a row that says
    /// "conflicts · 0 files" is contradicting itself.
    public var conflictedFiles: [String]?

    /// GitHub's node id, which every mutation on this pull request needs as
    /// its subject.
    ///
    /// Optional and defaulted like the rest of what was added after the fact.
    /// A row that arrived without one simply cannot be acted on, and says so,
    /// rather than offering a button that would fail.
    public var nodeID: String?

    /// Who owns the repository the head branch lives in.
    ///
    /// nil, or a login that is not the base repo's owner, means a fork — which
    /// resolve must refuse, because it cannot push there. Worth knowing before
    /// a run rather than fifteen minutes into one.
    public var headRepositoryOwner: String?
    /// Which account surfaced this row. Empty until a fetch tags it, and set
    /// after the inbox builds rather than threaded through it — the same
    /// post-build shape `behindBy` already uses, and it keeps every existing
    /// construction site and test compiling unchanged.
    public var account: String = ""

    public let totalThreadCount: Int
    /// `var` so the required-checks phase can fold its answer in, the way
    /// `behindBy` is filled by the compare phase.
    public var checks: ChecksSummary
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

    /// Whether the branch conflicts, whatever is or is not known about how
    /// much. Asked where the count is not the point — the ordering rule that
    /// hides the threads button, for one.
    public var isConflicted: Bool { mergeBlocker == .dirty }

    /// What, if anything, the branch needs doing to it before it can merge.
    ///
    /// Read straight off what GitHub already reports — `mergeStateStatus` and
    /// the compare count — so it needs no local checkout.
    public enum BranchState: Equatable, Sendable {
        case upToDate
        case needsRebase(behindBy: Int?)
        /// `files` is nil when nothing could count them — the same shape, and
        /// the same reason, as `needsRebase`'s count.
        case conflicts(files: Int?)
        /// The compare request didn't answer, so we genuinely don't know.
        case unknown
    }

    public var branchState: BranchState {
        if mergeBlocker == .dirty { return .conflicts(files: conflictedFiles?.count) }
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
                unresolvedThreads: [UnresolvedThread] = [],
                totalThreadCount: Int, checks: ChecksSummary,
                additions: Int, deletions: Int, changedFiles: Int,
                behindBy: Int? = nil, stackedOn: Int? = nil,
                blocksRestackOf: [Int] = [], account: String = "") {
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
        self.unresolvedThreads = unresolvedThreads
        self.totalThreadCount = totalThreadCount
        self.checks = checks
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.behindBy = behindBy
        self.stackedOn = stackedOn
        self.blocksRestackOf = blocksRestackOf
        self.account = account
    }
}
