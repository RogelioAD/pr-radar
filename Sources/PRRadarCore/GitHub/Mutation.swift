import Foundation

/// The write half of the GitHub API.
///
/// Its own file rather than another case in `Query`, which is named for the
/// thing it holds. It is also worth the separation for a blunter reason: until
/// automatic review, this app never wrote to GitHub at all, and a reader should
/// be able to see everything it can now change in one screen.
public enum Mutation {

    /// Submits a review, with every inline thread in the same call.
    ///
    /// One atomic submission rather than a comment followed by N thread calls:
    /// a half-posted review is not a state worth being able to reach, and the
    /// single call is also the only way the threads arrive attached to the
    /// summary rather than as loose comments.
    public static let submitReview = """
    mutation($prId: ID!, $event: PullRequestReviewEvent!, $body: String,
             $threads: [DraftPullRequestReviewThread!]) {
      addPullRequestReview(input: {
        pullRequestId: $prId, event: $event, body: $body, threads: $threads
      }) {
        pullRequestReview {
          id
          url
          state
          submittedAt
          comments(first: 100) { nodes { id } }
        }
      }
    }
    """

    /// Rewrites a review's body — how a superseded review is retired.
    public static let updateReview = """
    mutation($id: ID!, $body: String!) {
      updatePullRequestReview(input: {pullRequestReviewId: $id, body: $body}) {
        pullRequestReview { id url }
      }
    }
    """

    /// Closes one thread, so a re-run does not leave the Files tab full of
    /// suggestions that no longer apply.
    public static let resolveThread = """
    mutation($threadId: ID!) {
      resolveReviewThread(input: {threadId: $threadId}) {
        thread { id isResolved }
      }
    }
    """
}

/// What `addPullRequestReview` gives back.
public struct SubmittedReview: Decodable, Equatable, Sendable {
    public let id: String
    public let url: String
    public let state: String?
    public let submittedAt: Date?
    /// The comments the threads became, so a re-run can resolve them.
    public let commentIDs: [String]

    enum CodingKeys: String, CodingKey { case id, url, state, submittedAt, comments }
    enum CommentKeys: String, CodingKey { case nodes }
    struct Node: Decodable { let id: String }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        submittedAt = try container.decodeIfPresent(Date.self, forKey: .submittedAt)
        if let comments = try? container.nestedContainer(keyedBy: CommentKeys.self,
                                                         forKey: .comments) {
            commentIDs = (try? comments.decode([Node].self, forKey: .nodes))?.map(\.id) ?? []
        } else {
            commentIDs = []
        }
    }

    public init(id: String, url: String, state: String? = nil,
                submittedAt: Date? = nil, commentIDs: [String] = []) {
        self.id = id
        self.url = url
        self.state = state
        self.submittedAt = submittedAt
        self.commentIDs = commentIDs
    }
}

struct SubmitReviewPayload: Decodable {
    struct Wrapper: Decodable { let pullRequestReview: SubmittedReview? }
    let addPullRequestReview: Wrapper?
}

struct UpdateReviewPayload: Decodable {
    struct Review: Decodable { let id: String }
    struct Wrapper: Decodable { let pullRequestReview: Review? }
    let updatePullRequestReview: Wrapper?
}

struct ResolveThreadPayload: Decodable {
    struct Thread: Decodable { let id: String; let isResolved: Bool }
    struct Wrapper: Decodable { let thread: Thread? }
    let resolveReviewThread: Wrapper?
}

/// Which kind of review is being submitted.
///
/// `COMMENT` is the one automatic review uses, and the choice is load-bearing:
/// it deliberately does *not* clear the review request server-side, which is
/// what leaves the decision — approve, request changes, or let the comment
/// stand — with the person whose name is on it.
public enum ReviewEvent: String, Sendable {
    case comment = "COMMENT"
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
}

extension GitHubClient {

    /// Submits a review as the authenticated user.
    ///
    /// `body` is optional for APPROVE and required in practice for
    /// REQUEST_CHANGES — GitHub rejects that event without one, which is why
    /// `AutoReviewComment.reviewBody` is built to never come back empty.
    ///
    /// The timeout is longer than a read's twenty seconds: a review carrying
    /// fifty inline threads is a much larger request than any query here, and
    /// a timeout that fired on a submission that actually landed would leave
    /// PR Radar not knowing whether it had posted.
    public func submitReview(pullRequestID: String,
                             event: ReviewEvent,
                             body: String?,
                             threads: [ReviewThread] = []) async throws -> SubmittedReview {
        var variables: [String: GraphQLValue] = [
            "prId": .string(pullRequestID),
            "event": .string(event.rawValue),
            "body": body.map(GraphQLValue.string) ?? .null,
        ]
        if !threads.isEmpty {
            variables["threads"] = .array(threads.map(Self.draft))
        }

        let payload = try await run(Mutation.submitReview, variables: variables,
                                    as: SubmitReviewPayload.self, timeout: 60)
        guard let review = payload.addPullRequestReview?.pullRequestReview else {
            throw GitHubClientError.emptyPayload
        }
        return review
    }

    public func updateReview(id: String, body: String) async throws {
        _ = try await run(Mutation.updateReview,
                          variables: ["id": .string(id), "body": .string(body)],
                          as: UpdateReviewPayload.self)
    }

    /// Resolves a thread, tolerating the ones that cannot be.
    ///
    /// Returns false rather than throwing: a thread somebody already resolved
    /// by hand is not a failure worth abandoning a re-run over.
    @discardableResult
    public func resolveThread(id: String) async -> Bool {
        let payload = try? await run(Mutation.resolveThread,
                                     variables: ["threadId": .string(id)],
                                     as: ResolveThreadPayload.self)
        return payload?.resolveReviewThread?.thread?.isResolved ?? false
    }

    /// One inline thread, as `DraftPullRequestReviewThread` wants it.
    ///
    /// `startLine` is omitted for a single-line thread because GitHub rejects
    /// one equal to `line`. `side` is always RIGHT: these are comments about
    /// what the pull request does, not about what it replaced.
    static func draft(_ thread: ReviewThread) -> GraphQLValue {
        var fields: [String: GraphQLValue] = [
            "path": .string(thread.path),
            "line": .int(thread.line),
            "side": .string("RIGHT"),
            "body": .string(thread.body),
        ]
        if let startLine = thread.startLine, startLine != thread.line {
            fields["startLine"] = .int(startLine)
            fields["startSide"] = .string("RIGHT")
        }
        return .object(fields)
    }
}
