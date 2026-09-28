import XCTest
@testable import PRRadarCore

final class AutoReviewCommentTests: XCTestCase {

    let key = "acme/repo#12@2026-09-15T11:00:00Z"

    /// Lines 10–13 of Foo.swift are in the diff; nothing else is.
    let diff = DiffMap.parse(unifiedDiff: """
    diff --git a/Sources/Foo.swift b/Sources/Foo.swift
    --- a/Sources/Foo.swift
    +++ b/Sources/Foo.swift
    @@ -10,2 +10,4 @@
     context
    +added one
    +added two
     trailing
    """)

    private func finding(_ tier: FindingTier,
                         file: String? = "Sources/Foo.swift",
                         line: Int? = 11,
                         endLine: Int? = nil,
                         summary: String = "something",
                         detail: String? = nil,
                         recommendation: String = "do the other thing",
                         suggestion: String? = nil) -> Finding {
        Finding(tier: tier, file: file, line: line, endLine: endLine,
                summary: summary, detail: detail,
                recommendation: recommendation, suggestion: suggestion)
    }

    private func compose(_ findings: [Finding]) -> ComposedReview {
        AutoReviewComment.compose(AutoReviewFindings(findings: findings),
                                  skill: "/code-review", pingKey: key, diff: diff)
    }

    // MARK: - The summary

    /// The review is authored by the user's own account, so the body is the
    /// only thing that says where it came from.
    func testTheBodyOpensWithThePRRadarTitleAndNamesTheSkill() {
        let body = compose([finding(.mild)]).body
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(lines[0].hasPrefix(AutoReviewComment.markerPrefix))
        XCTAssertEqual(String(lines[1]), "**PR Radar** · automatic review · `/code-review`")
    }

    /// Arguments are configuration, not identity — the reader wants the skill's
    /// name, not the flags it was run with.
    func testTheTitleNamesTheSkillWithoutItsArguments() {
        let body = AutoReviewComment.body([], skill: "/code-review high", pingKey: key)
        XCTAssertTrue(body.contains("`/code-review`"))
        XCTAssertFalse(body.contains("high"))
    }

    func testPriorityAndMildAreBothListedInTheSummary() {
        let body = compose([finding(.priority, summary: "leaks"),
                            finding(.mild, line: 12, summary: "duplicated")]).body
        XCTAssertTrue(body.contains("### Priority"))
        XCTAssertTrue(body.contains("leaks"))
        XCTAssertTrue(body.contains("### Mild"))
        XCTAssertTrue(body.contains("duplicated"))
    }

    /// Posting a colleague a list of nits under your own name is how an
    /// automated reviewer gets muted.
    func testNitsAreOnlyEverACountAndNeverAThread() {
        let review = compose([finding(.nit), finding(.nit), finding(.mild, line: 12)])
        XCTAssertTrue(review.body.contains("_2 nits not raised._"))
        XCTAssertEqual(review.threads.count, 1)
    }

    func testOneNitIsSingular() {
        XCTAssertTrue(compose([finding(.nit)]).body.contains("_1 nit not raised._"))
    }

    func testACleanReviewSaysSoRatherThanBeingEmpty() {
        let body = compose([]).body
        XCTAssertTrue(body.contains("**Nothing to raise.**"))
        XCTAssertFalse(body.isEmpty)
    }

    func testTheFooterSaysThisIsNotAVerdict() {
        XCTAssertTrue(compose([]).body.contains("not a verdict"))
    }

    // MARK: - Inline threads

    func testEveryLocatableRaisedFindingBecomesAThread() {
        let review = compose([finding(.priority, line: 11), finding(.mild, line: 12)])
        XCTAssertEqual(review.threads.count, 2)
        XCTAssertEqual(review.threads.first?.path, "Sources/Foo.swift")
        XCTAssertTrue(review.unanchored.isEmpty)
    }

