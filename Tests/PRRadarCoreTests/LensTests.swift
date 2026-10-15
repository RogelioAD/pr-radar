import XCTest
@testable import PRRadarCore

final class LensTests: XCTestCase {

    // MARK: - The invariant the feature exists under

    /// **The whole point, asserted rather than assumed.**
    ///
    /// A populated lens store must make no difference whatsoever to what gets
    /// posted. This is structurally true — `AutoReviewComment` composes from
    /// `Finding` and has never heard of `LensStore` — and that is exactly why
    /// it is worth a test: a future refactor that "helpfully" threads a reading
    /// into the composer would break nothing visible, and would post a
    /// paraphrase of somebody's review under the user's own name.
    func testAReadingNeverReachesAPostedReview() {
        let finding = Finding(
            tier: .priority, file: "Pool.kt", line: 128,
            summary: "The keyed resource pool violates its residency invariant "
                   + "when a teardown races an acquisition.",
            detail: "Observed under configuration change.",
            recommendation: "Hold the lock across the teardown path.")

        var store = LensStore()
        store.store("The video player pool can hand the same player to two "
                    + "screens at once.", for: finding.summary)
        XCTAssertNotNil(store.reading(for: finding.summary))

        let body = AutoReviewComment.threadBody(finding, moved: false, originalLine: 128)
        XCTAssertTrue(body.contains("violates its residency invariant"),
                      "the posted body must carry the original words")
        XCTAssertFalse(body.contains("two screens at once"),
                       "a plain-English reading must never reach a posted body")

        let line = AutoReviewComment.summaryLine(finding, inlined: true)
        XCTAssertTrue(line.contains("violates its residency invariant"))
        XCTAssertFalse(line.contains("two screens at once"))
    }

    // MARK: - Keying

    func testTheKeyIsTheTextSoIdenticalTextSharesAReading() {
        var store = LensStore()
        store.store("plain", for: "The same sentence.")
        XCTAssertEqual(store.reading(for: "The same sentence."), "plain")
        XCTAssertEqual(store.count, 1)
    }

    /// Wrapping and trailing whitespace are not a different sentence.
    func testKeyingIgnoresSurroundingWhitespaceAndLineEndings() {
        XCTAssertEqual(LensStore.key(for: "a sentence"),
                       LensStore.key(for: "  a sentence\n"))
        XCTAssertEqual(LensStore.key(for: "one\r\ntwo"),
                       LensStore.key(for: "one\ntwo"))
    }

    /// The case that protects against the only genuinely harmful outcome:
    /// confidently plain, and about something else.
    func testEditedTextMissesRatherThanServingTheOldReading() {
        var store = LensStore()
        store.store("the old reading", for: "Original wording.")
        XCTAssertNil(store.reading(for: "Rewritten wording."))
    }

    func testAnEmptyReadingIsNotStored() {
        var store = LensStore()
        store.store("   \n ", for: "something")
        XCTAssertTrue(store.isEmpty)
        XCTAssertNil(store.reading(for: "something"))
    }

    func testMissingReportsOnlyUnreadAndDeduplicates() {
        var store = LensStore()
        store.store("read", for: "first")
        let missing = store.missing(from: ["first", "second", "second", "third"])
        XCTAssertEqual(missing, ["second", "third"])
    }

    // MARK: - Pruning

    func testPruningDropsWhatIsNoLongerLive() {
        var store = LensStore()
        store.store("a", for: "kept")
        store.store("b", for: "dropped")
        store.prune(keeping: ["kept"])
        XCTAssertEqual(store.reading(for: "kept"), "a")
        XCTAssertNil(store.reading(for: "dropped"))
    }

    func testPruningCapsWhatSurvives() {
        var store = LensStore()
        let sources = (0..<50).map { "source \($0)" }
        for source in sources { store.store("reading", for: source) }
        store.prune(keeping: sources, limit: 10)
        XCTAssertEqual(store.count, 10)
    }

    func testRoundTripsThroughItsStoredForm() {
        var store = LensStore()
        store.store("a plain reading", for: "a dense one")
        let decoded = LensStore.decoded(from: store.encoded())
        XCTAssertEqual(decoded.reading(for: "a dense one"), "a plain reading")
    }

