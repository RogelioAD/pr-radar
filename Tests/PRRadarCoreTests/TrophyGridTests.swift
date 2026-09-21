import XCTest
@testable import PRRadarCore

/// The shelf's layout and its bookkeeping. Both are what the drawer sizes
/// itself from, so both are rules rather than appearances.
final class TrophyGridTests: XCTestCase {

    // MARK: - The roster

    /// Every id has exactly one trophy, and no trophy is declared twice.
    /// `Trophy.named` traps rather than returning nil, so this is what keeps
    /// that trap from ever firing in the app.
    func testEveryIDHasExactlyOneTrophy() {
        XCTAssertEqual(Trophy.all.count, TrophyID.allCases.count)
        XCTAssertEqual(Set(Trophy.all.map(\.id)).count, Trophy.all.count)
        for id in TrophyID.allCases {
            XCTAssertEqual(Trophy.named(id).id, id)
        }
    }

    /// The banner draws a name in a 5x7 font at up to 4x. A long one does not
    /// break anything, but it makes a banner wide enough to stop reading as
    /// an aside — which is the whole register these are pitched at.
    func testNamesStayShortEnoughForTheBanner() {
        for trophy in Trophy.all {
            XCTAssertLessThanOrEqual(trophy.name.count, 16, trophy.name)
        }
    }

    /// The hint is the only explanation a trophy ever gets, so an empty one
    /// is a trophy nobody can work out.
    func testEveryTrophyExplainsItself() {
        for trophy in Trophy.all {
            XCTAssertFalse(trophy.hint.isEmpty, "\(trophy.id)")
            XCTAssertTrue(trophy.hint.hasSuffix("."), "\(trophy.id) is not a sentence")
        }
    }

    /// Hidden ones sit at the end, so the run of question marks reads as one
    /// block rather than as gaps in an otherwise full shelf.
    func testHiddenTrophiesComeLast() {
        let firstHidden = Trophy.all.firstIndex(where: \.isHidden)
        let lastVisible = Trophy.all.lastIndex(where: { !$0.isHidden })
        XCTAssertNotNil(firstHidden)
        XCTAssertNotNil(lastVisible)
        XCTAssertGreaterThan(firstHidden ?? 0, lastVisible ?? 0)
    }

    // MARK: - Rows

    func testTheRosterFillsWholeRows() {
        let rows = TrophyGrid.rows()
        XCTAssertEqual(rows.count, 6)
        for row in rows {
            XCTAssertEqual(row.count, TrophyGrid.columns)
        }
    }

    func testEveryTrophyAppearsExactlyOnce() {
        let laid = TrophyGrid.rows().flatMap { $0 }.map(\.id)
        XCTAssertEqual(laid, Trophy.all.map(\.id))
    }

    /// A short final row is a legal stop, not something to pad out: the
    /// drawer snaps to rows, and inventing a trophy to square the grid would
    /// be inventing a trophy.
    func testAShortFinalRowIsKeptShort() {
        let rows = TrophyGrid.rows(Array(Trophy.all.prefix(7)))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].count, 5)
        XCTAssertEqual(rows[1].count, 2)
    }

    func testRowIDsAreStableAndDistinct() {
        let ids = (0..<TrophyGrid.rowCount()).map(TrophyGrid.rowID)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(TrophyGrid.rowID(3), TrophyGrid.rowID(3))
    }

    // MARK: - Progress

    func testProgressCountsWhatIsEarned() {
        XCTAssertTrue(TrophyGrid.progress(unlocked: []).hasPrefix("0 / 30"))
        XCTAssertTrue(TrophyGrid.progress(unlocked: [.swamped, .juggler])
            .hasPrefix("2 / 30"))
    }

    /// The hidden count is reported as *found*, never as outstanding — saying
    /// how many are left is most of what would stop them being hidden.
    func testProgressNeverSaysHowManyHiddenAreLeft() {
        let text = TrophyGrid.progress(unlocked: [.homeTeam])
        XCTAssertTrue(text.contains("1 hidden found"), text)
        XCTAssertFalse(text.contains("/ \(Trophy.hidden.count)"), text)
    }

    func testProgressSaysNothingAboutHiddenBeforeAnyAreFound() {
        XCTAssertFalse(TrophyGrid.progress(unlocked: [.swamped]).contains("hidden"))
    }

    func testProgressCallsItWhenEveryHiddenOneIsFound() {
        let all = Set(Trophy.hidden.map(\.id))
        XCTAssertTrue(TrophyGrid.progress(unlocked: all).contains("every hidden one"))
    }

    // MARK: - What a locked trophy gives away

    func testAHiddenTrophyKeepsItsNameAndHintBack() {
        let hidden = Trophy.named(.palindrome)
        XCTAssertEqual(hidden.name(unlocked: false), Trophy.redacted)
        XCTAssertEqual(hidden.tooltip(unlocked: false), Trophy.redacted)
        XCTAssertEqual(hidden.art(unlocked: false).cells, Trophy.mystery.cells)
    }

    func testAHiddenTrophyGivesEverythingUpOnceFound() {
        let hidden = Trophy.named(.palindrome)
        XCTAssertEqual(hidden.name(unlocked: true), "Palindrome")
        XCTAssertTrue(hidden.tooltip(unlocked: true).contains("backwards"))
        XCTAssertNotEqual(hidden.art(unlocked: true).cells, Trophy.mystery.cells)
    }

    /// A locked *visible* trophy still says what it wants — that is the whole
    /// reason to hover one.
    func testALockedVisibleTrophyStillExplainsItself() {
        let swamped = Trophy.named(.swamped)
        XCTAssertEqual(swamped.name(unlocked: false), "Swamped")
        XCTAssertTrue(swamped.tooltip(unlocked: false).contains("ten reviews"))
        XCTAssertEqual(swamped.art(unlocked: false).cells, swamped.art.cells)
    }
}
