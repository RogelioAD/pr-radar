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
    /// Thickness of the resize strip. Supplied by the owner so the cursor
    /// region and the drag region cannot drift apart.
    var resizeEdgeThickness: CGFloat = 12
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
    /// Cursor state, tracked rather than pushed. `NSCursor.push()`/`pop()`
    /// leaves the pointer stuck as a fist system-wide if a release is ever
    /// missed; `set()` has no stack to unbalance.
    private var hoveringResizeEdge = false
    private var draggingResizeEdge = false
    private var resizeTrackingArea: NSTrackingArea?

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

        if zone == .resize, !draggingResizeEdge {
            draggingResizeEdge = true
            applyCursor()
        }

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
        draggingResizeEdge = false
        applyCursor()
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

    /// Up/down arrows over the resizable edge: they read as "resize", where a
    /// hand reads as "move". `frameResize` is the clean pair with no bar
    /// through the middle; `resizeUpDown` is the pre-macOS-15 fallback.
    private var resizeCursor: NSCursor {
        if #available(macOS 15.0, *) {
            return NSCursor.frameResize(position: .top, directions: .all)
        }
        return .resizeUpDown
    }

    /// Tracking area rather than `addCursorRect`: cursor rects only take effect
    /// while the window is active, and this is a non-activating floating panel,
    /// so they never fired. `.activeAlways` works regardless.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = resizeTrackingArea {
            removeTrackingArea(existing)
            resizeTrackingArea = nil
        }

        let thickness = resizeEdgeThickness
        let probe = NSPoint(x: bounds.midX,
                           y: isFlipped ? bounds.minY + 2 : bounds.maxY - 2)
        guard zoneAt(probe) == .resize else { return }

        // The view is flipped, so the visual top is minY rather than maxY.
        let topY = isFlipped ? bounds.minY : bounds.maxY - thickness
        let area = NSTrackingArea(
            rect: NSRect(x: bounds.minX, y: topY,
                         width: bounds.width, height: thickness),
            // .mouseMoved matters: .cursorUpdate alone only fires on entry, so
            // anything that reset the cursor while the pointer was still
            // inside won until it left and re-entered — which is why the
            // arrows appeared only sometimes.
            options: [.mouseEnteredAndExited, .mouseMoved,
                      .cursorUpdate, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        resizeTrackingArea = area
    }

    /// Enter and exit say only that *a* tracking area was crossed, not which.
    /// Every `.onHover` in the drawer installs one owned by this same view, so
    /// hovering any row delivers an enter here — which used to be taken as
    /// "the pointer reached the resize strip" and raised the arrows with the
    /// pointer hundreds of points away. Re-laying out the rows, as changing a
    /// filter does, installs a fresh crop of them and did it every time.
    ///
    /// So the pointer's actual position decides, and the event only prompts
    /// the question.
    override func mouseEntered(with event: NSEvent) {
        updateEdgeHover(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateEdgeHover(with: event)
    }

    private func updateEdgeHover(with event: NSEvent) {
        let inside = zoneAt(convert(event.locationInWindow, from: nil)) == .resize
        guard inside != hoveringResizeEdge else { return }
        hoveringResizeEdge = inside
        applyCursor()
    }

    /// Reasserts the cursor on every move inside the strip, so it cannot be
    /// left as whatever something else set.
    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let inside = zoneAt(local) == .resize
        if inside != hoveringResizeEdge {
            hoveringResizeEdge = inside
        }
        if inside { applyCursor() }
        super.mouseMoved(with: event)
    }

    /// Called by AppKit when the pointer enters a `.cursorUpdate` area — the
    /// supported hook for asserting a cursor, and it reasserts after anything
    /// else changes it.
    override func cursorUpdate(with event: NSEvent) {
        applyCursor()
    }

    private func applyCursor() {
        if draggingResizeEdge {
            NSCursor.closedHand.set()
        } else if hoveringResizeEdge {
            resizeCursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// Last resort: leaving the window mid-drag means no mouse-up arrives, so
    /// put the pointer back rather than leaving it a fist.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            hoveringResizeEdge = false
            draggingResizeEdge = false
            NSCursor.arrow.set()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