    func testAnUnreadableStoreDecodesEmptyRatherThanThrowing() {
        XCTAssertTrue(LensStore.decoded(from: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(LensStore.decoded(from: nil).isEmpty)
    }

    // MARK: - Invocation

    /// No tools at all. A session handed other people's prose must not be able
    /// to act on a sentence inside it.
    func testTheRunCanUseNoToolsAtAll() {
        XCTAssertTrue(LensInvocation.allowedTools.isEmpty)
        for tool in ["Edit", "Write", "Bash", "Read", "WebFetch", "AskUserQuestion"] {
            XCTAssertTrue(LensInvocation.disallowedTools.contains(tool),
                          "\(tool) must be denied by name")
        }
    }

    func testArgumentsCarryTheSchemaAndTheDenials() {
        let arguments = LensInvocation.arguments(
            for: LensRequest(sources: ["one"], model: "claude-haiku-4-5-20251001",
                             budgetUSD: 1))
        XCTAssertTrue(arguments.contains("--json-schema"))
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertTrue(arguments.contains("claude-haiku-4-5-20251001"))
        XCTAssertTrue(arguments.contains("1.00"))
        XCTAssertFalse(arguments.contains("--allowedTools"),
                       "an empty allow-list is expressed by denying by name")
    }

    /// Zero is "no ceiling", not "spend nothing" — the same rule the other two
    /// invocations follow.
    func testAZeroBudgetIsNotPassedThrough() {
        let arguments = LensInvocation.arguments(
            for: LensRequest(sources: ["one"], budgetUSD: 0))
        XCTAssertFalse(arguments.contains("--max-budget-usd"))
    }

    func testItemsAreDelimitedSoFencedCodeCannotSplitThem() {
        let withFence = "Look at this:\n```\nlet x = 1\n```\nIt is wrong."
        let prompt = LensInvocation.prompt(
            for: LensRequest(sources: [withFence, "second"]))
        XCTAssertTrue(prompt.contains("<<<ITEM 0>>>"))
        XCTAssertTrue(prompt.contains("<<<ITEM 1>>>"))
        XCTAssertTrue(prompt.contains("let x = 1"))
    }

    func testBatchingSplitsAtTheLimit() {
        XCTAssertTrue(LensInvocation.batches(of: []).isEmpty)
        let sources = (0..<20).map { "s\($0)" }
        let batches = LensInvocation.batches(of: sources)
        XCTAssertEqual(batches.count, 3)
        XCTAssertEqual(batches[0].count, LensInvocation.batchSize)
        XCTAssertEqual(batches[2].count, 20 - 2 * LensInvocation.batchSize)
        // Order is preserved, which is what makes a visible-first list arrive
        // visible-first.
        XCTAssertEqual(batches.flatMap { $0 }, sources)
    }

    /// Low effort is a measured choice, not a default: the batch of twenty
    /// that took 83 seconds at the default took 25 at this one.
    func testTheRunAsksForLowEffort() {
        let arguments = LensInvocation.arguments(for: LensRequest(sources: ["one"]))
        guard let index = arguments.firstIndex(of: "--effort") else {
            return XCTFail("the lens must pin its effort level")
        }
        XCTAssertEqual(arguments[index + 1], "low")
    }

    // MARK: - Parsing

    private func envelope(_ json: String) -> String {
        "{\"is_error\":false,\"structured_output\":\(json)}"
    }

    func testReadingsAreFiledAgainstTheSourceTheyIndex() {
        let stdout = envelope(
            "{\"readings\":[{\"id\":\"1\",\"plain\":\"second plainly\"}," +
            "{\"id\":\"0\",\"plain\":\"first plainly\"}]}")
        let parsed = LensParser.parse(exitCode: 0, stdout: stdout, timedOut: false,
                                      sources: ["first", "second"])
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed.first { $0.source == "first" }?.plain, "first plainly")
        XCTAssertEqual(parsed.first { $0.source == "second" }?.plain, "second plainly")
    }

    /// A reading filed against the wrong source is the one way this feature can
    /// actively mislead, so an id it cannot place is dropped.
    func testAnOutOfRangeIdIsDroppedRatherThanGuessed() {
        let stdout = envelope(
            "{\"readings\":[{\"id\":\"7\",\"plain\":\"nowhere to put this\"}," +
            "{\"id\":\"not a number\",\"plain\":\"nor this\"}," +
            "{\"id\":\"0\",\"plain\":\"this one is fine\"}]}")
        let parsed = LensParser.parse(exitCode: 0, stdout: stdout, timedOut: false,
                                      sources: ["only"])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].source, "only")
    }

    func testADuplicateIdDoesNotOverwriteTheFirst() {
        let stdout = envelope(
            "{\"readings\":[{\"id\":\"0\",\"plain\":\"first answer\"}," +
            "{\"id\":\"0\",\"plain\":\"second answer\"}]}")
        let parsed = LensParser.parse(exitCode: 0, stdout: stdout, timedOut: false,
                                      sources: ["only"])
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].plain, "first answer")
    }

    func testFailureIsSilentBecauseTheOriginalIsAlwaysCorrect() {
        let good = envelope("{\"readings\":[{\"id\":\"0\",\"plain\":\"fine\"}]}")
        XCTAssertTrue(LensParser.parse(exitCode: 1, stdout: good, timedOut: false,
                                       sources: ["a"]).isEmpty)
        XCTAssertTrue(LensParser.parse(exitCode: 0, stdout: good, timedOut: true,
                                       sources: ["a"]).isEmpty)
        XCTAssertTrue(LensParser.parse(exitCode: 0, stdout: "not json",
                                       timedOut: false, sources: ["a"]).isEmpty)
        XCTAssertTrue(LensParser.parse(
            exitCode: 0, stdout: "{\"is_error\":true,\"result\":\"boom\"}",
            timedOut: false, sources: ["a"]).isEmpty)
    }

    func testAnEmptyReadingIsDropped() {
        let stdout = envelope("{\"readings\":[{\"id\":\"0\",\"plain\":\"  \"}]}")
        XCTAssertTrue(LensParser.parse(exitCode: 0, stdout: stdout, timedOut: false,
                                       sources: ["a"]).isEmpty)
    }

    /// The CLI does not always fill `structured_output`; a result string that
    /// is itself the JSON still counts.
    func testAResultStringCarryingTheJSONIsRead() {
        let stdout = "{\"is_error\":false,\"result\":" +
            "\"{\\\"readings\\\":[{\\\"id\\\":\\\"0\\\",\\\"plain\\\":\\\"plainly\\\"}]}\"}"
        let parsed = LensParser.parse(exitCode: 0, stdout: stdout, timedOut: false,
                                      sources: ["dense"])
        XCTAssertEqual(parsed.first?.plain, "plainly")
    }
}
