import AppKit
import SwiftUI
import PRRadarCore

/// Hosting view that moves and resizes the window from designated regions
/// while leaving clicks everywhere else to SwiftUI.
///
/// Drag tracking is explicit rather than delegated to `performDrag(with:)`:
/// that call returns immediately instead of blocking until mouse-up, so
/// comparing the pointer position around it reports every drag as a click.
/// `isMovableByWindowBackground` is no good either — SwiftUI's gesture
/// recognizers swallow the mouse-down it depends on.
final class DraggableHostingView<Content: View>: NSHostingView<Content> {

    typealias Zone = PressTracker.Zone

    /// Classifies a point in this view's coordinates (origin bottom-left).
    var zoneAt: (NSPoint) -> Zone = { _ in .move }
    var onClick: () -> Void = {}
    var onMoveFinished: () -> Void = {}
    /// Reports the window height the user is dragging towards.
    var onResize: (CGFloat) -> Void = { _ in }
    var onResizeFinished: () -> Void = {}
    var contextMenuProvider: () -> NSMenu? = { nil }

    /// Click-vs-drag decision lives in PRRadarCore so it can be unit-tested.
    private var tracker = PressTracker(threshold: 4)
    private var mouseDownLocation: NSPoint = .zero
    private var initialWindowFrame: NSRect = .zero

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    override func mouseDown(with event: NSEvent) {
        tracker.begin(zone: zoneAt(convert(event.locationInWindow, from: nil)))
        guard tracker.isTracking else {
            super.mouseDown(with: event)
            return
        }
        mouseDownLocation = NSEvent.mouseLocation
        initialWindowFrame = window?.frame ?? .zero
    }

    override func mouseDragged(with event: NSEvent) {
        guard tracker.isTracking, let window else {
            super.mouseDragged(with: event)
            return
        }

        let current = NSEvent.mouseLocation
        let dx = current.x - mouseDownLocation.x
        let dy = current.y - mouseDownLocation.y
        guard let zone = tracker.update(distance: hypot(dx, dy)) else { return }

        switch zone {
        case .move:
            // Deltas are measured from the press, so this stays stable even
            // though the window moves underneath the pointer.
            window.setFrameOrigin(NSPoint(x: initialWindowFrame.origin.x + dx,
                                          y: initialWindowFrame.origin.y + dy))
        case .resize:
            // The drawer's bottom edge is pinned, so dragging up grows it.
            onResize(initialWindowFrame.height + dy)
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        switch tracker.end() {
        case .ignored:
            super.mouseUp(with: event)
        case .click:
            onClick()
        case .moved:
            onMoveFinished()
        case .resized:
            onResizeFinished()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = contextMenuProvider() else {
            super.rightMouseDown(with: event)
            return
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Cursor feedback

    override func resetCursorRects() {
        super.resetCursorRects()
        // Advertise the resizable edge. Sampling the zone classifier keeps
        // this in step with wherever the resize strip currently is. The view
        // is flipped, so the visual top is minY rather than maxY.
        let thickness: CGFloat = 6
        let topY = isFlipped ? bounds.minY : bounds.maxY - thickness
        let probe = NSPoint(x: bounds.midX,
                           y: isFlipped ? bounds.minY + 2 : bounds.maxY - 2)
        guard zoneAt(probe) == .resize else { return }
        addCursorRect(NSRect(x: bounds.minX, y: topY,
                             width: bounds.width, height: thickness),
                      cursor: .resizeUpDown)
    }
}
