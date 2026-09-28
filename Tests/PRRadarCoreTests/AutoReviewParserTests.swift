import XCTest
@testable import PRRadarCore

final class AutoReviewParserTests: XCTestCase {

    private let findingsJSON = #"""
    {"verdict":"needs work","findings":[
      {"tier":"priority","file":"Sources/Foo.swift","line":42,
       "summary":"the closure retains self","recommendation":"capture self weakly"},
      {"tier":"nit","summary":"spelling","recommendation":"fix it"}
    ]}
    """#

    private func envelope(result: String, structured: String? = nil,
                          isError: Bool = false) -> String {
        let escaped = String(data: try! JSONEncoder().encode(result), encoding: .utf8)!
        let structuredField = structured.map { ",\"structured_output\":\($0)" } ?? ""
        return #"{"type":"result","subtype":"success","is_error":\#(isError),"result":\#(escaped)\#(structuredField)}"#
    }

    private func parse(_ stdout: String, exitCode: Int32 = 0, stderr: String = "",
                       timedOut: Bool = false) -> Result<AutoReviewFindings, AutoReviewFailure> {
        AutoReviewParser.parse(exitCode: exitCode, stdout: stdout, stderr: stderr,
                               timedOut: timedOut, timeoutSeconds: 600)
    }

    // MARK: - The normal path

    /// The CLI puts the schema-validated object on `structured_output`, beside
    /// the `result` string. That is what a successful run actually looks like,
    /// confirmed against the CLI rather than assumed.
    func testTheStructuredOutputFieldIsPreferred() throws {
        let result = parse(envelope(result: "ignored prose", structured: findingsJSON))
        let findings = try XCTUnwrap(try? result.get())
        XCTAssertEqual(findings.count(.priority), 1)
        XCTAssertEqual(findings.verdict, "needs work")
    }

    func testAJSONStringInTheResultFieldIsParsed() throws {
        let findings = try XCTUnwrap(try? parse(envelope(result: findingsJSON)).get())
        XCTAssertEqual(findings.findings.count, 2)
    }

    /// A model that wrapped its answer in a sentence has still done the work.
    func testJSONEmbeddedInProseIsRecovered() throws {
        let prose = "Here is what I found:\n\(findingsJSON)\nHope that helps."
        let findings = try XCTUnwrap(try? parse(envelope(result: prose)).get())
        XCTAssertEqual(findings.count(.priority), 1)
    }

    // MARK: - The rule that must not bend

    /// Posting "no issues found" because a parse fell through is an automated
    /// clean bill of health under the user's own name, backed by nothing.
    func testProseWithNoJSONIsAFailureAndNotAnEmptyResult() {
        let result = parse(envelope(result: "I would need to see the diff first."))
        guard case .failure(let failure) = result else {
            return XCTFail("prose must not read as zero findings")
        }
        guard case .unparseable = failure else {
            return XCTFail("expected .unparseable, got \(failure)")
        }
    }

    func testAnEmptyStdoutIsAFailure() {
        guard case .failure(.unparseable) = parse("") else {
            return XCTFail("nothing printed is not a clean review")
        }
    }

    /// An empty findings array *is* a real answer, and must still be told apart
    /// from a parse that failed.
    func testAnExplicitlyEmptyFindingsArrayIsASuccess() throws {
        let findings = try XCTUnwrap(try? parse(
            envelope(result: "ok", structured: #"{"findings":[]}"#)).get())
        XCTAssertTrue(findings.findings.isEmpty)
    }

    // MARK: - Failures

    func testATimeoutIsItsOwnFailureRatherThanAnExitCode() {
        guard case .failure(.timedOut(let seconds)) = parse("", timedOut: true) else {
            return XCTFail("expected a timeout")
        }
        XCTAssertEqual(seconds, 600)
    }

    func testANonZeroExitCarriesStderrIntoTheMessage() {
        let result = parse("", exitCode: 2, stderr: "unknown skill: /nope")
        guard case .failure(let failure) = result else { return XCTFail("expected a failure") }
        XCTAssertTrue(failure.message.contains("unknown skill"))
    }

    /// A session that reported its own failure is a failure, whatever else it
    /// managed to print alongside.
    func testASessionThatReportsIsErrorIsAFailure() {
        let result = parse(envelope(result: "hit the budget", structured: findingsJSON,
                                    isError: true))
        guard case .failure = result else { return XCTFail("is_error must not be ignored") }
    }

    // MARK: - Tolerance

    /// A skill inventing a fourth category should not throw away the three it
    /// got right.
    func testAnUnknownTierDropsOneFindingRatherThanThePayload() throws {
        let mixed = #"{"findings":[{"tier":"blocker","summary":"x","recommendation":"y"},{"tier":"mild","summary":"a","recommendation":"b"}]}"#
        let findings = try XCTUnwrap(try? parse(
            envelope(result: "ok", structured: mixed)).get())
        XCTAssertEqual(findings.findings.count, 1)
        XCTAssertEqual(findings.findings.first?.tier, .mild)
    }

    /// A finding with no recommendation is a complaint, and the schema requires
    /// one — so an entry missing it is dropped rather than posted.
    func testAFindingWithNoRecommendationIsDropped() throws {
        let partial = #"{"findings":[{"tier":"mild","summary":"x"},{"tier":"mild","summary":"a","recommendation":"b"}]}"#
        let findings = try XCTUnwrap(try? parse(
            envelope(result: "ok", structured: partial)).get())
        XCTAssertEqual(findings.findings.count, 1)
    }

    // MARK: - The brace scanner

    func testBracesInsideStringsDoNotEndTheObject() {
        let text = #"noise {"a":"}{","b":1} trailing"#
        XCTAssertEqual(AutoReviewParser.firstJSONObject(in: text), #"{"a":"}{","b":1}"#)
    }

    func testAnEscapedQuoteDoesNotEndTheString() {
        let text = #"{"a":"say \"hi\" {"}"#
        XCTAssertEqual(AutoReviewParser.firstJSONObject(in: text), text)
    }

    func testAnUnbalancedObjectIsNotRecovered() {
        XCTAssertNil(AutoReviewParser.firstJSONObject(in: #"{"a":1"#))
    }
}

// MARK: - Saying what actually went wrong

extension AutoReviewParserTests {

    /// A CLI that fails on its own terms reports on stdout, as its own JSON,
    /// and leaves stderr empty. Reading only stderr turned every one of those
    /// into "exited with code 1" and nothing else — the least useful thing a
    /// failed review can say, and exactly the case where the detail is needed.
    func testANonZeroExitFallsBackToStdoutWhenStderrIsSilent() {
        let envelope = #"{"type":"result","is_error":true,"result":"Credit balance is too low"}"#
        let result = AutoReviewParser.parse(exitCode: 1, stdout: envelope, stderr: "",
                                            timedOut: false, timeoutSeconds: 600)
        guard case .failure(let failure) = result else { return XCTFail("expected a failure") }
        XCTAssertTrue(failure.message.contains("Credit balance is too low"), failure.message)
    }

    func testRawStdoutIsUsedWhenThereIsNoEnvelopeToReadItFrom() {
        let result = AutoReviewParser.parse(exitCode: 1, stdout: "command not found: claude",
                                            stderr: "", timedOut: false, timeoutSeconds: 600)
        guard case .failure(let failure) = result else { return XCTFail("expected a failure") }
        XCTAssertTrue(failure.message.contains("command not found"), failure.message)
    }

    /// stderr still wins when there is one — it is the more direct report.
    func testStderrIsPreferredWhenThereIsOne() {
        let result = AutoReviewParser.parse(exitCode: 1, stdout: "noise", stderr: "real reason",
                                            timedOut: false, timeoutSeconds: 600)
        guard case .failure(let failure) = result else { return XCTFail("expected a failure") }
        XCTAssertTrue(failure.message.contains("real reason"), failure.message)
        XCTAssertFalse(failure.message.contains("noise"))
    }

    /// Silence on both is at least admitted rather than dressed up.
    func testAnExitWithNothingSaidAdmitsAsMuch() {
        let result = AutoReviewParser.parse(exitCode: 1, stdout: "", stderr: "",
                                            timedOut: false, timeoutSeconds: 600)
        guard case .failure(let failure) = result else { return XCTFail("expected a failure") }
        XCTAssertTrue(failure.message.contains("said nothing"), failure.message)
    }
}
