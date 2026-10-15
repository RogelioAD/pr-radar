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
    public let id: String?
    public let number: Int?
    public let title: String?
    public let url: String?
    public let isDraft: Bool?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let headRefName: String?
    public let baseRefName: String?
    public let headRepositoryOwner: ActorDTO?
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
    public let id: String?
    public let isResolved: Bool?
    public let isOutdated: Bool?
    public let path: String?
    public let line: Int?
    public let comments: ThreadCommentConn?
    public let hunk: ThreadHunkConn?
}

public struct ThreadHunkConn: Decodable {
    public let nodes: [ThreadHunkNode]
}

public struct ThreadHunkNode: Decodable {
    public let diffHunk: String?
}

public struct ThreadCommentConn: Decodable {
    public let totalCount: Int
    public let nodes: [ThreadCommentNode]
}

public struct ThreadCommentNode: Decodable {
    public let id: String?
    public let createdAt: Date?
    public let author: ActorDTO?
    public let body: String?
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

/// Which workflow a check run belongs to, unwrapped from the two levels
/// GraphQL wraps it in. Only the name is read: it identifies the workflow
/// across re-runs, which is exactly what telling a superseded run from a live
/// one needs.
public struct CheckSuiteNode: Decodable {
    public struct WorkflowRun: Decodable {
        public struct Workflow: Decodable {
            public let name: String?
        }
        public let workflow: Workflow?
    }
    public let workflowRun: WorkflowRun?
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
    /// When this run began, or when the status was posted. The tiebreak for
    /// which of two runs of one check is the one GitHub is showing.
    public let startedAt: Date?
    public let createdAt: Date?
    public let checkSuite: CheckSuiteNode?

    enum CodingKeys: String, CodingKey {
        case typename = "__typename"
        case name, conclusion, status, context, state
        case startedAt, createdAt, checkSuite
    }

    /// The single verdict for this context, whichever kind it is.
    public var verdict: String? {
        if typename == "CheckRun" { return conclusion ?? status }
        return state
    }

    public var displayName: String { name ?? context ?? "check" }

    /// What makes two contexts the same check rather than two checks.
    ///
    /// The workflow is part of it, not just the name. Two workflows may each
    /// define a job called `build`, and GitHub shows both — collapsing them on
    /// the name alone would hide one. A status context has no workflow and is
    /// already unique by its own name, so it keys on that.
    public var identity: String {
        let workflow = checkSuite?.workflowRun?.workflow?.name ?? ""
        return "\(workflow)\u{0}\(displayName)"
    }

    /// When this one happened, for picking the later of two.
    public var occurredAt: Date { startedAt ?? createdAt ?? .distantPast }
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

/// The narrow threads-only query's payload.
public struct ThreadsPayload: Decodable {
    public struct Repository: Decodable {
        public let pullRequest: PullRequest?
    }
    public struct PullRequest: Decodable {
        public let reviewThreads: ThreadConn?
    }
    public let repository: Repository?
}
