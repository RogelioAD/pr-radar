import XCTest
@testable import PRRadarCore

/// Showing a finding the code it is about. The diff exists exactly once — in
/// the worktree the review ran in, which is deleted the moment the run ends —
/// so everything here is about what was kept while it still could be.
final class DiffExcerptTests: XCTestCase {

    private let diff = """
    diff --git a/src/lib.rs b/src/lib.rs
    --- a/src/lib.rs
    +++ b/src/lib.rs
    @@ -204,6 +204,9 @@ fn resolve(path: &str) -> Option<Route> {
         let mut parts = path.split('/');
         let seg = parts.next()?;
    -    if seg.is_empty() {
    +    if RESERVED.contains(seg) {
    +        return None;
    +    }
    +    if seg.is_empty() {
             return None;
         }
         Route::from_slug(seg)
    """

    private var map: DiffMap { DiffMap.parse(unifiedDiff: diff) }

    // MARK: Keeping the text

    func testTheParserKeepsTheLineText() {
        let hunk = try! XCTUnwrap(map.hunks["src/lib.rs"]?.first)
        XCTAssertFalse(hunk.rendered.isEmpty)
        XCTAssertTrue(hunk.rendered.contains { $0.text.contains("RESERVED.contains") })
    }

    /// A removal has no right-side number, which is the same reason it can
    /// carry no comment.
    func testARemovedLineIsKeptButUnnumbered() {
        let hunk = try! XCTUnwrap(map.hunks["src/lib.rs"]?.first)
        let removed = try! XCTUnwrap(hunk.rendered.first { $0.kind == .removed })
        XCTAssertNil(removed.number)
        XCTAssertTrue(removed.text.contains("seg.is_empty"))
    }

    /// The numbering the excerpt shows is the numbering the anchor uses, or the
    /// code would be captioned with somebody else's line numbers.
    func testTheNumbersAgreeWithWhatIsCommentable() {
        for line in map.hunks["src/lib.rs"]!.first!.rendered {
            guard let number = line.number else { continue }
            XCTAssertTrue(map.isCommentable(path: "src/lib.rs", line: number))
        }
    }

    /// The text is kept without its diff marker: the sign is drawn from `kind`,
    /// and a `+` baked into the string would show up twice.
    func testTheMarkerIsNotPartOfTheText() {
        let hunk = try! XCTUnwrap(map.hunks["src/lib.rs"]?.first)
        for line in hunk.rendered {
            XCTAssertFalse(line.text.hasPrefix("+"), line.text)
            XCTAssertFalse(line.text.hasPrefix("-"), line.text)
        }
    }

    // MARK: Slicing one

    func testAnExcerptIsCentredOnTheCommentedLine() {
        let excerpt = try! XCTUnwrap(map.excerpt(path: "src/lib.rs", line: 207, context: 2))
        XCTAssertEqual(excerpt.path, "src/lib.rs")
        XCTAssertEqual(excerpt.focus, 207)
        XCTAssertTrue(excerpt.lines.contains { $0.number == 207 })
    }

    /// Counted in rows, not in line numbers. A removal has no number, so a
    /// window measured in numbers would drop exactly the line that explains
    /// what the change replaced.
    func testTheWindowCarriesTheRemovalThatExplainsTheChange() {
        let excerpt = try! XCTUnwrap(map.excerpt(path: "src/lib.rs", line: 207, context: 2))
        XCTAssertTrue(excerpt.lines.contains { $0.kind == .removed })
    }

    func testTheWindowIsBoundedByTheHunk() {
        let excerpt = try! XCTUnwrap(map.excerpt(path: "src/lib.rs", line: 207, context: 99))
        XCTAssertEqual(excerpt.lines.count, map.hunks["src/lib.rs"]!.first!.rendered.count)
    }

