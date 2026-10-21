import XCTest
@testable import PRRadarCore

/// Telling a failing check that blocks the merge from one that does not.
final class RequiredChecksTests: XCTestCase {

    func summary(failing: Int, names: [String] = [], required: [String]? = nil)
    -> ChecksSummary {
        ChecksSummary(passing: 3, failing: failing, running: 0, skipped: 0,
                      failingNames: names, rollupState: nil,
                      requiredFailingNames: required)
    }

    func item(_ number: Int, repo: String = "acme/repo",
              checks: ChecksSummary) -> MyPullRequest {
        MyPullRequest(repo: repo, number: number, title: "t",
                      url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
                      isDraft: false, createdAt: Date(), updatedAt: Date(),
                      headRefName: "head", baseRefName: "main",
                      reviewDecision: .none, mergeBlocker: .unstable,
                      approvals: [], awaitingReviewers: [],
                      unresolvedThreadCount: 0, totalThreadCount: 0,
                      checks: checks, additions: 1, deletions: 0, changedFiles: 1)
    }

    // MARK: - What the tally claims

    /// nil is *not known*, and it is where every row starts. It must never be
    /// read as *nothing is required* — the same distinction a failed branch
    /// compare makes between unknown and up to date.
    func testUnknownIsNotTheSameAsNoneRequired() {
        XCTAssertNil(summary(failing: 2).hasBlockingFailure)
        XCTAssertNil(summary(failing: 2).blockingLabel)

        let verified = summary(failing: 2, required: [])
        XCTAssertEqual(verified.hasBlockingFailure, false)
        XCTAssertEqual(verified.blockingLabel, "none blocking")
    }

    func testBlockingLabelCounts() {
        XCTAssertEqual(summary(failing: 3, required: ["build"]).blockingLabel,
                       "1 blocking")
        XCTAssertEqual(summary(failing: 3, required: ["build", "test"]).blockingLabel,
                       "2 blocking")
    }

    // MARK: - Severity

    /// A failure nothing requires is a real failure and a lesser one: the
    /// branch can still merge. It drops to attention rather than disappearing,
    /// because red is still red.
    func testANonBlockingFailureIsLessSevere() {
        XCTAssertEqual(summary(failing: 2, required: []).health, .attention)
        XCTAssertEqual(summary(failing: 2, required: ["build"]).health, .bad)
    }

    /// While required-ness is unknown, a failure is treated as the worst it
    /// could be. That is the honest reading of a question not yet asked.
    func testAnUnknownFailureIsTreatedAsBlocking() {
        XCTAssertEqual(summary(failing: 2).health, .bad)
    }

    func testPassingAndRunningAreUnaffected() {
        XCTAssertEqual(summary(failing: 0).health, .good)
        XCTAssertEqual(ChecksSummary(passing: 0, failing: 0, running: 2, skipped: 0,
                                     failingNames: [], rollupState: nil).health,
                       .running)
    }

    // MARK: - Which rows get asked

    /// Most pull requests are green, and re-fetching a hundred context nodes
    /// per row per minute to learn that nothing is failing is a cost the
    /// common path should not pay.
    func testOnlyFailingRowsAreAskedAbout() {
        let items = [item(1, checks: summary(failing: 0)),
                     item(2, checks: summary(failing: 2)),
                     item(3, checks: summary(failing: 0)),
                     item(4, checks: summary(failing: 1))]
        let targets = MyPRInbox.requiredCheckTargets(items)
        XCTAssertEqual(targets.map(\.number), [2, 4])
    }

    /// The index is into the full array, so an alias always names the same
    /// item whether or not it was asked about.
    func testTargetsAreIndexedAgainstTheWholeList() {
        let items = [item(1, checks: summary(failing: 0)),
                     item(2, checks: summary(failing: 2))]
        XCTAssertEqual(MyPRInbox.requiredCheckTargets(items).map(\.index), [1])
    }

    func testNothingFailingSendsNoQuery() {
        let items = [item(1, checks: summary(failing: 0))]
        XCTAssertNil(Query.requiredChecks(MyPRInbox.requiredCheckTargets(items)))
    }

    func testTheQueryNamesTheNumberInBothPlaces() throws {
        let query = try XCTUnwrap(Query.requiredChecks([(index: 0, repo: "acme/repo",
                                                         number: 42)]))
        XCTAssertTrue(query.contains("r0: repository(owner: \"acme\", name: \"repo\")"))
        XCTAssertTrue(query.contains("pullRequest(number: 42)"))
        // Once per union branch: a GraphQL argument cannot refer to a sibling
        // field, so the number is written out at each place that asks.
        XCTAssertEqual(query.components(separatedBy: "isRequired(pullRequestNumber: 42)")
                            .count - 1, 2)
    }

