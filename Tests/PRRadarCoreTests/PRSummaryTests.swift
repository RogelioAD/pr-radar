import XCTest
@testable import PRRadarCore

/// The one line of a description worth putting on a row.
final class PRSummaryTests: XCTestCase {

    func testTakesTheFirstRealLine() {
        XCTAssertEqual(PRSummary.firstLine(of: "Fixes the pager jumping on load."),
                       "Fixes the pager jumping on load.")
    }

    func testSkipsBlankLines() {
        XCTAssertEqual(PRSummary.firstLine(of: "\n\n  \nThe actual sentence."),
                       "The actual sentence.")
    }

    /// Half the descriptions in a repo with a template start `## Summary`, and
    /// that is the template talking rather than the author.
    func testSkipsHeadings() {
        XCTAssertEqual(PRSummary.firstLine(of: "## Summary\n\nWhat it does."),
                       "What it does.")
        XCTAssertEqual(PRSummary.firstLine(of: "# Title\n### Sub\nReal text"),
                       "Real text")
    }

    func testSkipsRules() {
        XCTAssertEqual(PRSummary.firstLine(of: "---\n***\n___\nContent"), "Content")
    }

    /// The markers a template leaves behind when nobody filled them in.
    func testSkipsEmptyListItemsAndCheckboxes() {
        XCTAssertEqual(PRSummary.firstLine(of: "- [ ]\n-\n*  \nSomething real"),
                       "Something real")
    }

    func testKeepsAFilledCheckbox() {
        XCTAssertEqual(PRSummary.firstLine(of: "- [x] Tested on device"),
                       "- [x] Tested on device")
    }

    /// HTML comments are where templates keep their instructions, and the
    /// instructions are never the summary.
    func testSkipsASingleLineComment() {
        XCTAssertEqual(PRSummary.firstLine(of: "<!-- describe your change -->\nThe change."),
                       "The change.")
    }

    func testSkipsAMultiLineComment() {
        let body = """
        <!--
        Please fill in the sections below.
        Do not delete this template.
        -->
        Adds the retry.
        """
        XCTAssertEqual(PRSummary.firstLine(of: body), "Adds the retry.")
    }

    func testTakesTextAroundAnInlineComment() {
        XCTAssertEqual(PRSummary.firstLine(of: "Real text <!-- a note --> continues"),
                       "Real text  continues")
    }

    func testAnUnclosedCommentSwallowsTheRest() {
        XCTAssertNil(PRSummary.firstLine(of: "<!-- never closed\nhidden\nalso hidden"))
    }

    func testNothingToSay() {
        XCTAssertNil(PRSummary.firstLine(of: nil))
        XCTAssertNil(PRSummary.firstLine(of: ""))
        XCTAssertNil(PRSummary.firstLine(of: "## Summary\n\n---\n- [ ]\n"))
    }

    // MARK: - Headings that do not look like headings

    /// The form every template written in a text editor rather than a browser
    /// tends to use: the marker is on the *next* line.
    func testSkipsSetextHeadings() {
        XCTAssertEqual(PRSummary.firstLine(of: "What\n----\nIt does the thing."),
                       "It does the thing.")
        XCTAssertEqual(PRSummary.firstLine(of: "Title\n=====\nReal text"),
                       "Real text")
    }

    /// A line underlined by a *sentence* is not a heading — the lookahead has
    /// to be an underline and nothing else.
    func testADashedListIsNotAnUnderline() {
        XCTAssertEqual(PRSummary.firstLine(of: "Fixes the crash\n- and the leak"),
                       "Fixes the crash")
    }

    /// A whole line in bold is a heading wearing a disguise.
    func testUnwrapsAWhollyEmphasisedLine() {
        XCTAssertEqual(PRSummary.firstLine(of: "**Summary of changes**"),
                       "Summary of changes")
        XCTAssertEqual(PRSummary.firstLine(of: "_draft, do not review_"),
                       "draft, do not review")
    }

    /// Emphasis inside a sentence is left exactly as written. Stripping it is
    /// how `a **hard** no` becomes a different sentence in a flatter voice.
    func testLeavesEmphasisInsideASentence() {
        XCTAssertEqual(PRSummary.firstLine(of: "This is a **hard** no"),
                       "This is a **hard** no")
        XCTAssertEqual(PRSummary.firstLine(of: "**a** and **b**"),
                       "**a** and **b**")
    }

    func testStripsBlockQuoteMarkers() {
        XCTAssertEqual(PRSummary.firstLine(of: "> Note: needs the API deploy first"),
                       "Note: needs the API deploy first")
    }

    /// Bounded, so a four-kilobyte template cannot ride around in memory on
    /// thirty rows.
    func testIsTruncated() {
        let long = String(repeating: "a", count: 2_000)
        XCTAssertEqual(PRSummary.firstLine(of: long)?.count, PRSummary.limit)
    }
}