    func testAThreadCarriesTheTierTheSummaryAndTheRecommendation() {
        let review = compose([finding(.priority, summary: "retains self",
                                      recommendation: "capture it weakly")])
        let body = try! XCTUnwrap(review.threads.first?.body)
        XCTAssertTrue(body.contains("**Priority** — retains self"))
        XCTAssertTrue(body.contains("capture it weakly"))
    }

    /// A finding pointing outside the diff would have its thread rejected, and
    /// GitHub rejects the whole review when one thread is wrong — so it falls
    /// back to the body rather than costing every other finding.
    func testAFindingOutsideTheDiffFallsBackToTheBody() {
        let review = compose([finding(.priority, line: 900, summary: "far away")])
        XCTAssertTrue(review.threads.isEmpty)
        XCTAssertEqual(review.unanchored.count, 1)
        XCTAssertTrue(review.body.contains("far away"))
        XCTAssertTrue(review.body.contains("not in the diff"))
    }

    func testAFindingWithNoFileFallsBackToTheBody() {
        let review = compose([finding(.mild, file: nil, line: nil, summary: "overall")])
        XCTAssertTrue(review.threads.isEmpty)
        XCTAssertTrue(review.body.contains("overall"))
    }

    /// An off-by-a-line anchor is worth rescuing, but the comment has to admit
    /// it moved — otherwise it reads as a confident claim about the wrong line.
    func testASnappedThreadSaysThatItMoved() {
        let review = compose([finding(.mild, line: 14)])
        let thread = try! XCTUnwrap(review.threads.first)
        XCTAssertEqual(thread.line, 13)
        XCTAssertTrue(thread.body.contains("Reported at line 14"))
    }

    /// A multi-line thread whose start is outside the diff is rejected, and one
    /// rejection costs the whole review — so anchor the whole range or none.
    func testAMultiLineFindingIsAnchoredWholeOrNotAtAll() {
        let inside = compose([finding(.mild, line: 11, endLine: 12)])
        XCTAssertEqual(inside.threads.first?.startLine, 11)
        XCTAssertEqual(inside.threads.first?.line, 12)

        let straddling = compose([finding(.mild, line: 12, endLine: 40)])
        XCTAssertTrue(straddling.threads.isEmpty)
    }

    /// GitHub rejects a startLine equal to line, so a single-line thread must
    /// not send one.
    func testASingleLineThreadSendsNoStartLine() {
        XCTAssertNil(compose([finding(.mild, line: 11)]).threads.first?.startLine)
    }

    // MARK: - Suggestions

    func testASuggestionRendersWhenItsLineCountMatchesTheRange() {
        let review = compose([finding(.priority, line: 11, suggestion: "let x = 1")])
        let body = try! XCTUnwrap(review.threads.first?.body)
        XCTAssertTrue(body.contains("```suggestion\nlet x = 1\n```"))
    }

    func testAMultiLineSuggestionMatchesAMultiLineRange() {
        let review = compose([finding(.priority, line: 11, endLine: 12,
                                      suggestion: "let x = 1\nlet y = 2")])
        XCTAssertTrue(try! XCTUnwrap(review.threads.first?.body).contains("```suggestion"))
    }

    /// Apply replaces exactly the commented range, so a mismatched block
    /// silently deletes or duplicates code. A wrong Apply button is worse than
    /// no Apply button.
    func testAMismatchedSuggestionIsDroppedRatherThanRendered() {
        let review = compose([finding(.priority, line: 11,
                                      suggestion: "let x = 1\nlet y = 2")])
        let body = try! XCTUnwrap(review.threads.first?.body)
        XCTAssertFalse(body.contains("```suggestion"))
        XCTAssertTrue(body.contains("do the other thing"))
    }

    /// A suggestion that brings its own fence would break out of ours.
    func testASuggestionContainingAFenceIsDropped() {
        let review = compose([finding(.mild, line: 11, suggestion: "```\ncode")])
        XCTAssertFalse(try! XCTUnwrap(review.threads.first?.body).contains("```suggestion"))
    }

