import AppKit

/// The drawer's window.
///
/// Exists only to answer `canBecomeKey`. A `.borderless` window refuses key
/// status by default, and refuses it no matter how politely it is asked:
/// `makeKeyAndOrderFront` returns having done nothing, with no error and no
/// clue. SwiftUI's hover tracking is live only in the key window, so the drawer
/// came up looking perfectly normal and completely inert — no row highlight, no
/// underlined title.
///
/// Main is still declined. The panel is an accessory to whatever the user is
/// actually working in, and taking main would put it in the window menu and let
/// it own the menu bar, neither of which an agent app should do.
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
