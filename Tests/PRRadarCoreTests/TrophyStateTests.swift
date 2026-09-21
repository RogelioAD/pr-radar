import XCTest
@testable import PRRadarCore

/// The shelf is the one part of this feature that outlives a launch, so what
/// it does with an unfamiliar or damaged store matters more than what it does
/// with a good one.
final class TrophyStateTests: XCTestCase {

    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Round trip

    func testARoundTripKeepsEverything() {
        var state = TrophyState()
        state.established = true
        state.unlocked["swamped"] = epoch
        state.counters["queue.cleared"] = 3
        state.record(TrophyFact.usedStackedFilter)
        state.lastDay = "2027-09-21"
        state.unseen = ["swamped"]

        XCTAssertEqual(TrophyState.decoded(from: state.encoded()), state)
    }

    func testNothingStoredIsAnEmptyShelf() {
        let state = TrophyState.decoded(from: nil)
        XCTAssertTrue(state.unlocked.isEmpty)
        XCTAssertFalse(state.established)
    }

    /// A trophy room is not worth failing a launch over.
    func testGarbageIsAnEmptyShelfRatherThanACrash() {
        XCTAssertEqual(TrophyState.decoded(from: Data("not json".utf8)), TrophyState())
    }

    /// The reason ids are stored as raw strings. A trophy retired in a future
    /// build must cost its owner that one trophy, not the whole shelf —
    /// `Codable` fails a value, not a field.
    func testAnUnknownTrophyIDSurvivesDecodingAndIsIgnored() {
        var state = TrophyState()
        state.unlocked["swamped"] = epoch
        state.unlocked["trophyFromAFutureBuild"] = epoch

        let decoded = TrophyState.decoded(from: state.encoded())
        XCTAssertEqual(decoded.unlocked.count, 2)
        XCTAssertEqual(decoded.unlockedIDs, [.swamped])
    }

    // MARK: - Unlocking

    func testUnlockingIsIdempotentAndKeepsTheFirstDate() {
        var state = TrophyState()
        state.established = true
        let later = epoch.addingTimeInterval(86_400)

        _ = TrophyEvaluator.evaluate(TrophySnapshot(), state: state)
        state.unlocked["swamped"] = epoch
        state.unlocked["swamped"] = state.unlocked["swamped"] ?? later
        XCTAssertEqual(state.unlockedAt(.swamped), epoch)
    }

    func testTheUnseenSetIsTheDotOnTheButton() {
        var snapshot = TrophySnapshot()
        snapshot.reviews = []
        var state = TrophyState()
        state.established = true
        snapshot.badgeMinimum = 28
        snapshot.badgeMaximum = 128
        snapshot.badgeTileSize = 128

        state = TrophyEvaluator.evaluate(snapshot, state: state).state
        XCTAssertTrue(state.hasUnseen)
        XCTAssertEqual(state.unseenCount, 1)

        state.markAllSeen()
        XCTAssertFalse(state.hasUnseen)
        // Seen is not un-earned.
        XCTAssertTrue(state.isUnlocked(.bigBadge))
    }

    // MARK: - Facts

    func testRecordingAFactIsIdempotent() {
        var state = TrophyState()
        state.record(TrophyFact.usedStackedFilter)
        state.record(TrophyFact.usedStackedFilter)
        XCTAssertEqual(state.flags.count, 1)
        XCTAssertTrue(state.has(TrophyFact.usedStackedFilter))
    }

    /// Corners are counted by prefix, so the naming has to hold.
    func testCornerFactsShareOnePrefix() {
        XCTAssertTrue(TrophyFact.badgeCorner("top-left")
            .hasPrefix(TrophyFact.cornerPrefix))
        XCTAssertNotEqual(TrophyFact.badgeCorner("top-left"),
                          TrophyFact.badgeCorner("top-right"))
    }

    /// Mascot facts must not collide with each other, or `Meet the Cast`
    /// would unlock on one character.
    func testMascotFactsAreDistinct() {
        let facts = MascotID.allCases.map(TrophyFact.mascotSeen)
        XCTAssertEqual(Set(facts).count, MascotID.allCases.count)
    }

    // MARK: - The debug shelf

    func testEverythingUnlockedFillsTheShelfWithoutMarkingItNew() {
        let state = TrophyState.everythingUnlocked(at: epoch)
        XCTAssertEqual(state.unlockedIDs.count, Trophy.all.count)
        XCTAssertTrue(state.established)
        // No dot: nothing about looking at the room should look like news.
        XCTAssertFalse(state.hasUnseen)
    }
}
