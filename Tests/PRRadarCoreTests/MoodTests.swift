import XCTest
@testable import PRRadarCore

final class MoodTests: XCTestCase {

    private func mood(reviews: Int = 3,
                      worst: Staleness = .fresh,
                      ready: Int = 0,
                      refreshing: Bool = false,
                      problem: Bool = false) -> Mood {
        Mood.of(reviews: reviews, worst: worst, readyToMerge: ready,
                isRefreshing: refreshing, hasProblem: problem)
    }

    /// Nothing else on screen can be trusted while the token is broken, so a
    /// problem outranks every other input including a refresh in flight.
    func testAProblemBeatsEverything() {
        XCTAssertEqual(mood(reviews: 9, worst: .stale, ready: 4,
                            refreshing: true, problem: true), .lost)
        XCTAssertEqual(mood(reviews: 0, problem: true), .lost)
    }

    /// "I am checking" is the more useful answer to "is this number still true".
    func testRefreshingBeatsStaleness() {
        XCTAssertEqual(mood(reviews: 9, worst: .stale, refreshing: true), .working)
        XCTAssertEqual(mood(reviews: 0, refreshing: true), .working)
    }

    func testAnEmptyListSleepsUnlessSomethingIsReady() {
        XCTAssertEqual(mood(reviews: 0), .asleep)
        XCTAssertEqual(mood(reviews: 0, ready: 1), .proud)
    }

    /// Ready-to-merge is about your own work; it must never soften a review
    /// someone else is waiting on.
    func testReadyToMergeDoesNotMaskWaitingReviews() {
        XCTAssertEqual(mood(reviews: 1, worst: .stale, ready: 5), .alarmed)
        XCTAssertEqual(mood(reviews: 1, worst: .fresh, ready: 5), .idle)
    }

    func testStalenessMapsStraightThrough() {
        XCTAssertEqual(mood(worst: .fresh), .idle)
        XCTAssertEqual(mood(worst: .aging), .nudging)
        XCTAssertEqual(mood(worst: .stale), .alarmed)
    }

    /// The mascot and the count badge must be the same colour by construction.
    func testMoodColoursTrackTheStalenessScale() {
        XCTAssertEqual(Mood.idle.style.health, Staleness.fresh.health)
        XCTAssertEqual(Mood.nudging.style.health, Staleness.aging.health)
        XCTAssertEqual(Mood.alarmed.style.health, Staleness.stale.health)
    }

    /// Exactly the four the empty-state mascot can ever be asked to draw.
    func testOnlyFourMoodsAreReachableWithAnEmptyList() {
        let reachable = Mood.allCases.filter(\.reachableWhenListEmpty)
        XCTAssertEqual(Set(reachable), [.asleep, .working, .proud, .lost])

        // And the claim is true of the derivation, not just the flag.
        for refreshing in [true, false] {
            for problem in [true, false] {
                for ready in [0, 2] {
                    let result = mood(reviews: 0, ready: ready,
                                      refreshing: refreshing, problem: problem)
                    XCTAssertTrue(result.reachableWhenListEmpty,
                                  "\(result) came out of an empty list but is marked unreachable")
                }
            }
        }
    }

    func testEveryStyleHasFramesToCycle() {
        for mood in Mood.allCases {
            XCTAssertFalse(mood.style.marks.isEmpty, "\(mood) has no marks")
            XCTAssertFalse(mood.style.bob.isEmpty, "\(mood) has no bob")
            // Frame indices come from a free-running counter.
            XCTAssertNoThrow(mood.style.mark(frame: 9_999))
            XCTAssertEqual(mood.style.offset(frame: 0), mood.style.bob[0])
        }
        for reaction in Reaction.allCases {
            let style = reaction.style(tint: .running)
            XCTAssertFalse(style.marks.isEmpty)
            XCTAssertFalse(style.bob.isEmpty)
        }
    }

    func testEveryMarkIsTheDeclaredSize() {
        for mark in Mark.allCases {
            XCTAssertEqual(mark.rows.count, Mark.height, "\(mark)")
            XCTAssertTrue(mark.rows.allSatisfy { $0.count == Mark.width }, "\(mark)")
        }
    }
}

// MARK: - Layout

final class SpriteLayoutTests: XCTestCase {

    /// The mistake this exists to prevent: centring the chips on the 21-wide
    /// block instead of the character's sixteen columns puts them three pixels
    /// to the right, because the block carries the mood gutter on that side.
    func testChipsCentreOnTheCharacterNotTheBlock() {
        for reviews in [0, 7, 12, 100] {
            for ready in [0, 2, 40] {
                let layout = SpriteLayout.widget(
                    mascot: .pip, style: Mood.alarmed.style, frame: 0, blink: false,
                    reviews: reviews, reviewHealth: .bad, readyToMerge: ready)

                let character = layout.layers[0]
                let characterCentre = Double(character.origin.x + SpriteLayout.characterSize / 2)

                let chips = layout.layers.filter { $0.sprite.height == Counter.height }
                guard let first = chips.first, let last = chips.last else { continue }
                let chipCentre = Double(first.origin.x + last.origin.x + last.sprite.width) / 2

                XCTAssertEqual(chipCentre, characterCentre, accuracy: 0.5,
                               "reviews \(reviews), ready \(ready)")
            }
        }
    }

