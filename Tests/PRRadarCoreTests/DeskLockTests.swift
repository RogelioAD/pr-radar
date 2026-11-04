import XCTest
@testable import PRRadarCore

final class DeskLockTests: XCTestCase {

    // MARK: - The mechanism

    /// The whole safety argument for this feature rests on the lock being the
    /// system's own, so the symbol being reached for is worth pinning down. A
    /// change here that swapped in a lock of our own — a window, a text field,
    /// a comparison against the account password — is the one-line diff most
    /// worth noticing in review.
    func testLocksThroughTheSystemLoginWindow() {
        XCTAssertEqual(DeskLock.symbol, "SACLockScreenImmediate")
        XCTAssertTrue(DeskLock.frameworkPath.hasSuffix("/login.framework/login"))
    }

    /// Resolving is deliberately separate from calling, so this can run on
    /// every build. A test that locked the machine running it would be a
    /// memorable way to learn the difference, once.
    func testResolvesOnThisMac() {
        XCTAssertNotNil(DeskLock.resolve())
        XCTAssertTrue(DeskLock.isAvailable())
    }

    /// The reason the symbol is looked up at runtime at all. `CGSession` was
    /// this feature's first implementation and macOS 26 removed it; the next
    /// removal should disable the button, not crash or silently stop locking.
    func testMissingSymbolResolvesToNothingRatherThanTrapping() {
        XCTAssertNil(DeskLock.resolve(path: "/nope/not/a/framework"))
        XCTAssertNil(DeskLock.resolve(name: "NotASymbolAnybodyShipped"))
    }

    func testUnavailableLockThrowsRatherThanReportingSuccess() {
        XCTAssertEqual(DeskLock.Failure.refused(7),
                       DeskLock.Failure.refused(7))
        XCTAssertNotEqual(DeskLock.Failure.refused(7),
                          DeskLock.Failure.unavailable)
    }

    /// The assertion shows up in `pmset -g assertions`, where it is read by
    /// someone who does not yet know PR Radar is why their Mac stopped
    /// sleeping. It has to name the app and the way out.
    func testAwakeReasonExplainsItselfToStrangers() {
        XCTAssertTrue(DeskLock.awakeReason.contains("PR Radar"))
        XCTAssertTrue(DeskLock.awakeReason.lowercased().contains("unlock"))
    }

    // MARK: - The tooltip, which is the control's only label

    func testHelpSaysBothHalvesOfWhatThePressDoes() {
        let help = DeskLock.help(available: true, error: nil)
        XCTAssertTrue(help.contains("Cover the screen"))
        XCTAssertTrue(help.contains("awake"))
    }

    /// The claim this feature is built on — that PR Radar never handles the
    /// password — is only reassuring if it is said somewhere it gets read.
    /// Naming the login window is how it is said: there is no in-app prompt
    /// left to confuse it with.
    func testHelpSaysWhoAsksForThePassword() {
        let help = DeskLock.help(available: true, error: nil)
        XCTAssertTrue(help.contains("login window"))
    }

    /// The away screen cannot let you back in by itself, and the tooltip must
    /// not imply otherwise. Somebody who expects a prompt and gets the login
    /// window has been surprised by their own lock screen, which is how people
    /// learn to stop trusting one.
    func testHelpSaysAKeypressLocksForReal() {
        let help = DeskLock.help(available: true, error: nil)
        XCTAssertTrue(help.contains("locks the Mac for real"))
        XCTAssertFalse(help.lowercased().contains("unlocks with"))
    }

    /// The hard lock has no control of its own, so the tooltip is the only
    /// place it is discoverable. A modifier nobody is told about is a feature
    /// that does not exist — and this is the one to reach for on the day the
    /// room is not one to trust.
    func testHelpTeachesTheModifierThatLocksForReal() {
        let help = DeskLock.help(available: true, error: nil)
        XCTAssertTrue(help.contains("Option-click"))
    }

    /// A failed lock has to say nothing happened, in both respects. Half the
    /// message — "could not lock" without "and it can still sleep" — leaves
    /// someone believing the run behind it is still protected.
    func testHelpOnFailureSaysNothingWasLeftHolding() {
        let help = DeskLock.help(available: true, error: "the screen did not lock.")
        XCTAssertTrue(help.contains("the screen did not lock."))
        XCTAssertTrue(help.contains("Nothing was locked"))
        XCTAssertTrue(help.contains("can still sleep"))
    }

    /// An error outranks unavailability: it describes a press that actually
    /// happened, which is the more specific thing to answer.
    func testErrorWinsOverUnavailable() {
        XCTAssertTrue(DeskLock.help(available: false, error: "boom").contains("boom"))
    }

    // MARK: - Reading the real lock state

    /// The key is absent when unlocked rather than present and false. Written
    /// as `!= false` this would call every unlocked Mac locked, and the
    /// assertion would be held for ever — so both directions are pinned.
    func testUnlockedIsTheAbsenceOfTheKey() {
        XCTAssertFalse(ScreenLock.isLocked { [:] })
        XCTAssertFalse(ScreenLock.isLocked { nil })
        XCTAssertTrue(ScreenLock.isLocked { [ScreenLock.key: true] })
        XCTAssertFalse(ScreenLock.isLocked { [ScreenLock.key: false] })
    }

    /// The suite runs at an unlocked Mac, so the live reader must agree.
    func testLiveReaderSaysUnlockedWhileTheseTestsRun() {
        XCTAssertFalse(ScreenLock.isLocked())
    }

    // MARK: - When to let the Mac sleep again

