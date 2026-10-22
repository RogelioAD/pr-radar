import XCTest
@testable import PRRadarCore

/// ↑↑↓↓←→←→BA.
final class KonamiTests: XCTestCase {

    let up: UInt16 = 126, down: UInt16 = 125
    let left: UInt16 = 123, right: UInt16 = 124
    let b: UInt16 = 11, a: UInt16 = 0

    var full: [UInt16] { [up, up, down, down, left, right, left, right, b, a] }

    func feed(_ codes: [UInt16], into konami: inout Konami) -> Bool {
        var fired = false
        for code in codes where konami.accept(keyCode: code) { fired = true }
        return fired
    }

    func testTheWholeThingFires() {
        var konami = Konami()
        XCTAssertTrue(feed(full, into: &konami))
    }

    /// Only on the last key, never early.
    func testNothingFiresPartway() {
        var konami = Konami()
        XCTAssertFalse(feed(Array(full.dropLast()), into: &konami))
        XCTAssertTrue(konami.accept(keyCode: a))
    }

    func testAWrongKeyResets() {
        var konami = Konami()
        _ = feed([up, up, down, down], into: &konami)
        XCTAssertFalse(konami.accept(keyCode: right), "left comes next, not right")
        XCTAssertEqual(konami.progress, 0)
        XCTAssertFalse(feed([left, right, left, right, b, a], into: &konami),
                       "the reset should mean this run is short")
    }

    /// Three ups is what you get when somebody holds the key down, and it
    /// must not throw the attempt away — the extra press simply starts a
    /// fresh one.
    func testARepeatedFirstKeyRestartsRatherThanResetting() {
        var konami = Konami()
        XCTAssertTrue(feed([up, up, up, up, down, down,
                            left, right, left, right, b, a], into: &konami))
    }

    func testItFiresAgainAfterwards() {
        var konami = Konami()
        XCTAssertTrue(feed(full, into: &konami))
        XCTAssertEqual(konami.progress, 0, "it should rearm itself")
        XCTAssertTrue(feed(full, into: &konami))
    }

    func testResetClearsProgress() {
        var konami = Konami()
        _ = feed([up, up, down], into: &konami)
        XCTAssertEqual(konami.progress, 3)
        konami.reset()
        XCTAssertEqual(konami.progress, 0)
    }

    /// Unrelated typing never accidentally arms it.
    func testOrdinaryKeysDoNothing() {
        var konami = Konami()
        XCTAssertFalse(feed([1, 2, 3, 36, 53, 11, 0], into: &konami))
    }

    /// The two arrows the drawer already uses are in the sequence, so the
    /// watcher has to be an observer — this is the shape that proves it is
    /// reading codes and not consuming commands.
    func testTheSequenceUsesTheListsOwnArrows() {
        XCTAssertEqual(KeyCommand.from(characters: "", keyCode: up,
                                       hasCommand: false, hasOption: false,
                                       hasControl: false), .moveUp)
        XCTAssertEqual(KeyCommand.from(characters: "", keyCode: down,
                                       hasCommand: false, hasOption: false,
                                       hasControl: false), .moveDown)
        XCTAssertTrue(Konami.sequence.contains(up))
        XCTAssertTrue(Konami.sequence.contains(down))
    }
}