    func testEveryLayerFitsInsideTheReportedBounds() {
        for mascot in Mascot.all {
            for mood in Mood.allCases {
                for frame in 0..<6 {
                    let layout = SpriteLayout.widget(
                        mascot: mascot, style: mood.style, frame: frame, blink: false,
                        reviews: 100, reviewHealth: .bad, readyToMerge: 3)
                    for layer in layout.layers {
                        XCTAssertGreaterThanOrEqual(layer.origin.x, 0)
                        XCTAssertGreaterThanOrEqual(layer.origin.y, 0)
                        XCTAssertLessThanOrEqual(layer.origin.x + layer.sprite.width,
                                                 layout.width, "\(mascot.name)/\(mood) x")
                        XCTAssertLessThanOrEqual(layer.origin.y + layer.sprite.height,
                                                 layout.height, "\(mascot.name)/\(mood) y")
                    }
                }
            }
        }
    }

    /// Inbox zero is a sleeping character and nothing else — no empty tile, no
    /// stale badge.
    func testZeroCountsDrawNoChips() {
        let layout = SpriteLayout.widget(
            mascot: .pip, style: Mood.asleep.style, frame: 0, blink: false,
            reviews: 0, reviewHealth: .good, readyToMerge: 0)
        XCTAssertFalse(layout.layers.contains { $0.sprite.height == Counter.height })
    }

    /// A bobbing character must never be clipped by its own bounds.
    func testBobNeverEscapesTheLayout() {
        for mascot in Mascot.all {
            for mood in Mood.allCases + [] {
                for frame in 0..<12 {
                    let layout = SpriteLayout.perch(mascot: mascot, style: mood.style,
                                                    frame: frame, blink: false,
                                                    crop: mascot.headRows)
                    for layer in layout.layers {
                        XCTAssertLessThanOrEqual(layer.origin.y + layer.sprite.height,
                                                 layout.height,
                                                 "\(mascot.name)/\(mood) frame \(frame)")
                    }
                }
            }
        }
    }

    func testPerchCropTrimsTheCollarButKeepsTheHead() {
        let full = SpriteLayout.perch(mascot: .pip, style: Mood.idle.style,
                                      frame: 0, blink: false)
        let head = SpriteLayout.perch(mascot: .pip, style: Mood.idle.style,
                                      frame: 0, blink: false, crop: Mascot.pip.headRows)
        XCTAssertEqual(head.layers[0].sprite.height, 12)
        XCTAssertEqual(full.layers[0].sprite.height, 16)
        // The eyes survive the crop; that is the whole point of it.
        for box in Mascot.pip.eyes {
            XCTAssertLessThan(box.y + 1, Mascot.pip.headRows)
        }
    }

    func testHaloWrapsTheWholeCompositionAsOne() {
        let layout = SpriteLayout.widget(
            mascot: .widget, style: Mood.alarmed.style, frame: 0, blink: false,
            reviews: 7, reviewHealth: .bad, readyToMerge: 2)
        let halo = layout.halo()
        XCTAssertFalse(halo.isEmpty)
        for point in halo {
            XCTAssertFalse(layout.isLit(x: point.x, y: point.y),
                           "halo overlaps the art at \(point)")
        }
        // It reaches the chips, not just the character — one sticker, not three.
        let chipY = layout.layers.last!.origin.y
        XCTAssertTrue(halo.contains { $0.y >= chipY },
                      "halo stopped before the counter chips")
    }
}

final class BlinkTests: XCTestCase {

    private let tempos: [Double] = [1, 2, 6, 30]

    /// The point of scheduling in seconds: the badge runs at a third of the
    /// drawer's rate and must not therefore blink a third as often.
    func testBlinkRateIsTheSameAtEveryTempo() {
        for fps in tempos {
            let seconds = 70.0
            let frames = Int(seconds * fps)
            var blinks = 0, wasBlinking = false
            for frame in 0..<frames {
                let now = Blink.isBlinking(frame: frame, fps: fps)
                if now && !wasBlinking { blinks += 1 }
                wasBlinking = now
            }
            let expected = seconds / Blink.interval
            XCTAssertEqual(Double(blinks), expected, accuracy: 1,
                           "\(fps) fps blinked \(blinks) times in \(seconds)s")
        }
    }

    /// A slow clock must not step straight over the blink window.
    func testEveryTempoActuallyClosesTheEyes() {
        for fps in tempos {
            let period = Blink.periodFrames(fps: fps)
            let closed = (0..<period).filter { Blink.isBlinking(frame: $0, fps: fps) }
            XCTAssertFalse(closed.isEmpty, "\(fps) fps never blinks")
            XCTAssertGreaterThanOrEqual(Blink.holdFrames(fps: fps), 1)
            // And it opens them again — a blink that never ends is a shut eye.
            XCTAssertLessThan(closed.count, period, "\(fps) fps never opens")
        }
    }

    /// The frame index comes from a free-running clock, which is negative for
    /// dates before the reference date.
    func testNegativeAndHugeFrameIndicesAreSafe() {
        for fps in tempos {
            XCTAssertNoThrow(Blink.isBlinking(frame: -1, fps: fps))
            XCTAssertNoThrow(Blink.isBlinking(frame: Int.max, fps: fps))
            XCTAssertNoThrow(Blink.isBlinking(frame: Int.min + 1, fps: fps))
        }
        XCTAssertFalse(Blink.isBlinking(frame: 3, fps: 0), "a stopped clock never blinks")
    }
}
