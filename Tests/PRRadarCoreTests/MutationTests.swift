import XCTest
@testable import PRRadarCore

final class MutationTests: XCTestCase {

    private func encoded(_ variables: [String: GraphQLValue]) throws -> [String: Any] {
        let request = GraphQLRequest(query: "q", variables: variables.isEmpty ? nil : variables)
        let data = try JSONEncoder().encode(request)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - The read path must not regress

    /// Every existing query goes through the same encoder now. If `variables`
    /// appeared in the body, a whole app's worth of working requests would be
    /// changing shape for the sake of the three that need it.
    func testAQueryWithNoVariablesSendsNoVariablesKey() throws {
        let body = try encoded([:])
        XCTAssertEqual(body["query"] as? String, "q")
        XCTAssertNil(body["variables"])
        XCTAssertEqual(body.count, 1)
    }

    // MARK: - Variables

    /// The entire reason the write path uses variables: a review body is full
    /// of backticks, quotes and newlines, and it arrives as a JSON string
    /// rather than as part of the document.
    func testABodyWithQuotesAndNewlinesTravelsIntact() throws {
        let body = #"He said "no".\#nHere: `foo\bar` and ```suggestion"#
        let encodedBody = try encoded(["body": .string(body)])
        let variables = try XCTUnwrap(encodedBody["variables"] as? [String: Any])
        XCTAssertEqual(variables["body"] as? String, body)
    }

    func testEveryValueKindEncodesAsItself() throws {
        let variables = try XCTUnwrap(try encoded([
            "s": .string("x"), "i": .int(3), "b": .bool(true), "n": .null,
            "a": .array([.int(1), .int(2)]),
            "o": .object(["k": .string("v")]),
        ])["variables"] as? [String: Any])
        XCTAssertEqual(variables["s"] as? String, "x")
        XCTAssertEqual(variables["i"] as? Int, 3)
        XCTAssertEqual(variables["b"] as? Bool, true)
        XCTAssertTrue(variables["n"] is NSNull)
        XCTAssertEqual(variables["a"] as? [Int], [1, 2])
        XCTAssertEqual((variables["o"] as? [String: Any])?["k"] as? String, "v")
    }

    // MARK: - The documents

    func testEveryMutationDeclaresTheVariablesItUses() {
        XCTAssertTrue(Mutation.submitReview.contains("$prId: ID!"))
        XCTAssertTrue(Mutation.submitReview.contains("$event: PullRequestReviewEvent!"))
        XCTAssertTrue(Mutation.submitReview.contains("$threads: [DraftPullRequestReviewThread!]"))
        XCTAssertTrue(Mutation.updateReview.contains("$id: ID!"))
        XCTAssertTrue(Mutation.resolveThread.contains("$threadId: ID!"))
    }

    /// A submitted review's node id is what the pin names and what a re-run
    /// supersedes, so the mutation has to ask for it.
    func testSubmitReviewAsksForTheIdThePinWillName() {
        XCTAssertTrue(Mutation.submitReview.contains("pullRequestReview {"))
        XCTAssertTrue(Mutation.submitReview.contains("comments(first: 100) { nodes { id } }"))
    }

    func testTheEventsAreSpelledTheWayGitHubExpects() {
        XCTAssertEqual(ReviewEvent.comment.rawValue, "COMMENT")
        XCTAssertEqual(ReviewEvent.approve.rawValue, "APPROVE")
        XCTAssertEqual(ReviewEvent.requestChanges.rawValue, "REQUEST_CHANGES")
    }

    // MARK: - Draft threads

    /// GitHub rejects a startLine equal to line, and one rejected thread costs
    /// the whole review.
    func testASingleLineThreadSendsNoStartLine() throws {
        guard case .object(let fields) = GitHubClient.draft(
            ReviewThread(path: "F.swift", line: 12, body: "b")) else {
            return XCTFail("expected an object")
        }
        XCTAssertNil(fields["startLine"])
        XCTAssertEqual(fields["line"], .int(12))
        XCTAssertEqual(fields["path"], .string("F.swift"))
    }

    func testAMultiLineThreadSendsBothEnds() {
        guard case .object(let fields) = GitHubClient.draft(
            ReviewThread(path: "F.swift", line: 14, startLine: 12, body: "b")) else {
            return XCTFail("expected an object")
        }
        XCTAssertEqual(fields["startLine"], .int(12))
        XCTAssertEqual(fields["line"], .int(14))
    }

    /// A startLine that happens to equal line would be rejected, so it is
    /// dropped rather than passed through.
    func testAStartLineEqualToTheLineIsDropped() {
        guard case .object(let fields) = GitHubClient.draft(
            ReviewThread(path: "F.swift", line: 12, startLine: 12, body: "b")) else {
            return XCTFail("expected an object")
        }
        XCTAssertNil(fields["startLine"])
    }

    /// These are comments about what the pull request does, not about what it
    /// replaced — and a LEFT-side anchor on an added line is rejected.
    func testThreadsAreAlwaysAnchoredToTheRightSide() {
        guard case .object(let fields) = GitHubClient.draft(
            ReviewThread(path: "F.swift", line: 14, startLine: 12, body: "b")) else {
            return XCTFail("expected an object")
        }
        XCTAssertEqual(fields["side"], .string("RIGHT"))
        XCTAssertEqual(fields["startSide"], .string("RIGHT"))
    }

    // MARK: - Decoding the response

    func testASubmittedReviewCarriesItsThreadCommentIDs() throws {
        let json = #"""
        {"id":"PRR_1","url":"https://github.com/a/b/pull/1#pullrequestreview-1",
         "state":"COMMENTED","comments":{"nodes":[{"id":"PRRC_1"},{"id":"PRRC_2"}]}}
        """#
        let review = try JSONDecoder().decode(SubmittedReview.self, from: Data(json.utf8))
        XCTAssertEqual(review.id, "PRR_1")
        XCTAssertEqual(review.commentIDs, ["PRRC_1", "PRRC_2"])
    }

    /// A review with no inline threads is still a review.
    func testAReviewWithNoCommentsDecodesToAnEmptyList() throws {
        let json = #"{"id":"PRR_1","url":"https://x","state":"COMMENTED"}"#
        let review = try JSONDecoder().decode(SubmittedReview.self, from: Data(json.utf8))
        XCTAssertTrue(review.commentIDs.isEmpty)
    }
}