    // MARK: - Applying the answer

    func payload(_ contexts: [(name: String, conclusion: String, required: Bool,
                               started: String)]) -> [String: RequiredChecksResult] {
        let nodes = contexts.map { c in
            #"{"__typename":"CheckRun","name":"\#(c.name)","conclusion":"\#(c.conclusion)","#
            + #""startedAt":"\#(c.started)","isRequired":\#(c.required)}"#
        }.joined(separator: ",")
        let json = """
        {"r0":{"pullRequest":{"commits":{"nodes":[{"commit":{"statusCheckRollup":
          {"contexts":{"totalCount":\(contexts.count),"nodes":[\(nodes)]}}}}]}}}}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode([String: RequiredChecksResult].self,
                                   from: Data(json.utf8))
    }

    func testNamesOnlyTheFailingRequiredOnes() {
        let items = [item(1, checks: summary(failing: 2,
                                             names: ["build", "lint"]))]
        let applied = MyPRInbox.applyRequiredChecks(payload([
            (name: "build", conclusion: "FAILURE", required: true,
             started: "2026-01-01T00:00:00Z"),
            (name: "lint", conclusion: "FAILURE", required: false,
             started: "2026-01-01T00:00:00Z"),
            (name: "docs", conclusion: "SUCCESS", required: true,
             started: "2026-01-01T00:00:00Z"),
        ]), to: items)
        XCTAssertEqual(applied[0].checks.requiredFailingNames, ["build"])
        XCTAssertEqual(applied[0].checks.blockingLabel, "1 blocking")
    }

    func testAVerifiedEmptyIsRecorded() {
        let items = [item(1, checks: summary(failing: 1, names: ["lint"]))]
        let applied = MyPRInbox.applyRequiredChecks(payload([
            (name: "lint", conclusion: "FAILURE", required: false,
             started: "2026-01-01T00:00:00Z"),
        ]), to: items)
        XCTAssertEqual(applied[0].checks.requiredFailingNames, [])
        XCTAssertEqual(applied[0].checks.health, .attention)
    }

    /// A missing alias is *not asked*, which is *not known*, and the row has
    /// to stay exactly as it was rather than gaining a claim nobody checked.
    func testAMissingAliasLeavesItUnknown() {
        let items = [item(1, checks: summary(failing: 2))]
        let applied = MyPRInbox.applyRequiredChecks([:], to: items)
        XCTAssertNil(applied[0].checks.requiredFailingNames)
        XCTAssertEqual(applied[0].checks.health, .bad)
    }

    /// A cancelled run and the re-run that replaced it both come back from
    /// this query too. Counting the cancelled one as a required failure would
    /// re-create the bug the main tally already fixed.
    func testASupersededRunIsNotARequiredFailure() {
        let items = [item(1, checks: summary(failing: 0))]
        let applied = MyPRInbox.applyRequiredChecks(payload([
            (name: "build", conclusion: "CANCELLED", required: true,
             started: "2026-01-01T00:00:00Z"),
            (name: "build", conclusion: "SUCCESS", required: true,
             started: "2026-01-01T01:00:00Z"),
        ]), to: items)
        XCTAssertEqual(applied[0].checks.requiredFailingNames, [])
    }

    /// And the other way round: a passing run superseded by a failing re-run
    /// is a required failure.
    func testAReRunThatFailsIsARequiredFailure() {
        let items = [item(1, checks: summary(failing: 1))]
        let applied = MyPRInbox.applyRequiredChecks(payload([
            (name: "build", conclusion: "SUCCESS", required: true,
             started: "2026-01-01T00:00:00Z"),
            (name: "build", conclusion: "FAILURE", required: true,
             started: "2026-01-01T01:00:00Z"),
        ]), to: items)
        XCTAssertEqual(applied[0].checks.requiredFailingNames, ["build"])
    }

    /// Every verdict the tally calls a failure, the required phase calls a
    /// failure. One list, read from both, so the two cannot disagree.
    func testBothHalvesAgreeOnWhatFailingMeans() {
        for verdict in ["FAILURE", "ERROR", "TIMED_OUT", "CANCELLED",
                        "ACTION_REQUIRED", "STARTUP_FAILURE"] {
            XCTAssertTrue(MyPRInbox.isFailure(verdict), verdict)
        }
        for verdict in ["SUCCESS", "SKIPPED", "NEUTRAL", "STALE",
                        "IN_PROGRESS", "QUEUED", nil] {
            XCTAssertFalse(MyPRInbox.isFailure(verdict), verdict ?? "nil")
        }
    }
}