    /// A multi-line finding shows its whole range, not the tail of it with
    /// three lines of lead-in.
    func testAMultiLineFindingStartsAtItsFirstLine() {
        let excerpt = try! XCTUnwrap(
            map.excerpt(path: "src/lib.rs", line: 209, startLine: 207, context: 0))
        XCTAssertTrue(excerpt.lines.contains { $0.number == 207 })
        XCTAssertTrue(excerpt.lines.contains { $0.number == 209 })
        XCTAssertEqual(excerpt.focusStart, 207)
    }

    func testEveryLineOfTheCommentedRangeIsMarkedAsFocused() {
        let excerpt = try! XCTUnwrap(
            map.excerpt(path: "src/lib.rs", line: 209, startLine: 207))
        XCTAssertTrue(excerpt.isFocused(207))
        XCTAssertTrue(excerpt.isFocused(209))
        XCTAssertFalse(excerpt.isFocused(205))
        // A removal has no number and is never the line under discussion.
        XCTAssertFalse(excerpt.isFocused(nil))
    }

    /// nil is the same condition as "not commentable", so a finding with no
    /// excerpt is a finding with no inline thread either — the two stay
    /// consistent without having to be kept in step.
    func testALineOutsideTheDiffHasNoExcerpt() {
        XCTAssertNil(map.excerpt(path: "src/lib.rs", line: 4_000))
        XCTAssertNil(map.excerpt(path: "nowhere.rs", line: 207))
    }

    /// A map built by hand in a test carries no text, and must not pretend to.
    func testAMapWithNoTextOffersNoExcerpt() {
        let bare = DiffMap(hunks: ["a.swift": [.init(start: 1, end: 3, lines: [1, 2, 3])]])
        XCTAssertTrue(bare.isCommentable(path: "a.swift", line: 2))
        XCTAssertNil(bare.excerpt(path: "a.swift", line: 2))
    }

    // MARK: Surviving the worktree

    /// The whole point: the checkout is deleted when the review ends, so the
    /// code has to come back off the record with the ticks.
    func testAnExcerptSurvivesStorage() {
        let findings = AutoReviewFindings(findings: [
            Finding(tier: .mild, file: "src/lib.rs", line: 207, endLine: nil,
                    summary: "s", recommendation: "r", suggestion: nil)
        ])
        var record = AutoReviewRecord(status: .ready)
        record.body = "b"
        record.prepared = AutoReviewComment.prepare(findings, diff: map)

        var log = AutoReviewLog()
        log["k"] = record
        let restored = try! XCTUnwrap(AutoReviewLog.decoded(from: log.encoded())["k"])

        let excerpt = try! XCTUnwrap(restored.prepared.first?.excerpt)
        XCTAssertEqual(excerpt.focus, 207)
        XCTAssertTrue(excerpt.lines.contains { $0.text.contains("RESERVED.contains") })
    }

    /// An unanchored finding is unanchored *because* its line is not in the
    /// diff. There is nothing to show and no honest way to invent it.
    func testAnUnanchoredFindingCarriesNoCode() {
        let findings = AutoReviewFindings(findings: [
            Finding(tier: .mild, file: "docs/spec.md", line: 102, endLine: nil,
                    summary: "s", recommendation: "r", suggestion: nil)
        ])
        let prepared = AutoReviewComment.prepare(findings, diff: map)
        XCTAssertFalse(prepared[0].isAnchored)
        XCTAssertNil(prepared[0].excerpt)
    }

    /// A record written before excerpts were kept still decodes; those rows
    /// simply have no code to open.
    func testARecordFromBeforeExcerptsStillDecodes() {
        let json = """
        {"records":{"k":{"status":"ready","attempts":1,"body":"b","prepared":
        [{"finding":{"tier":"mild","summary":"s","recommendation":"r"},
          "isSelected":true}]}}}
        """
        let log = AutoReviewLog.decoded(from: Data(json.utf8))
        let record = try! XCTUnwrap(log["k"])
        XCTAssertEqual(record.prepared.count, 1)
        XCTAssertNil(record.prepared[0].excerpt)
    }
}
