import XCTest
@testable import PRRadarCore

/// What the CLI printed, read — or the reason there is nothing to read.
final class ResolveParserTests: XCTestCase {

    private let table = """
    {"scope":"This PR adds the hub.","threads":[\
    {"threadId":"T1","disposition":"fix","reply":"Fixed in a1b2c3d","sha":"a1b2c3d"}]}
    """

    private func envelope(_ structured: String) -> String {
        #"{"is_error":false,"result":"ok","structured_output":"# + structured + #"}"#
    }

    private func parse(exitCode: Int32 = 0, stdout: String, stderr: String = "",
                       timedOut: Bool = false,
                       pushed: [String] = []) -> Result<ResolveTable, ResolveFailure> {
        ResolveParser.parse(exitCode: exitCode, stdout: stdout, stderr: stderr,
                            timedOut: timedOut, timeoutSeconds: 5400,
                            pushedShas: pushed)
    }

    func testTheSchemaValidatedObjectIsTheNormalPath() throws {
        let parsed = try parse(stdout: envelope(table)).get()
        XCTAssertEqual(parsed.scope, "This PR adds the hub.")
        XCTAssertEqual(parsed.threads.count, 1)
        XCTAssertEqual(parsed.threads[0].sha, "a1b2c3d")
    }

    func testJSONWrappedInProseIsStillWorthOneAttempt() throws {
        let prose = "Here is the table:\\n\(table)\\nThat's everything."
        let encoded = String(data: try JSONEncoder().encode(prose), encoding: .utf8)!
        let parsed = try parse(stdout: #"{"is_error":false,"result":"# + encoded + #"}"#).get()
        XCTAssertEqual(parsed.threads.count, 1)
    }

    /// The rule inherited from the review parser, and the one that must not
    /// bend: nothing readable is a failure, never an empty table. An empty
    /// table reads as "every thread was already fine."
    func testNothingReadableIsAFailureRatherThanAnEmptyTable() {
        guard case .failure(let failure) = parse(stdout: "just some prose") else {
            return XCTFail("unreadable output must not pass as zero threads")
        }
        guard case .unparseable = failure else {
            return XCTFail("expected unparseable, got \(failure)")
        }
    }

    func testPrintingNothingIsAFailure() {
        guard case .failure = parse(stdout: "") else {
            return XCTFail("silence is not a clean bill of health")
        }
    }

    func testASessionThatReportedItsOwnFailureIsAFailure() {
        let stdout = #"{"is_error":true,"result":"the gate could not be satisfied"}"#
        guard case .failure(.exited(_, let stderr)) = parse(stdout: stdout) else {
            return XCTFail("is_error must not be ignored")
        }
        XCTAssertEqual(stderr, "the gate could not be satisfied")
    }

    func testATimeoutSaysSoInMinutes() {
        guard case .failure(let failure) = parse(stdout: "", timedOut: true) else {
            return XCTFail("expected a timeout")
        }
        XCTAssertEqual(failure.message, "gave up after 90m")
    }

    // MARK: - The case review has no equivalent of

    /// Code is on the user's branch and nobody has read a word about it.
    /// Reporting that as "could not be read" invites a retry, and a retry would
    /// layer a second set of fixes on a first set nobody has seen.
    func testARunThatPushedAndThenFailedSaysSoRatherThanInvitingARetry() {
        guard case .failure(let failure) =
                parse(stdout: "garbage", pushed: ["a1b2c3d", "e4f5a6b"]) else {
            return XCTFail("expected a failure")
        }
        XCTAssertEqual(failure, .landedUnreported(shas: ["a1b2c3d", "e4f5a6b"]))
        XCTAssertTrue(failure.message.contains("2 commits"), failure.message)
        XCTAssertTrue(failure.message.contains("go and look"), failure.message)
    }

    func testATimeoutAfterPushingIsAlsoLandedUnreported() {
        guard case .failure(let failure) =
                parse(stdout: "", timedOut: true, pushed: ["a1b2c3d"]) else {
            return XCTFail("expected a failure")
        }
        XCTAssertEqual(failure, .landedUnreported(shas: ["a1b2c3d"]))
        XCTAssertTrue(failure.message.contains("1 commit "), failure.message)
    }

    /// A run that pushed and *did* report is an ordinary success — the
    /// distinction is about the table, not about the commits.
    func testARunThatPushedAndReportedIsNotAFailure() throws {
        let parsed = try parse(stdout: envelope(table), pushed: ["a1b2c3d"]).get()
        XCTAssertEqual(parsed.threads.count, 1)
    }

    func testANonZeroExitReportsWhatTheCLIItselfSaid() {
        let stdout = #"{"is_error":true,"result":"budget exhausted"}"#
        guard case .failure(.exited(let code, let stderr)) =
                parse(exitCode: 1, stdout: stdout) else {
            return XCTFail("expected an exit failure")
        }
        XCTAssertEqual(code, 1)
        XCTAssertEqual(stderr, "budget exhausted")
    }
}
