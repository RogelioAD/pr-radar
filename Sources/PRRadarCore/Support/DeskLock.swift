import CoreGraphics
import Foundation

/// Locks the screen, and keeps the machine awake behind it.
///
/// One button and two problems, which only look unrelated. Starting a review
/// and walking away fails in two different ways: the Mac idles into sleep and
/// the run stops halfway, or it stays awake and the screen is open to whoever
/// walks past the desk. Either one alone is not worth a control in the most
/// contested 440pt in the app. Both together are.
///
/// **Locking does not pause anything.** This is the misconception the feature
/// exists to correct, and it decides the whole shape below: a locked Mac still
/// runs every process on it, so a review started before the lock keeps going
/// behind it, writes its comments, and is finished when you come back. What
/// stops a run is *sleep*. So the lock is the half that handles the passer-by
/// and `StayAwake` is the half that handles the deadline — shipping only the
/// first would be a button that appears to solve the problem it was asked for
/// and does not.
///
/// **The password is never this app's business.** The lock below is the same
/// one Control-Command-Q performs: the session is handed to the real login
/// window, which is already trusted to ask for the account password. Touch ID
/// works, Apple Watch unlock works, a password manager works, and none of them
/// route through PR Radar. The alternative — a panel of our own covering the
/// screen, swallowing the keyboard, comparing what you typed against your
/// account password — is the same artifact a credential phish produces. It
/// would hold the one secret on this machine worth stealing, it would train
/// the habit of typing that password into whatever asks for it, and the first
/// time it crashed mid-lock it would strand you at a dead screen on your own
/// Mac. Three costs, nothing bought: the login window already does this
/// correctly.
public enum DeskLock {

    typealias LockNow = @convention(c) () -> Int32

    /// The private symbol behind Control-Command-Q.
    ///
    /// Private, which is a real cost and is taken deliberately, because macOS
    /// has never shipped a public one and every alternative is worse:
    ///
    /// - `CGSession -suspend` was this feature's first implementation and was
    ///   removed from the OS. `User.menu`, which carried it, is gone as of
    ///   macOS 26 — the test asserting it existed is what caught that.
    /// - `pmset displaysleepnow` sleeps the *display*. Whether that locks
    ///   anything depends on a Lock Screen setting this app cannot reliably
    ///   read, so on a Mac set to ask for a password five minutes after sleep
    ///   it would report success, darken the screen, and leave the session open
    ///   for five minutes. A lock button whose locking is conditional on a
    ///   preference elsewhere is worse than no lock button, because it is
    ///   trusted. The same objection retires the screen-saver trick.
    /// - Sending the keystroke through System Events needs Accessibility
    ///   permission — handing a background app the right to synthesise input
    ///   across every window on the machine, to avoid one private symbol. That
    ///   is a far larger thing to grant than the one it would buy.
    ///
    /// So: resolved at runtime, never assumed. If a future macOS drops it the
    /// button disables itself and says why, which is the one behaviour that
    /// stays honest. A lock that silently stopped locking is the failure this
    /// whole feature cannot afford — you find out by coming back to an open
    /// Mac, hours later, having trusted it.
    public static let frameworkPath =
        "/System/Library/PrivateFrameworks/login.framework/login"

    public static let symbol = "SACLockScreenImmediate"

    /// Looks the symbol up without calling it.
    ///
    /// Separate from the call so availability can be tested on every build
    /// without locking the machine running the tests — which, for a test suite
    /// run from a terminal, would be a memorable way to learn the difference.
    ///
    /// The handle is never `dlclose`d. It is the login framework, it is already
    /// resident in every GUI process, and closing it would invalidate a pointer
    /// this app holds for its whole life.
    static func resolve(path: String = frameworkPath,
                        name: String = symbol) -> LockNow? {
        guard let handle = dlopen(path, RTLD_LAZY) else { return nil }
        guard let address = dlsym(handle, name) else { return nil }
        return unsafeBitCast(address, to: LockNow.self)
    }

    /// Resolved once. The framework does not come and go while we run, and a
    /// `dlopen` per render of the header would be a syscall for an answer that
    /// cannot have changed.
    static let lockNow: LockNow? = resolve()

    public static func isAvailable() -> Bool { lockNow != nil }

    public enum Failure: LocalizedError, Equatable {
        case unavailable
        case refused(Int32)

        public var errorDescription: String? {
            switch self {
            case .unavailable:
                return "this version of macOS has no \(DeskLock.symbol) to lock with."
            case .refused(let status):
                return "the login window refused it (status \(status))."
            }
        }
    }

