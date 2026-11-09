import AppKit
import PRRadarCore

/// Locks the desk, and lets the Mac sleep again once you are back.
///
/// The fourth coordinator and much the smallest. `AutoReviewCoordinator` posts
/// under your name and `LensCoordinator` spends money; this one changes nothing
/// anywhere and is over in a second — but it is the only one that takes the
/// whole screen away, so the care goes somewhere different. Three rules:
///
/// - **Awake first, lock second.** In the other order there is a gap between
///   the screen going and the assertion landing, and idle sleep is entitled to
///   fire in it. Cheap to get right, invisible to get wrong, and the symptom
///   would be a run that died "sometimes".
/// - **A failed lock leaves nothing behind.** If the screen does not actually
///   go, the assertion is released immediately. Holding a Mac awake in an
///   unlocked room is the worst of the three available outcomes, and it would
///   have been arrived at by pressing a button marked *lock*.
/// - **The assertion is released by watching, not by being told.** See
///   `DeskLockWatch`: on the hard path the loop asks the window server whether
///   the screen is still locked, so there is no notification whose non-arrival
///   would leave this Mac permanently unable to sleep. On the away screen the
///   dismissal is ours and arrives directly.
@MainActor
final class DeskLockCoordinator {

    private let state: AppState
    private let awake = StayAwake()
    private var watch: Task<Void, Never>?
    private let away = AwayController()
    /// Live only during an unconfirmed hold. See `listenForUnlock`.
    private var unlockObserver: NSObjectProtocol?

    init(state: AppState) {
        self.state = state
        // The cover has no unlock of its own. Everything it can do ends in
        // the system lock, so this is its only callback.
        away.onEscalate = { [weak self] in self?.escalate() }
    }

    /// `hard` is the system lock. The default is the away screen.
    ///
    /// Both halves of the promise are the same either way — the Mac is held
    /// awake and the password is the system's business — and what differs is
    /// only how hard the cover is to get past, and whether it can tell you
    /// anything while it is up.
    func lock(hard: Bool) {
        guard !awake.isHeld else { return }
        state.deskLockError = nil

        // Before the screen goes, in both paths. Begun the other way round
        // there is a gap for idle sleep to fire in.
        //
        // The away screen also holds the *display* on: it exists to be read
        // from the doorway, and one that goes dark after ten minutes is not
        // only useless but indistinguishable, from across a room, from a Mac
        // that has slept and taken the work with it.
        awake.begin(display: !hard)

        if !hard {
            // Never cover a screen this app cannot uncover again. See
            // `AwayController.unavailableReason`.
            if let why = AwayController.unavailableReason() {
                failed(why)
                return
            }
            if away.show(state: state) {
                Log.debug("away screen up; holding the system awake")
                return
            }
            // There was no display to cover — every one asleep, or a clamshell
            // whose external screen has gone. Falls through to the system lock
            // rather than returning: an uncovered Mac held awake is the one
            // outcome worse than either lock, and the button that produced it
            // was marked with a padlock. The display goes back to its normal
            // timeout on the way, since there is now nothing to read.
            Log.debug("no display to cover; using the system lock instead")
            awake.begin(display: false)
        }

        do {
            try DeskLock.lock()
        } catch {
            failed(error.localizedDescription)
            return
        }

        Log.debug("desk locked; holding the system awake")
        watchUntilUnlocked()
    }

    /// Something got past the away screen, so the real lock takes over.
    ///
    /// The cover comes down **without** reporting an unlock: the Mac stays held
    /// awake and the desk stays locked, because neither of those things has
    /// stopped being true — only the cover doing the work has changed. What
    /// this converts is a deterrent into a boundary, at the moment somebody
    /// shows they needed one.
    ///
    /// Unlocking is then the login window's business, exactly as an
    /// Option-click would have been, and the watch loop takes over the job of
    /// noticing you came back.
    func escalate() {
        guard awake.isHeld else { return }
        away.takeDown()
        // Nothing left on screen worth reading, so the display is released
        // back to its normal timeout. The system stays held awake, which is
        // the half that keeps the work alive.
        awake.begin(display: false)
        do {
            try DeskLock.lock()
            Log.debug("escalated to the system lock")
            watchUntilUnlocked()
        } catch {
            // Nothing to fall back to: the cover is down and the system lock
            // refused. Say so rather than leaving a Mac that looks locked and
            // is not.
            failed(error.localizedDescription)
        }
    }

