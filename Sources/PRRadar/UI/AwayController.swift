import AppKit
import PRRadarCore
import SwiftUI

/// The away screen: PR Radar's own cover over every display, showing what is
/// still running while you are not at the desk.
///
/// **It has no way to dismiss itself, and that is the design.** Touch the
/// keyboard or the trackpad and the Mac locks for real; you come back in
/// through the login window. The cover's whole job is the thing a lock screen
/// cannot do — say, legibly from the doorway, that the work you walked away
/// from is still going — and the moment anybody interacts with it, that job is
/// over and the system's lock takes the screen.
///
/// It did once raise an in-app `LAContext` prompt instead, and that was a hole
/// rather than a convenience. The prompt had to out-rank a cover sitting at
/// the shielding level, so the cover dropped to an ordinary level while it was
/// up, and the focus sentry had to be suppressed so a legitimate prompt was not
/// mistaken for a bypass. Those two concessions overlapped: for the few seconds
/// of the prompt the cover was both out-ranked and unguarded, and anything
/// already on screen could be clicked straight through to the desktop.
///
/// Nothing was gained by it either. The login window takes Touch ID, the same
/// account password, Apple Watch unlock and a password manager — so handing the
/// screen straight to it costs a keystroke and closes the hole completely.
/// **PR Radar asks for nothing and sees nothing.**
@MainActor
final class AwayController {

    private var windows: [AwayWindow] = []
    /// What the app's menu bar and Dock looked like before kiosk mode, so it
    /// can be put back exactly rather than reset to a guess.
    private var restorePresentation: NSApplication.PresentationOptions?
    private var screenChange: NSObjectProtocol?
    private var feed: Task<Void, Never>?
    private var sentry: Task<Void, Never>?
    /// When the cover went up. Activation is not instant, so losing the front
    /// in the first moments is expected rather than suspicious.
    private var shownAt: Date?

    /// The cover is finished and the real lock should take the screen. Sent for
    /// a keypress, a click, or anything that got in front of us.
    var onEscalate: (() -> Void)?

    var isShowing: Bool { !windows.isEmpty }

    /// Whether a cover is up that the system lock should replace on the way out.
    var needsSystemLockOnExit: Bool { isShowing }

    /// Why this screen must not be put up, or nil.
    ///
    /// **Asked before anything is covered.** The cover's only exit is the
    /// system lock, so a Mac that cannot be locked is a Mac where covering the
    /// screen would produce something with no way past it. Checked up front
    /// rather than discovered at the first keystroke, because by then the
    /// damage is done.
    static func unavailableReason() -> String? {
        DeskLock.isAvailable()
            ? nil
            : "this version of macOS has no lock for the away screen to hand over to."
    }

    // MARK: - Putting it up

