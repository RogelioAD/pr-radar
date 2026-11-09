import XCTest
@testable import PRRadarCore

final class AwayScreenTests: XCTestCase {

    private func job(_ label: String, _ elapsed: TimeInterval) -> AwayScreen.Job {
        AwayScreen.Job(label: label, elapsed: elapsed)
    }

    // MARK: - The headline, which is read first and often only

    func testNothingRunningSaysSo() {
        let status = AwayScreen.status(running: [], queued: 0)
        XCTAssertEqual(status.headline, "Nothing running")
        XCTAssertTrue(status.lines.isEmpty)
        XCTAssertFalse(status.isWorking)
    }

    /// A queue with nothing started yet is still work in hand. Reported as
    /// *working* so the screen does not dim and read, from the doorway, as
    /// finished.
    func testAQueueOnItsOwnIsTheHeadlineAndCountsAsWorking() {
        let status = AwayScreen.status(running: [], queued: 3)
        XCTAssertEqual(status.headline, "3 waiting to start")
        XCTAssertTrue(status.isWorking)
        // Not repeated underneath: it has already been said in the line that
        // gets read.
        XCTAssertFalse(status.lines.contains("3 queued"))
    }

    func testOnePullRequestIsNotPluralised() {
        XCTAssertEqual(AwayScreen.status(running: [job("a#1", 5)], queued: 0).headline,
                       "Reviewing 1 pull request")
        XCTAssertEqual(AwayScreen.status(running: [job("a#1", 5), job("b#2", 5)],
                                         queued: 0).headline,
                       "Reviewing 2 pull requests")
    }

    // MARK: - Which runs get named

    /// Longest first, because the question behind a glance from the doorway is
    /// *when will this be done*, and the oldest run is what is holding it up.
    func testLongestRunningIsNamedFirst() {
        let status = AwayScreen.status(
            running: [job("short#1", 10), job("long#2", 600), job("middle#3", 120)],
            queued: 0)
        XCTAssertEqual(status.lines, ["long#2 · 10:00", "middle#3 · 2:00", "short#1 · 0:10"])
    }

    /// Past three, the rest become a count. A list long enough to need scanning
    /// has stopped answering the one question this screen is read for.
    func testBeyondThreeTheRestAreCounted() {
        let running = (1...6).map { job("repo#\($0)", TimeInterval($0) * 60) }
        let status = AwayScreen.status(running: running, queued: 0)
        XCTAssertEqual(status.lines.count, AwayScreen.maxNamed + 1)
        XCTAssertEqual(status.lines.last, "+3 more")
        // Still the longest three that got named.
        XCTAssertEqual(status.lines.first, "repo#6 · 6:00")
    }

    /// Equal durations keep the order they arrived in, so a one-second redraw
    /// does not reshuffle two runs that started together — motion on this
    /// screen draws exactly the attention it exists to deflect.
    func testEqualDurationsDoNotReshuffleBetweenRedraws() {
        let running = [job("a#1", 60), job("b#2", 60), job("c#3", 60)]
        let first = AwayScreen.status(running: running, queued: 0).lines
        let again = AwayScreen.status(running: running, queued: 0).lines
        XCTAssertEqual(first, again)
        XCTAssertEqual(first, ["a#1 · 1:00", "b#2 · 1:00", "c#3 · 1:00"])
    }

    func testQueueIsAFootnoteOnceSomethingIsRunning() {
        let status = AwayScreen.status(running: [job("a#1", 30)], queued: 2)
        XCTAssertEqual(status.lines, ["a#1 · 0:30", "2 queued"])
    }

    /// Seconds advance, which is the point of showing a stopwatch at all: a
    /// number that only moved once a minute would not look like it was
    /// measuring anything.
    func testElapsedIsShownToTheSecond() {
        XCTAssertEqual(AwayScreen.status(running: [job("a#1", 7)], queued: 0).lines,
                       ["a#1 · 0:07"])
        XCTAssertEqual(AwayScreen.status(running: [job("a#1", 3_753)], queued: 0).lines,
                       ["a#1 · 1:02:33"])
    }