    /// Hands the screen to the login window. Returns when it has gone.
    public static func lock() throws {
        guard let lockNow else { throw Failure.unavailable }
        let status = lockNow()
        guard status == 0 else { throw Failure.refused(status) }
    }

    /// What `pmset -g assertions` will show while the lock is held.
    ///
    /// Written to be read by someone who did not know PR Radar was the reason
    /// their Mac stopped sleeping. An assertion naming only the app is a
    /// mystery to debug; this one gives the app, the cause and the way out in
    /// a single line.
    public static let awakeReason =
        "PR Radar is holding the desk locked so work in progress can finish. Unlock to release."

    /// The tooltip, which is the only label this control has.
    ///
    /// A one-glyph button in a header with no room for a caption, doing
    /// something that takes over the whole screen, has to say what will happen
    /// *before* it happens — there is no undo for "the screen went black and I
    /// do not know what this app just did".
    public static func help(available: Bool, error: String?) -> String {
        if let error {
            return "Could not lock the screen: \(error) Nothing was locked and "
                + "the Mac can still sleep."
        }
        guard available else {
            return "This version of macOS gives PR Radar no way to lock the "
                + "screen that it would be safe to trust."
        }
        return "Cover the screen and keep the Mac awake behind it, so a review "
            + "in flight finishes while you are away — the away screen says "
            + "what is still running. Touching the keyboard, or anything "
            + "getting in front of it, locks the Mac for real; you sign back "
            + "in at the login window with your usual password or Touch ID. "
            + "Option-click to go straight there. Normal sleep resumes when "
            + "you return."
    }
}

/// Holds the machine awake, and lets go.
///
/// `ProcessInfo.beginActivity` rather than an `IOPMAssertion` from IOKit: it is
/// the supported Foundation spelling of the same assertion, and it is released
/// automatically if this process dies — which an IOKit assertion leaked by a
/// crash is not.
///
/// **Two modes, because the two covers want opposite things from the display.**
///
/// Only *system* sleep stops work, so `.idleSystemSleepDisabled` is held in
/// both. The difference is the screen:
///
/// - **The away screen keeps the display on.** Its entire purpose is to be
///   read from the doorway, and a status board that goes dark after ten
///   minutes is not a status board. Letting the display sleep behind it made
///   the feature quietly useless at exactly the distance it was built for —
///   and worse, left a dark screen that is indistinguishable, from across a
///   room, from a Mac that has gone to sleep and taken the work with it.
/// - **The system lock lets it sleep.** There is nothing on the login window
///   worth reading, so burning a backlight for hours would buy nothing. This
///   is also the honest way to get a dark screen on purpose: Option-click.
///
/// A dark screen is therefore a *choice* either way, which is the point. The
/// display going off while the away screen was up read as the Mac dying, and a
/// lock screen that cannot be told from a dead machine is one you stop
/// trusting.
///
/// Two limits this cannot lift, both of them the system declining to be
/// overruled by an app, and both worth knowing before trusting a long run to
/// it: closing the lid still sleeps a laptop, and so does choosing Sleep from
/// the Apple menu. Leave the lid open.
@MainActor
public final class StayAwake {

    private var token: NSObjectProtocol?
    /// Whether the held assertion is currently keeping the display on.
    private var holdsDisplay = false

    public init() {}

    public var isHeld: Bool { token != nil }

    /// Idempotent, and safe to call again to *change* mode.
    ///
    /// The callers are a button someone can press twice, a cover handing over
    /// to the system lock, and a notification that can arrive more than once —
    /// so this has to be safe to repeat and safe to re-aim. A second token
    /// taken without releasing the first would leak it, and ending an activity
    /// that was never begun would trap.
    ///
    /// When the mode changes the new assertion is taken **before** the old one
    /// is released. The gap the other order would open is small and the odds of
    /// losing a race in it are slim, which is exactly the kind of bug that
    /// surfaces once a month on somebody else's machine and never reproduces.
    public func begin(display: Bool = false,
                      reason: String = DeskLock.awakeReason) {
        if token != nil && holdsDisplay == display { return }

        var options: ProcessInfo.ActivityOptions = [.idleSystemSleepDisabled,
                                                    .userInitiated]
        if display { options.insert(.idleDisplaySleepDisabled) }

        let replacing = token
        token = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
        holdsDisplay = display
        if let replacing { ProcessInfo.processInfo.endActivity(replacing) }
    }

    /// Whether the display is being held on as well as the system.
    public var isHoldingDisplay: Bool { token != nil && holdsDisplay }