    func show(state: AppState) {
        guard windows.isEmpty else { return }

        for screen in NSScreen.screens {
            windows.append(AwayWindow(screen: screen, state: state, controller: self))
        }
        // Key so that keystrokes land here rather than in whatever was in
        // front, and active so the presentation options below apply to us.
        windows.first?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        enterKiosk()

        shownAt = Date()
        pollFeed(state: state)
        standGuard()

        // A display plugged in or unplugged while you are away would otherwise
        // leave a brand new screen showing the desktop, uncovered.
        screenChange = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self, weak state] _ in
            MainActor.assumeIsolated {
                guard let self, let state, self.isShowing else { return }
                self.rebuild(state: state)
            }
        }
    }

    /// Hides the Dock and menu bar and, most of the point, turns off
    /// Command-Tab.
    ///
    /// Not a boundary by itself — see `standGuard` for the part that matters —
    /// but it removes the two things that make a covered screen look like it is
    /// merely a window in front of a desktop.
    ///
    /// `disableForceQuit` is deliberately **not** included. It is the escape
    /// hatch left open on purpose, and it is no longer a bypass: quitting with
    /// a cover up locks the screen on the way out.
    private func enterKiosk() {
        restorePresentation = NSApp.presentationOptions
        // Only combinations Apple documents as valid — an invalid one raises,
        // and raising here would do it with the screen already covered.
        NSApp.presentationOptions = [.hideDock, .hideMenuBar,
                                     .disableProcessSwitching,
                                     .disableHideApplication]
    }

    private func rebuild(state: AppState) {
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        for screen in NSScreen.screens {
            windows.append(AwayWindow(screen: screen, state: state, controller: self))
        }
        windows.first?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Handing over

    /// A key, a click, a nudge of the trackpad. You are back, so the Mac locks.
    func interacted() {
        guard isShowing else { return }
        onEscalate?()
    }

    /// Watches for anything getting in front of the cover.
    ///
    /// **This is the answer to the hole that `disableProcessSwitching` cannot
    /// close.** Command-Space reaches Spotlight before any app sees the key,
    /// because system hotkeys are handled by the window server above all of
    /// them — and from Spotlight you can launch anything. Blocking that
    /// outright needs an event tap and the Input Monitoring permission that
    /// comes with it: a background app holding the permanent right to read
    /// every keystroke on the machine, to defend a screen it could instead
    /// simply lock.
    ///
    /// So the cover does not try to win that fight. It notices it has lost one
    /// — this app stopped being frontmost while a cover was up — and hands the
    /// screen to the system lock, which has no hole of this kind.
    ///
    /// There is no longer any state in which this is suppressed. That was the
    /// bug: while an in-app prompt was up the sentry stood down, and those were
    /// exactly the seconds in which the cover could be clicked past.
    ///
    /// Polled rather than taken from `didResignActive` alone, because a
    /// notification that does not arrive leaves the cover standing with the
    /// bypass open, and a question this cheap should not depend on being told.
    private func standGuard() {
        sentry?.cancel()
        sentry = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, self.isShowing else { return }
                if let shown = self.shownAt,
                   Date().timeIntervalSince(shown) < 1.5 { continue }
                guard !NSApp.isActive else { continue }
                Log.debug("away screen: lost the front — handing over to the system lock")
                self.onEscalate?()
                return
            }
        }
    }

    /// Takes the cover down.
    ///
    /// Never reports an unlock, because the cover has no unlock of its own: it
    /// comes down either on the way into the system lock or on the way out of
    /// the app, and in both cases the desk stays locked and the Mac stays held
    /// awake until the login window says otherwise.
    func takeDown() {
        guard isShowing else { return }
        feed?.cancel(); feed = nil
        sentry?.cancel(); sentry = nil
        if let screenChange {
            NotificationCenter.default.removeObserver(screenChange)
            self.screenChange = nil
        }
        for window in windows { window.orderOut(nil) }
        windows.removeAll()
        NSApp.presentationOptions = restorePresentation ?? []
        restorePresentation = nil
        shownAt = nil
    }

    // MARK: - The feed behind it

    /// Seconds between rescans. Four is under the threshold where a feed stops
    /// feeling live, and far above the one where it starts costing anything.
    static let feedInterval = 4

    /// Rescans the Claude sessions on a beat of its own.
    ///
    /// Slower than the view's one-second tick on purpose. The elapsed times
    /// have to advance every second to look like they are measuring anything;
    /// *which sessions exist* changes on the scale of a turn, and asking the
    /// filesystem sixty times a minute to find that out would be a cost paid
    /// against the very work this screen exists to protect.
    ///
    /// Read off the main actor: it is a directory scan plus a few hundred
    /// kilobytes of file, and doing that on the main thread would stutter the
    /// one animation on screen.
    private func pollFeed(state: AppState) {
        feed?.cancel()
        feed = Task { [weak self, weak state] in
            while !Task.isCancelled {
                let digest = await Task.detached(priority: .utility) {
                    ClaudeFeed.digest(ClaudeFeedReader.sessions())
                }.value
                guard !Task.isCancelled, let state else { return }
                state.claudeFeed = digest
                guard self != nil else { return }
                try? await Task.sleep(for: .seconds(AwayController.feedInterval))
            }
        }
    }
}

/// One cover, on one display.
///
/// A window rather than a full-screen `NSView` over the desktop because only a
/// window can take key status, and taking key status is what keeps keystrokes
/// out of whatever was in front when you walked away.
final class AwayWindow: NSWindow {

    private weak var controller: AwayController?

    init(screen: NSScreen, state: AppState, controller: AwayController) {
        self.controller = controller
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)
        // Above everything, and it never moves from here. The level used to
        // drop while an in-app prompt was up, which is precisely when the
        // cover could be clicked past.
        self.level = .init(rawValue: Int(CGShieldingWindowLevel()))
        // Every space, and not a window the system may cycle to or try to
        // tile: it is scenery that happens to be a window.
        self.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                   .fullScreenAuxiliary, .ignoresCycle]
        self.isOpaque = true
        self.backgroundColor = .black
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.setFrame(screen.frame, display: true)
        self.contentView = NSHostingView(
            rootView: AwayView(state: state) { [weak controller] in
                controller?.interacted()
            })
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Any key means you are back, and no key does anything else.
    ///
    /// Swallowed rather than passed on, and swallowed silently — the system
    /// beep on every keystroke would turn a cat on the keyboard into an alarm.
    override func keyDown(with event: NSEvent) {
        controller?.interacted()
    }

    /// Command shortcuts are key equivalents and never reach `keyDown`.
    /// Claiming them all is what stops Command-W, Command-Q and friends from
    /// being handled by the app behind this one.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        controller?.interacted()
        return true
    }

    override func mouseDown(with event: NSEvent) {
        controller?.interacted()
    }
}
