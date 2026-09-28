import XCTest
@testable import PRRadarCore

/// When the drawer is twice its usual width. Code cannot be reflowed into a
/// 440pt column without ceasing to look like code, so a findings list earns
/// the space — and gives it straight back, which is the only reason a doubling
/// this large is affordable.
final class DrawerWidthTests: XCTestCase {

    private let open: Set<String> = ["acme/app#12@2026-09-28T18:34:11Z"]
    /// Rows drawing a findings list right now — not merely rows on screen.
    private let visible = ["acme/app#12@2026-09-28T18:34:11Z",
                           "acme/app#13@2026-09-28T18:34:11Z"]

    func testAnOpenFindingsListWidensTheDrawer() {
        XCTAssertTrue(DrawerWidth.isWide(room: nil,
                                         openKeys: open, expandable: visible))
    }

    func testTheOrdinaryListStaysNarrow() {
        XCTAssertFalse(DrawerWidth.isWide(room: nil,
                                          openKeys: [], expandable: visible))
    }

    /// Closing the list is one of the ways out.
    func testClosingTheListGivesTheWidthBack() {
        var keys = open
        keys.removeAll()
        XCTAssertFalse(DrawerWidth.isWide(room: nil,
                                          openKeys: keys, expandable: visible))
    }

    /// Changing tab is another — the caller asks with the other tab's keys,
    /// and nothing open there is nothing to be wide for.
    func testTheOtherTabIsNarrowWhenNothingIsOpenOnIt() {
        XCTAssertFalse(DrawerWidth.isWide(room: nil, openKeys: [], expandable: []))
    }

    /// Both tabs have something worth the room: a findings list on one, an
    /// unresolved review thread on the other. The rule does not care which —
    /// the caller decides whose keys it is asking about.
    func testTheOtherTabCanEarnTheWidthToo() {
        XCTAssertTrue(DrawerWidth.isWide(room: nil,
                                         openKeys: ["acme/app#7"],
                                         expandable: ["acme/app#7"]))
    }

    /// And walking into a room is the third: a room replaces the whole list.
    func testEveryRoomIsNarrow() {
        for room in DrawerRoom.allCases {
            XCTAssertFalse(DrawerWidth.isWide(room: room,
                                              openKeys: open, expandable: visible),
                           "\(room)")
        }
    }

    /// Coming back finds it as it was left, rather than having been forgotten
    /// on the way out — the tab is a gate on the width, not a reason to close
    /// what was open.
    func testComingBackToTheTabIsWideAgain() {
        XCTAssertFalse(DrawerWidth.isWide(room: nil, openKeys: open, expandable: []))
        XCTAssertTrue(DrawerWidth.isWide(room: nil, openKeys: open, expandable: visible))
    }

    /// The case that would otherwise wedge it open: a pull request that was
    /// reviewed and left the list takes its findings with it, and the key it
    /// left behind must not hold the drawer at double width over a list with
    /// nothing open in it.
    func testAKeyLeftBehindByAVanishedRowDoesNotHoldItOpen() {
        XCTAssertFalse(DrawerWidth.isWide(room: nil,
                                          openKeys: open,
                                          expandable: ["acme/app#99@2026-09-28T18:34:11Z"]))
    }

    /// The subtler one, and the one that actually showed up: the row does not
    /// have to *leave* for its findings to. Press a decision and it stays put
    /// saying `done` while the list retires with the record — still on screen,
    /// no longer awaiting anything, and not a reason to be wide.
    func testARowStillOnScreenButNoLongerPickingOverFindingsIsNarrow() {
        XCTAssertFalse(DrawerWidth.isWide(room: nil,
                                          openKeys: open,
                                          expandable: []))
    }

    func testAnEmptyListIsNarrowWhateverIsRemembered() {
        XCTAssertFalse(DrawerWidth.isWide(room: nil,
                                          openKeys: open, expandable: []))
    }

    /// Two open at once is the ordinary case, not an edge one: comparing two
    /// findings in the same file is why the set is a set.
    func testTwoOpenAtOnceIsStillWide() {
        XCTAssertTrue(DrawerWidth.isWide(room: nil,
                                         openKeys: Set(visible), expandable: visible))
    }
}
