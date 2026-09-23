import Foundation

// Payload for the "my PRs" query.
//
// This is a *separate* request from the reviews query rather than another alias
// in the same document. The reviews document carries one dynamically-named
// search alias per team, so it decodes as `[String: SearchResult]` — a
// homogeneous dictionary. Mixing a differently-shaped `mine:` alias into it
// would force that decode to become untyped. Two small requests are cheaper to
// reason about than one union.

public struct MyPRPayload: Decodable {
    public let mine: MyPRSearchResult
}

public struct MyPRSearchResult: Decodable {
    public let issueCount: Int
    public let nodes: [MyPRNode]
}

public struct MyPRNode: Decodable {
    public let number: Int?
    public let title: String?
    public let url: String?
    public let isDraft: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let headRefName: String?
    public let baseRefName: String?
    public let reviewDecision: String?
    public let mergeStateStatus: String?
    public let mergeable: String?
    public let additions: Int?
    public let deletions: Int?
    public let changedFiles: Int?
    public let repository: RepoDTO?
    public let latestReviews: ReviewConn?
    public let reviewRequests: RequestConn?
    public let reviewThreads: ThreadConn?
    public let commits: CommitConn?
}

public struct ReviewConn: Decodable {
    public let nodes: [ReviewNode]
}

public struct ReviewNode: Decodable {
    public let author: ActorDTO?
    public let state: String?
    public let submittedAt: Date?
}

public struct RequestConn: Decodable {
    public let nodes: [RequestNode]
}

public struct RequestNode: Decodable {
    public let requestedReviewer: ReviewerDTO?
}

public struct ThreadConn: Decodable {
    public let totalCount: Int
    public let nodes: [ThreadNode]
}

public struct ThreadNode: Decodable {
    public let isResolved: Bool?
    public let isOutdated: Bool?
}

public struct CommitConn: Decodable {
    public let nodes: [CommitWrapper]
}

public struct CommitWrapper: Decodable {
    public let commit: CommitNode?
}

public struct CommitNode: Decodable {
    public let oid: String?
    public let statusCheckRollup: RollupNode?
}

public struct RollupNode: Decodable {
    public let state: String?
    public let contexts: ContextConn?
}

public struct ContextConn: Decodable {
    public let totalCount: Int
    public let nodes: [ContextNode]
}

/// Union of CheckRun and StatusContext — the two kinds of check GitHub reports.
/// A CheckRun carries `conclusion` once finished and `status` while running; a
/// StatusContext only ever has `state`.
public struct ContextNode: Decodable {
    public let typename: String
    public let name: String?
    public let conclusion: String?
    public let status: String?
    public let context: String?
    public let state: String?
    /// Which workflow run produced this CheckRun. nil for a StatusContext, and
    /// for a CheckRun posted by an app that does not run on Actions.
    public let checkSuite: CheckSuiteNode?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case name, conclusion, status, context, state, checkSuite
    }

    /// The single verdict for this context, whichever kind it is.
    public var verdict: String? {
        if typename == "CheckRun" { return conclusion ?? status }
        return state
    }

    public var displayName: String { name ?? context ?? "check" }

    /// The workflow this check belongs to, if it came from one.
    public var workflow: String? { checkSuite?.workflowRun?.workflow?.name }

    /// Orders two runs of the same workflow. `createdAt` decides it; the id is
    /// only a tie-break, because two runs can start within the same second.
    public var runOrder: (Date, Int)? {
        guard let run = checkSuite?.workflowRun, let created = run.createdAt
        else { return nil }
        return (created, run.databaseId ?? 0)
    }
}

public struct CheckSuiteNode: Decodable {
    public let workflowRun: WorkflowRunNode?
}

public struct WorkflowRunNode: Decodable {
    public let databaseId: Int?
    public let createdAt: Date?
    public let workflow: WorkflowDTO?
}

public struct WorkflowDTO: Decodable {
    public let name: String?
}

// MARK: - Second-phase compare payload

/// `compare` is a repository-level field, so it cannot be aliased inside search
/// results before the PR list is known. This is fetched in a follow-up request,
/// one alias per PR.
public struct CompareResult: Decodable {
    public let ref: RefNode?
}

public struct RefNode: Decodable {
    public let compare: ComparisonNode?
}

public struct ComparisonNode: Decodable {
    public let aheadBy: Int?
    public let behindBy: Int?
    public let status: String?
}