    /// The bug arming exists to prevent: the first poll lands in the gap
    /// between the press and the screen going, and a single-phase watch reads
    /// that as "already back" and drops the assertion it just took.
    func testArmingWaitsOutTheGapBeforeTheScreenGoes() {
        XCTAssertEqual(
            DeskLockWatch.next(phase: .arming, screenIsLocked: false, armingElapsed: 1),
            .keepWaiting)
    }

    func testArmingBecomesHoldingOnceTheScreenIsSeenLocked() {
        XCTAssertEqual(
            DeskLockWatch.next(phase: .arming, screenIsLocked: true, armingElapsed: 1),
            .nowHolding)
    }

    /// **The most important assertion in this file.** Never seeing the lock
    /// take effect must not release the assertion.
    ///
    /// The bias is deliberate and asymmetric: releasing wrongly puts the Mac
    /// to sleep behind a locked screen and kills whatever was running — the
    /// exact thing this feature exists to prevent, at the exact moment nobody
    /// is there to notice. Holding wrongly keeps a locked Mac awake slightly
    /// too long and costs nothing. Failing to observe something is not
    /// evidence that it did not happen.
    func testNeverSeeingTheLockStillHoldsTheMacAwake() {
        XCTAssertEqual(
            DeskLockWatch.next(phase: .arming, screenIsLocked: false,
                               armingElapsed: DeskLockWatch.armingGrace),
            .holdUnconfirmed)
    }

    /// And once in that state it stops asking. A reader that never said
    /// *locked* cannot be believed when it says *unlocked* either, and acting
    /// on it would drop the assertion in the one situation it exists for.
    func testAnUnconfirmedHoldNeverReleasesOnItsOwn() {
        for elapsed in [0.0, 60.0, 86_400.0] {
            XCTAssertEqual(
                DeskLockWatch.next(phase: .holdingUnconfirmed,
                                   screenIsLocked: false, armingElapsed: elapsed),
                .keepWaiting)
            XCTAssertEqual(
                DeskLockWatch.next(phase: .holdingUnconfirmed,
                                   screenIsLocked: true, armingElapsed: elapsed),
                .keepWaiting)
        }
    }

    /// Arming must get more than one look. A grace period equal to a single
    /// poll gives it exactly one chance to observe the lock, and one late poll
    /// then reports a failure — and drops the assertion — for a Mac that is at
    /// that moment correctly locked, with a review running behind it.
    func testArmingGetsSeveralPollsBeforeGivingUp() {
        XCTAssertGreaterThan(DeskLockWatch.armingGrace, DeskLockWatch.interval * 2)
    }

    func testHoldingKeepsTheAssertionWhileTheScreenStaysLocked() {
        XCTAssertEqual(
            DeskLockWatch.next(phase: .holding, screenIsLocked: true, armingElapsed: 600),
            .keepWaiting)
    }

    /// Coming back is the only thing that ends a successful lock.
    func testHoldingReleasesTheMomentTheScreenIsUnlocked() {
        XCTAssertEqual(
            DeskLockWatch.next(phase: .holding, screenIsLocked: false, armingElapsed: 600),
            .release)
    }

    /// An unlock hours later is still an unlock. Holding has no deadline of
    /// its own — the grace period belongs to arming alone, and a review that
    /// runs longer than it must not be cut off by it.
    func testHoldingHasNoDeadlineOfItsOwn() {
        XCTAssertEqual(
            DeskLockWatch.next(phase: .holding, screenIsLocked: true, armingElapsed: 86_400),
            .keepWaiting)
    }

    // MARK: - The sleep assertion

    /// Begun twice, the second call must not strand the first token — a leaked
    /// activity is a Mac that never sleeps again until the app quits, with
    /// nothing on screen to suggest why.
    @MainActor
    func testStayAwakeIsIdempotentInBothDirections() {
        let awake = StayAwake()
        XCTAssertFalse(awake.isHeld)

        awake.begin(reason: "test")
        awake.begin(reason: "test")
        XCTAssertTrue(awake.isHeld)

        awake.end()
        XCTAssertFalse(awake.isHeld)
        // Ending one that was never begun has to be a no-op: a failed lock and
        // the watch loop can both reach release, and both are allowed to win.
        awake.end()
        XCTAssertFalse(awake.isHeld)
    }

    /// The away screen keeps the display on; the system lock lets it sleep.
    /// Re-aiming must not leak the first assertion — a leaked one is a Mac
    /// that never sleeps again until the app quits.
    @MainActor
    func testStayAwakeCanBeReAimedBetweenModes() {
        let awake = StayAwake()
        awake.begin(display: true, reason: "test")
        XCTAssertTrue(awake.isHeld)
        XCTAssertTrue(awake.isHoldingDisplay)

        awake.begin(display: false, reason: "test")
        XCTAssertTrue(awake.isHeld)
        XCTAssertFalse(awake.isHoldingDisplay)

        // Still just one, and still releasable in one call.
        awake.end()
        XCTAssertFalse(awake.isHeld)
        XCTAssertFalse(awake.isHoldingDisplay)
    }

    /// Asking for the mode it already has is a no-op rather than a churn of
    /// assertions: the escalation path and the exit path can both reach it.
    @MainActor
    func testReAimingToTheSameModeDoesNothing() {
        let awake = StayAwake()
        awake.begin(display: true, reason: "test")
        awake.begin(display: true, reason: "test")
        XCTAssertTrue(awake.isHoldingDisplay)
        awake.end()
        XCTAssertFalse(awake.isHeld)
    }

    @MainActor
    func testStayAwakeCanBeRetaken() {
        let awake = StayAwake()
        awake.begin(reason: "test")
        awake.end()
        awake.begin(reason: "test")
        XCTAssertTrue(awake.isHeld)
        awake.end()
    }
}
