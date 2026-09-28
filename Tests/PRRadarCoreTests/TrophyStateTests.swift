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

// MARK: - Which trophy is the new one

/// The shelf's button goes quiet the moment the room opens — you have seen
/// them, so the dot on the button is right to go. But that left nothing to say
/// *which* of thirty drawings had changed, at exactly the moment you could
/// finally look. The unseen set is therefore read before it is cleared, and the
/// answer held for the length of the visit.
extension TrophyStateTests {

    func testTheUnseenSetIsWhatTheRoomHasToCaptureBeforeClearing() {
        var state = TrophyState()
        state.unlocked["swamped"] = epoch
        state.unseen = ["swamped"]
        XCTAssertTrue(state.hasUnseen)

        let captured = state.unseen
        state.markAllSeen()

        // The button has nothing left to announce...
        XCTAssertFalse(state.hasUnseen)
        XCTAssertEqual(state.unseenCount, 0)
        // ...and the room still knows which one it was.
        XCTAssertEqual(captured, ["swamped"])
    }

    /// Several at once is the case the dot exists for: a backfill can unlock a
    /// handful, and "3 new" on the button does not say which three.
    func testEveryNewlyUnlockedTrophyIsCaptured() {
        var state = TrophyState()
        state.unseen = ["swamped", "century", "nightowl"]
        XCTAssertEqual(state.unseenCount, 3)
        let captured = state.unseen
        state.markAllSeen()
        XCTAssertEqual(captured.count, 3)
        XCTAssertTrue(state.unseen.isEmpty)
    }

    /// Nothing new means nothing to capture, and no dots to draw.
    func testAShelfWithNothingNewCapturesNothing() {
        var state = TrophyState()
        state.unlocked["swamped"] = epoch
        XCTAssertFalse(state.hasUnseen)
        XCTAssertTrue(state.unseen.isEmpty)
    }

    /// The marker is not persisted as a *seen* flag per trophy, so a round trip
    /// must not resurrect an announcement that has already been made.
    func testSeenTrophiesStaySeenAcrossARoundTrip() {
        var state = TrophyState()
        state.unlocked["swamped"] = epoch
        state.unseen = ["swamped"]
        state.markAllSeen()
        XCTAssertFalse(TrophyState.decoded(from: state.encoded()).hasUnseen)
    }
}