    /// A review whose row has since gone is still named by its key. An
    /// unexplained stopwatch beats a run that quietly stopped being mentioned
    /// on the one screen built to say whether work is still going.
    func testAnUnlabelledRunIsStillNamed() {
        let status = AwayScreen.status(running: [job("elevation/app#418:2026-01-01", 45)],
                                       queued: 0)
        XCTAssertEqual(status.lines, ["elevation/app#418:2026-01-01 · 0:45"])
    }

    // MARK: - Fitting whichever display it landed on

    /// Every display anyone reviews on. Side by side is the layout the screen
    /// was designed around, and these must not lose it.
    func testAnOrdinaryDisplayKeepsTheTwoColumnsSideBySide() {
        let widths: [CGFloat] = [
            2_560,   // the ultrawide this was found on
            1_728,   // 16" MacBook Pro, default scaling
            1_512,   // 14" MacBook Pro
            1_440,   // 13" at the common scaled size
            1_280,   // an old secondary, and the floor worth calling roomy
        ]
        for width in widths {
            XCTAssertEqual(AwayScreen.columns(forWidth: width),
                           .sideBySide(width: AwayScreen.columnWidth),
                           "\(width) should still fit two columns")
        }
    }

    /// A portrait monitor is the common case here, and the one that was
    /// clipped: two 480pt columns and their gap do not fit across 1080pt with
    /// anything left for a margin.
    func testANarrowDisplayStacksRatherThanClips() {
        guard case .stacked(let width) = AwayScreen.columns(forWidth: 1_080) else {
            return XCTFail("a 1080pt-wide display cannot hold two columns")
        }
        XCTAssertEqual(width, AwayScreen.columnWidth)
    }

    /// A stacked column keeps its full width for as long as one fits — 480pt
    /// has room to spare on anything 560pt across.
    func testAStackedColumnKeepsItsWidthWhileItFits() {
        guard case .stacked(let width) = AwayScreen.columns(forWidth: 800) else {
            return XCTFail("expected a stack")
        }
        XCTAssertEqual(width, AwayScreen.columnWidth)
    }

    /// Below that it gives up the fixed width rather than the margin, because
    /// a column ending at the bezel reads as cut off whether or not it is.
    func testAVerySmallDisplayNarrowsTheColumn() {
        guard case .stacked(let width) = AwayScreen.columns(forWidth: 500) else {
            return XCTFail("expected a stack")
        }
        XCTAssertEqual(width, 500 - AwayScreen.sideMargin * 2)
        XCTAssertLessThan(width, AwayScreen.columnWidth)
    }

    /// Never narrower than a `repo#1234 · 1:02:33` line survives at. Past that
    /// the screen has stopped answering its question and should say so at a
    /// readable size rather than shrink politely.
    func testTheColumnHasAFloor() {
        guard case .stacked(let width) = AwayScreen.columns(forWidth: 200) else {
            return XCTFail("expected a stack")
        }
        XCTAssertEqual(width, 240)
    }

    /// The boundary, written down so that changing a constant has to be
    /// deliberate: exactly enough room is enough.
    func testTheBoundaryIsExact() {
        let both = AwayScreen.columnWidth * 2 + AwayScreen.columnGap
            + AwayScreen.sideMargin * 2
        XCTAssertEqual(AwayScreen.columns(forWidth: both),
                       .sideBySide(width: AwayScreen.columnWidth))
        guard case .stacked = AwayScreen.columns(forWidth: both - 1) else {
            return XCTFail("one point short is short")
        }
    }

    /// The title block keeps its distance from the top on anything tall
    /// enough, and gives ground only on a screen that cannot spare it.
    func testTheHeaderKeepsItsAnchorOnATallScreenAndYieldsOnAShortOne() {
        XCTAssertEqual(AwayScreen.headerTop(forHeight: 1_440), 96)
        XCTAssertEqual(AwayScreen.headerTop(forHeight: 900), 96)
        XCTAssertLessThan(AwayScreen.headerTop(forHeight: 768), 96)
        // Still clear of the top edge, however short the screen.
        XCTAssertGreaterThanOrEqual(AwayScreen.headerTop(forHeight: 200), 24)
    }
}