    public func end() {
        guard let token else { return }
        ProcessInfo.processInfo.endActivity(token)
        self.token = nil
        holdsDisplay = false
    }
}

/// Whether the screen is locked right now, asked of the window server.
///
/// `CGSessionCopyCurrentDictionary` is public API and reports the truth rather
/// than what this app believes it arranged. That distinction is the point: the
/// screen can be unlocked by someone who never saw PR Radar's button, and it
/// can be locked by Control-Command-Q a minute after our own lock was released.
///
/// The key is *absent* when unlocked rather than present and false, so the
/// comparison has to be written as a positive test. Read as `!= false` it would
/// report every unlocked Mac as locked, which on this feature's one job is the
/// wrong way round: the assertion would be held for ever.
public enum ScreenLock {
    public static let key = "CGSSessionScreenIsLocked"

    public static func isLocked(
        session: () -> [String: Any]? = { CGSessionCopyCurrentDictionary() as? [String: Any] }
    ) -> Bool {
        session()?[key] as? Bool == true
    }
}

/// When to let the Mac sleep again.
///
/// A loop that watches the real lock state, rather than waiting to be told. The
/// notification this could have subscribed to is undocumented, and the cost of
/// it not arriving is a Mac that never sleeps again until the app quits — a
/// symptom nobody would trace back to a lock button pressed hours earlier.
/// Asking the window server every few seconds cannot go quietly wrong in that
/// way, and a few extra seconds awake after you sit down is unnoticeable.
///
/// Arming is separate from holding because the first poll can easily land in
/// the gap between the press and the screen actually going. Treated as one
/// phase, that poll would see an unlocked screen, conclude you had already come
/// back, and drop the assertion a moment after taking it.
public enum DeskLockWatch {

    public enum Phase: Equatable {
        /// Locked, waiting to see it take effect.
        case arming
        /// Confirmed locked. Holding the Mac awake until it is not.
        case holding
        /// Locked as far as the call was concerned, but never observed as
        /// locked. The Mac is held awake and this loop stops asking: a reader
        /// that never said *locked* cannot be believed when it says
        /// *unlocked* either, and acting on it would drop the assertion in
        /// the one situation it exists for.
        case holdingUnconfirmed
    }

    public enum Step: Equatable {
        case keepWaiting
        case nowHolding
        case release
        /// Never seen locked inside the grace period. **Keeps the Mac awake.**
        case holdUnconfirmed
    }

    /// How long the screen is given to go, before the observation is given up
    /// on — not before the lock is called a failure.
    ///
    /// Three polls' worth, not one. The call is immediate, so this is a ceiling
    /// for a wedged login window rather than a slow one — but a grace period
    /// equal to a single interval gives arming exactly one chance to observe
    /// the lock, and one late poll then reports a failure for a Mac that is, at
    /// that moment, correctly locked. The asymmetry is the reason: a false
    /// failure costs a wrong orange padlock and a dropped assertion on a locked
    /// screen, and waiting a few more seconds costs nothing at all.
    public static let armingGrace: TimeInterval = 6

    /// How often the question gets asked. A cheap call to the window server,
    /// on a machine that is being deliberately held awake anyway.
    public static let interval: TimeInterval = 2

    /// **The bias here is deliberate and is the whole point of this type.**
    ///
    /// Releasing the assertion wrongly puts the Mac to sleep behind a locked
    /// screen and kills whatever was running — which is the exact thing the
    /// feature exists to prevent, happening at the exact moment nobody is
    /// there to notice. Holding it wrongly keeps a locked Mac awake slightly
    /// longer than it needed to be, and costs nothing.
    ///
    /// So nothing is ever released on a *timeout*, only on a positive sighting
    /// of an unlocked screen after a confirmed locked one. Failing to observe
    /// something is not evidence that it did not happen.
    public static func next(phase: Phase,
                            screenIsLocked: Bool,
                            armingElapsed: TimeInterval) -> Step {
        switch phase {
        case .arming:
            if screenIsLocked { return .nowHolding }
            return armingElapsed >= armingGrace ? .holdUnconfirmed : .keepWaiting
        case .holding:
            return screenIsLocked ? .keepWaiting : .release
        case .holdingUnconfirmed:
            // Nothing this loop can see is worth acting on any more. Release
            // comes from the unlock notification instead, and if that never
            // arrives the Mac stays awake — which is the harmless way to be
            // wrong. See the note on `holdingUnconfirmed`.
            return .keepWaiting
        }
    }
}
