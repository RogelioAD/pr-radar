import XCTest
@testable import PRRadarCore

/// What a key press means, and where the selection goes.
final class KeyboardTests: XCTestCase {

    func key(_ characters: String, _ code: UInt16 = 0,
             cmd: Bool = false, opt: Bool = false, ctrl: Bool = false) -> KeyCommand? {
        KeyCommand.from(characters: characters, keyCode: code,
                        hasCommand: cmd, hasOption: opt, hasControl: ctrl)
    }

    // MARK: - The mapping

    func testArrowsAndTheirVimTwins() {
        XCTAssertEqual(key("", 125), .moveDown)
        XCTAssertEqual(key("", 126), .moveUp)
        XCTAssertEqual(key("j"), .moveDown)
        XCTAssertEqual(key("k"), .moveUp)
    }

    func testReturnOpensAndEscapeCollapses() {
        XCTAssertEqual(key("", 36), .open)
        XCTAssertEqual(key("", 76), .open, "the numeric keypad's Enter too")
        XCTAssertEqual(key("", 53), .collapse)
    }

    func testSSnoozes() {
        XCTAssertEqual(key("s"), .snooze)
        XCTAssertEqual(key("S"), .snooze, "shift is how you typed it, not a chord")
    }

    func testCommandSwitchesTabsAndRefreshes() {
        XCTAssertEqual(key("1", cmd: true), .tab(0))
        XCTAssertEqual(key("2", cmd: true), .tab(1))
        XCTAssertEqual(key("r", cmd: true), .refresh)
    }

    /// A modifier held over a letter belongs to whatever shortcut the user
    /// meant. Swallowing those would make the drawer eat ⌘Q.
    func testModifiedKeysAreNotTheDrawers() {
        XCTAssertNil(key("s", cmd: true))
        XCTAssertNil(key("s", opt: true))
        XCTAssertNil(key("j", ctrl: true))
        XCTAssertNil(key("q", cmd: true))
    }

    func testUnknownKeysAreLeftAlone() {
        XCTAssertNil(key("x"))
        XCTAssertNil(key("", 999))
    }

    // MARK: - Moving

    let rows = ["a", "b", "c"]

    func testFirstPressSelectsAnEnd() {
        var down = Selection()
        down.move(by: 1, in: rows)
        XCTAssertEqual(down.id, "a")

        var up = Selection()
        up.move(by: -1, in: rows)
        XCTAssertEqual(up.id, "c")
    }

    func testMovesOneAtATime() {
        var selection = Selection(id: "a")
        selection.move(by: 1, in: rows)
        XCTAssertEqual(selection.id, "b")
        selection.move(by: -1, in: rows)
        XCTAssertEqual(selection.id, "a")
    }

    /// A list you are stepping through to clear is one you want to reach the
    /// bottom of and know it. Wrapping silently starts you round again.
    func testStopsAtTheEndsRatherThanWrapping() {
        var bottom = Selection(id: "c")
        bottom.move(by: 1, in: rows)
        XCTAssertEqual(bottom.id, "c")

        var top = Selection(id: "a")
        top.move(by: -1, in: rows)
        XCTAssertEqual(top.id, "a")
    }

    func testAnEmptyListSelectsNothing() {
        var selection = Selection(id: "a")
        selection.move(by: 1, in: [])
        XCTAssertNil(selection.id)
    }

    /// Held as an id, so a pull request arriving above the selected row does
    /// not silently move the selection onto its neighbour.
    func testAnArrivalAboveDoesNotMoveTheSelection() {
        var selection = Selection(id: "b")
        selection.move(by: 1, in: ["new", "a", "b", "c"])
        XCTAssertEqual(selection.id, "c")
    }

    func testASelectionWhoseRowIsGoneMovesToTheTop() {
        var selection = Selection(id: "b")
        selection.validate(against: ["a", "c"])
        XCTAssertEqual(selection.id, "a")
    }

    func testValidateLeavesALiveSelectionAlone() {
        var selection = Selection(id: "c")
        selection.validate(against: rows)
        XCTAssertEqual(selection.id, "c")
    }

    // MARK: - The chord

    func testParsesAChord() throws {
        let chord = try XCTUnwrap(HotKeyChord.parse("opt+shift+r"))
        XCTAssertEqual(chord.display, "⌥⇧R")
    }

    func testRejectsAChordWithNoModifier() {
        XCTAssertNil(HotKeyChord.parse("r"))
    }

    func testRejectsNonsense() {
        XCTAssertNil(HotKeyChord.parse("opt+shift+banana"))
        XCTAssertNil(HotKeyChord.parse(""))
        XCTAssertNil(HotKeyChord.parse(nil))
    }
}