    /// Locks for real on the way out, if a cover is up.
    ///
    /// Quitting with the away screen showing — Force Quit, a `pkill`, an
    /// installer replacing this build — would otherwise take the cover down
    /// and leave the desktop open on an unattended Mac. Any exit this app is
    /// told about ends with the screen genuinely locked instead.
    ///
    /// A kill that runs no code cannot be caught, and that is the honest limit
    /// of this: it closes every exit the app is asked to make, not every exit
    /// there is.
    func lockOnExitIfCovered() {
        guard away.needsSystemLockOnExit else { return }
        away.takeDown()
        awake.begin(display: false)
        try? DeskLock.lock()
        Log.debug("quitting with a cover up — locked the screen on the way out")
    }

    /// Polls the real lock state and acts on what `DeskLockWatch` makes of it.
    ///
    /// A task rather than a `Timer` so that it is cancelled with the app, and
    /// so the arming and holding phases read as the one sequence they are.
    private func watchUntilUnlocked() {
        watch?.cancel()
        let began = Date()
        watch = Task { [weak self] in
            var phase = DeskLockWatch.Phase.arming
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DeskLockWatch.interval))
                guard let self, !Task.isCancelled else { return }

                let step = DeskLockWatch.next(
                    phase: phase,
                    screenIsLocked: ScreenLock.isLocked(),
                    armingElapsed: Date().timeIntervalSince(began))

                switch step {
                case .keepWaiting:
                    continue
                case .nowHolding:
                    phase = .holding
                case .release:
                    Log.debug("desk unlocked; letting the Mac sleep again")
                    self.release()
                    return
                case .holdUnconfirmed:
                    // The lock call succeeded and the window server never
                    // admitted it. The Mac stays awake — see the bias note on
                    // `DeskLockWatch.next`. Releasing here is what would kill
                    // a session behind a screen that is, almost certainly,
                    // locked exactly as asked.
                    Log.debug("desk lock unconfirmed; holding the Mac awake anyway")
                    phase = .holdingUnconfirmed
                    self.listenForUnlock()
                }
            }
        }
    }

    /// Unwinds everything the press set up, and says why.
    ///
    /// The error goes on `AppState` rather than into a banner because the only
    /// person who can see it is standing at an unlocked Mac wondering why
    /// nothing happened — the button they just pressed is the right place to
    /// find the answer, and it is still on screen.
    private func failed(_ reason: String) {
        release()
        state.deskLockError = reason
        Log.debug("desk lock failed: \(reason)")
    }

    /// The only way out of an unconfirmed hold.
    ///
    /// Subscribed to rather than polled because polling is precisely what has
    /// already proved unreliable in this state. If this never arrives the Mac
    /// stays awake until PR Radar quits, which is the harmless way to be
    /// wrong: a Mac awake longer than it needed costs some battery, a Mac
    /// asleep too early costs the work that was running on it.
    private func listenForUnlock() {
        guard unlockObserver == nil else { return }
        unlockObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                Log.debug("unlock notification arrived; letting the Mac sleep again")
                self?.release()
            }
        }
    }

    /// Hands the Mac back its normal sleep behaviour. Safe to reach twice.
    ///
    /// Takes the away screen down too, so that a failure on the hard path
    /// cannot leave a cover up with nothing holding the Mac awake behind it.
    private func release() {
        watch?.cancel()
        watch = nil
        if let unlockObserver {
            DistributedNotificationCenter.default().removeObserver(unlockObserver)
            self.unlockObserver = nil
        }
        away.takeDown()
        awake.end()
    }
}