    /// A snapped thread points at a line the suggestion was not written for, so
    /// applying it would edit the wrong code.
    func testASnappedThreadNeverCarriesASuggestion() {
        let review = compose([finding(.mild, line: 14, suggestion: "let x = 1")])
        XCTAssertFalse(try! XCTUnwrap(review.threads.first?.body).contains("```suggestion"))
    }

    func testATrailingNewlineDoesNotCountAsAnExtraLine() {
        let review = compose([finding(.mild, line: 11, suggestion: "let x = 1\n")])
        XCTAssertTrue(try! XCTUnwrap(review.threads.first?.body).contains("```suggestion"))
    }

    // MARK: - The marker

    func testTheMarkerCarriesThePingKeyAndIsRecognised() {
        let body = compose([]).body
        XCTAssertTrue(AutoReviewComment.isOurs(body))
        XCTAssertEqual(AutoReviewComment.pingKey(in: body), key)
    }

    func testSomebodyElsesCommentIsNotRecognisedAsOurs() {
        XCTAssertFalse(AutoReviewComment.isOurs("Looks good to me!"))
        XCTAssertNil(AutoReviewComment.pingKey(in: "Looks good to me!"))
    }

    // MARK: - Request changes

    /// GitHub rejects REQUEST_CHANGES without a body, so this one can never be
    /// allowed to come out empty.
    func testTheRequestChangesBodyIsNeverEmpty() {
        let empty = AutoReviewComment.reviewBody(AutoReviewFindings(findings: []),
                                                 skill: "/code-review")
        XCTAssertFalse(empty.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

        let withNitsOnly = AutoReviewComment.reviewBody(
            AutoReviewFindings(findings: [finding(.nit)]), skill: "/code-review")
        XCTAssertFalse(withNitsOnly.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testTheRequestChangesBodyLeadsWithThePriorityFindings() {
        let body = AutoReviewComment.reviewBody(
            AutoReviewFindings(findings: [finding(.priority, summary: "leaks"),
                                          finding(.mild, summary: "noisy")]),
            skill: "/code-review")
        XCTAssertTrue(body.contains("leaks"))
        XCTAssertFalse(body.contains("noisy"))
    }

    // MARK: - Hostile content

    /// A finding quoting the code it found will be full of both.
    func testBackticksAndQuotesInAFindingSurviveIntact() {
        let review = compose([finding(.priority, summary: #"`foo("bar")` is wrong"#)])
        XCTAssertTrue(review.body.contains(#"`foo("bar")` is wrong"#))
        XCTAssertTrue(try! XCTUnwrap(review.threads.first?.body)
            .contains(#"`foo("bar")` is wrong"#))
    }

    func testAnOverlongBodyIsTruncatedWithANotice() {
        let long = String(repeating: "x", count: 80_000)
        let body = AutoReviewComment.body([finding(.priority, summary: long)],
                                          skill: "/code-review", pingKey: key)
        XCTAssertTrue(body.hasSuffix("_Truncated._"))
        XCTAssertLessThan(body.count, 61_000)
    }

    // MARK: - Superseding

    func testASupersededBodyKeepsTheMarkerSoItIsStillRecognisable() {
        let body = AutoReviewComment.supersededBody(pingKey: key)
        XCTAssertTrue(AutoReviewComment.isOurs(body))
        XCTAssertTrue(body.contains("Superseded"))
    }
}

// MARK: - Posting a review that was held

/// With automatic posting off, a review is composed on one launch and sent on
/// a button press later. What gets sent then has to be the whole review.
extension AutoReviewCommentTests {

    private func held(_ threads: [ReviewThread]) -> AutoReviewRecord {
        var record = AutoReviewRecord(status: .ready)
        record.body = "**PR Radar** · automatic review · `/code-review`"
        record.threads = threads
        return record
    }

    /// The regression this file exists to prevent recurring. The manual post
    /// path rebuilt the review by hand and passed no threads, so every
    /// manually-posted review went out as a bare summary — the findings the
    /// review had just spent minutes anchoring at `file:line` silently gone,
    /// and nothing failing to say so.
    func testAHeldReviewIsSentWithItsInlineThreads() {
        let threads = [ReviewThread(path: "Sources/Foo.swift", line: 12, body: "one"),
                       ReviewThread(path: "Sources/Bar.swift", line: 40, body: "two")]
        let review = try! XCTUnwrap(held(threads).heldReview)
        XCTAssertEqual(review.threads.count, 2)
        XCTAssertEqual(review.threads.map(\.path),
                       ["Sources/Foo.swift", "Sources/Bar.swift"])
        XCTAssertTrue(review.body.contains("PR Radar"))
    }

    /// A review whose findings genuinely had nowhere to anchor is still a
    /// review — the summary carries them instead.
    func testAHeldReviewWithNoAnchorableFindingsIsStillSendable() {
        XCTAssertNotNil(held([]).heldReview)
        XCTAssertEqual(held([]).heldReview?.threads.count, 0)
    }

    /// Nothing composed yet means nothing to send, rather than an empty review.
    func testARecordWithNoBodyHoldsNothing() {
        XCTAssertNil(AutoReviewRecord(status: .queued).heldReview)
        var blank = AutoReviewRecord(status: .ready)
        blank.body = ""
        XCTAssertNil(blank.heldReview)
    }

    /// The round trip through `UserDefaults` sits between composing and
    /// posting, so it is part of the path and has to preserve them too.
    func testThreadsSurviveStorageAndAreStillSentAfterwards() {
        var log = AutoReviewLog()
        log["k"] = held([ReviewThread(path: "Sources/Foo.swift", line: 12,
                                      startLine: 10, body: "```suggestion\nlet x = 1\n```")])
        let restored = AutoReviewLog.decoded(from: log.encoded())["k"]
        let review = try! XCTUnwrap(restored?.heldReview)
        XCTAssertEqual(review.threads.count, 1)
        XCTAssertEqual(review.threads.first?.startLine, 10)
        XCTAssertTrue(review.threads.first?.body.contains("```suggestion") == true)
    }
}

// MARK: - Choosing what gets posted

/// Curated mode: the review is drafted, then picked over. The rules about what
/// a *subset* adds up to are the whole of it.
extension AutoReviewCommentTests {

    private func prepared(_ findings: [Finding]) -> [PreparedFinding] {
        AutoReviewComment.prepare(AutoReviewFindings(findings: findings), diff: diff)
    }

    private func composed(_ prepared: [PreparedFinding]) -> ComposedReview {
        AutoReviewComment.compose(prepared, skill: "/code-review", pingKey: key)
    }

    // MARK: Preparing

    /// Priority and mild start ticked; nits do not. Posting a colleague a list
    /// of nits under your own name stays a deliberate act — but it is now one
    /// tick rather than a re-run, which is why they are anchored anyway.
    func testNitsArePreparedButNotTickedWhileTheRestAre() {
        let items = prepared([finding(.priority, line: 11),
                              finding(.mild, line: 12),
                              finding(.nit, line: 13)])
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items.filter(\.isSelected).map(\.tier), [.priority, .mild])
        // Anchored regardless, so opting one in needs no further work.
        XCTAssertTrue(try XCTUnwrap(items.last).isAnchored)
    }

    /// A finding with nowhere to hang is prepared too — the summary is its
    /// home, and the row says as much.
    func testAFindingOutsideTheDiffIsPreparedWithoutAnAnchor() {
        let items = prepared([finding(.priority, line: 900)])
        XCTAssertFalse(try XCTUnwrap(items.first).isAnchored)
        XCTAssertTrue(try XCTUnwrap(items.first).isSelected)
    }

    func testAPreparedFindingSaysWhereItWillAppear() {
        let items = prepared([finding(.mild, file: "Sources/Deep/Foo.swift", line: 11)])
        XCTAssertEqual(items.first?.location, "Foo.swift:11")
    }

    // MARK: Composing a subset

    /// The reason a finished review cannot just be filtered: the summary
    /// *lists* the findings, so unticking one has to remove it from the body as
    /// well as drop its thread. Filtering threads alone would post a summary
    /// describing comments that are not there.
    func testUntickingAFindingRemovesItFromTheBodyAndNotJustTheThreads() {
        var items = prepared([finding(.priority, line: 11, summary: "keep me"),
                              finding(.mild, line: 12, summary: "drop me")])
        items[1].isSelected = false

        let review = composed(items)
        XCTAssertEqual(review.threads.count, 1)
        XCTAssertTrue(review.body.contains("keep me"))
        XCTAssertFalse(review.body.contains("drop me"))
    }

    /// And what was left out is admitted rather than silently dropped — a
    /// review claiming the rest is all there was would be lying by omission.
    ///
    /// By tier, because "3 nits" and "3 priority" are very different things to
    /// have decided not to mention.
    func testWhatWasLeftOutIsNamedByTier() {
        var items = prepared([finding(.priority, line: 11), finding(.mild, line: 12)])
        items[1].isSelected = false
        XCTAssertTrue(composed(items).body.contains("_1 mild not raised._"),
                      composed(items).body)
    }

    func testSeveralOmittedTiersReadAsASentence() {
        var items = prepared([finding(.priority, line: 11),
                              finding(.mild, line: 12),
                              finding(.nit, line: 13)])
        items[0].isSelected = false
        items[1].isSelected = false
        XCTAssertTrue(composed(items).body.contains("_1 priority, 1 mild, and 1 nit not raised._"),
                      composed(items).body)
    }

    func testNothingOmittedSaysNothing() {
        let items = prepared([finding(.priority, line: 11)])
        XCTAssertFalse(composed(items).body.contains("not raised"))
    }

    func testTickingANitPostsItInline() {
        var items = prepared([finding(.nit, line: 11, summary: "spelling")])
        XCTAssertTrue(composed(items).threads.isEmpty)
        items[0].isSelected = true
        let review = composed(items)
        XCTAssertEqual(review.threads.count, 1)
        XCTAssertTrue(review.body.contains("### Nit"))
    }

    func testTickingNothingProducesAReviewWithNoThreads() {
        var items = prepared([finding(.priority, line: 11)])
        items[0].isSelected = false
        let review = composed(items)
        XCTAssertTrue(review.threads.isEmpty)
        XCTAssertTrue(review.body.contains("Nothing to raise."))
    }

    /// The default selection has to produce exactly what the automatic mode
    /// posts, or the two modes would quietly disagree about what a review is.
    func testTheDefaultSelectionMatchesWhatAutomaticModeWouldPost() {
        let all = AutoReviewFindings(findings: [finding(.priority, line: 11),
                                                finding(.mild, line: 12),
                                                finding(.nit, line: 13)])
        let automatic = AutoReviewComment.compose(all, skill: "/code-review",
                                                  pingKey: key, diff: diff)
        let curated = composed(AutoReviewComment.prepare(all, diff: diff))
        XCTAssertEqual(automatic.body, curated.body)
        XCTAssertEqual(automatic.threads, curated.threads)
    }

    // MARK: Surviving the wait

    /// A curated review sits in the log while somebody thinks about it, and a
    /// half-picked-over review has to survive a relaunch — losing the ticks
    /// would mean reading nine findings again.
    func testASelectionSurvivesStorage() {
        var items = prepared([finding(.priority, line: 11), finding(.mild, line: 12)])
        items[1].isSelected = false

        var record = AutoReviewRecord(status: .ready)
        record.body = "b"
        record.prepared = items
        var log = AutoReviewLog()
        log["k"] = record

        let restored = try! XCTUnwrap(AutoReviewLog.decoded(from: log.encoded())["k"])
        XCTAssertEqual(restored.selection.chosen, 1)
        XCTAssertEqual(restored.selection.total, 2)
        XCTAssertEqual(restored.findings(in: .mild).first?.isSelected, false)
        XCTAssertTrue(restored.isAwaitingSelection)
    }

    /// A record from before curated mode has no prepared findings, and must
    /// not look like a review waiting to be picked over.
    func testARecordWithNoPreparedFindingsIsNotAwaitingSelection() {
        var record = AutoReviewRecord(status: .ready)
        record.body = "b"
        XCTAssertFalse(record.isAwaitingSelection)
    }
    // MARK: - Saying how many are actually inline

    private func mild(_ summary: String, file: String? = "a.swift",
                      line: Int? = 10) -> Finding {
        Finding(tier: .mild, file: file, line: line, endLine: nil,
                summary: summary, detail: nil, recommendation: "do it", suggestion: nil)
    }

    func testEverythingAnchoredSaysEachIsInline() {
        let text = AutoReviewComment.tally([mild("one"), mild("two")], unanchored: 0)
        XCTAssertTrue(text.contains("2 mild"), text)
        XCTAssertTrue(text.contains("Each is commented inline below."), text)
    }

    /// The bug as reported: two findings ticked, one anchorable, and the review
    /// announced that both were inline — then contradicted itself on the
    /// finding's own row. Nothing was lost; the summary was lying about it.
    func testAMixSaysHowManyAreInlineAndHowManyAreNot() {
        let text = AutoReviewComment.tally([mild("one"), mild("two")], unanchored: 1)
        XCTAssertFalse(text.contains("Each is commented inline below."),
                       "claimed every finding was inline when one was not: \(text)")
        XCTAssertTrue(text.contains("1 commented inline below"), text)
        XCTAssertTrue(text.contains("1 not in the diff"), text)
    }

    func testNothingAnchoredSaysSoRatherThanPromisingInlineComments() {
        let none = AutoReviewComment.tally([mild("one"), mild("two")], unanchored: 2)
        XCTAssertFalse(none.contains("inline below"), none)
        XCTAssertTrue(none.contains("None are in this pull request's diff"), none)

        let one = AutoReviewComment.tally([mild("only")], unanchored: 1)
        XCTAssertTrue(one.contains("It is not in this pull request's diff"), one)
        XCTAssertFalse(one.contains("It is in this pull"), "reads as the opposite: \(one)")
    }

    /// Whatever the caller passes, the sentence has to describe the findings it
    /// was actually given.
    func testTheCountIsClampedToTheFindingsItDescribes() {
        XCTAssertTrue(AutoReviewComment.tally([mild("one")], unanchored: 9)
            .contains("It is not in this pull request's diff"))
        XCTAssertTrue(AutoReviewComment.tally([mild("one")], unanchored: -3)
            .contains("Each is commented inline below."))
    }

    func testAnEmptyReviewStillSaysNothingToRaise() {
        XCTAssertEqual(AutoReviewComment.tally([], unanchored: 0), "**Nothing to raise.**")
    }

    /// End to end through `body`, which is what actually reaches the pull
    /// request — the unit under report was the composed review, not the helper.
    func testTheComposedBodyAgreesWithItsOwnFindingRows() {
        let anchored = mild("anchored one")
        let stranded = mild("stranded one", file: "untouched.md", line: 102)
        let body = AutoReviewComment.body([anchored, stranded],
                                          skill: "/judge",
                                          pingKey: "acme/repo#1@t",
                                          unanchored: [stranded])

        XCTAssertFalse(body.contains("Each is commented inline below."), body)
        XCTAssertTrue(body.contains("1 commented inline below"), body)
        // The row-level note that used to contradict the opening line.
        XCTAssertTrue(body.contains("stranded one _(not in the diff; no inline comment)_"),
                      body)
    }

}
