import AppKit
import SwiftUI
import PRRadarCore

/// Hosting view that moves and resizes the window from designated regions
/// while leaving clicks everywhere else to SwiftUI.
///
/// Two handles live here, and they are deliberately different shapes: the
/// expanded drawer has one horizontal strip along its top edge that changes its
/// height, and the collapsed badge has a grip at each of its four corners that
/// changes its size as a square. Which one is in play is decided entirely by
/// `zoneAt`, so this view never has to know whether the panel is a badge or a
/// drawer.
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
    /// Reports a corner grip and the pointer's travel since the press, in
    /// screen coordinates. Raw on purpose: what a given travel means for the
    /// badge's size is the owner's rule, not this view's — the same division of
    /// labour `onResize` already uses.
    var onCornerDrag: (BadgeCorner, CGPoint) -> Void = { _, _ in }
    var onCornerDragFinished: () -> Void = {}
    /// The region whose corners are grips — the badge's *art*, which is a good
    /// deal smaller than the panel carrying it — or nil when the panel has no
    /// grips at all. Supplied by the owner for the same reason
    /// `resizeEdgeThickness` is: the cursor region and the drag region must not
    /// be able to drift apart.
    var cornerGripRegion: () -> NSRect? = { nil }
    /// Given the press location, so the owner can decide whether this part of
    /// the drawer has a menu of its own.
    var contextMenuProvider: (NSPoint) -> NSMenu? = { _ in nil }

    /// Click-vs-drag decision lives in PRRadarCore so it can be unit-tested.
    private var tracker = PressTracker(threshold: 4)
    private var mouseDownLocation: NSPoint = .zero
    private var initialWindowFrame: NSRect = .zero
    /// Cursor state, tracked rather than pushed. `NSCursor.push()`/`pop()`
    /// leaves the pointer stuck as a fist system-wide if a release is ever
    /// missed; `set()` has no stack to unbalance.
    ///
    /// A zone rather than a pair of booleans: there are two kinds of handle now
    /// and a third would have meant a third flag to keep in step with the other
    /// two.
    private var hoverZone: Zone = .none
    /// The handle a drag started on, or nil — including during a plain window
    /// move, which has no cursor of its own.
    private var draggingHandle: Zone?
    private var cursorTrackingArea: NSTrackingArea?

    required init(rootView: Content) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("not supported")
    }

    /// Without this the first click on an inactive panel is spent activating
    /// it and never reaches the view, so opening the drawer took two clicks —
    /// one to wake the window, one to be heard.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

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

        if draggingHandle == nil, cursor(for: zone) != nil {
            draggingHandle = zone
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
        case .corner(let corner):
            // Measured from the press for the same reason as a move: the badge
            // is being re-framed under the pointer on every one of these.
            onCornerDrag(corner, CGPoint(x: dx, y: dy))
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        draggingHandle = nil
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
        case .sized:
            onCornerDragFinished()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Handing the event on is what lets a SwiftUI .contextMenu underneath
        // be seen at all: popping a menu here consumes the press, which is why
        // the rows' own menus never appeared.
        guard let menu = contextMenuProvider(convert(event.locationInWindow, from: nil)) else {
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

    /// The diagonal pair for a badge corner.
    ///
    /// There is no public diagonal cursor before macOS 15 — the ones the window
    /// server uses for window corners are private — so below it the crosshair
    /// stands in. It reads as "take hold of this point", which is the honest
    /// approximation, and it is at least unmistakably not the arrow.
    private func cornerCursor(_ corner: BadgeCorner) -> NSCursor {
        if #available(macOS 15.0, *) {
            let position: NSCursor.FrameResizePosition
            switch corner {
            case .topLeft: position = .topLeft
            case .topRight: position = .topRight
            case .bottomLeft: position = .bottomLeft
            case .bottomRight: position = .bottomRight
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
        return .crosshair
    }

    /// nil for the zones this view has no opinion about, which is what leaves
    /// SwiftUI free to pick its own cursor everywhere else.
    private func cursor(for zone: Zone) -> NSCursor? {
        switch zone {
        case .resize: return resizeCursor
        case .corner(let corner): return cornerCursor(corner)
        case .move, .none: return nil
        }
    }

    /// Tracking area rather than `addCursorRect`: cursor rects only take effect
    /// while the window is active, and this is a non-activating floating panel,
    /// so they never fired. `.activeAlways` works regardless.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = cursorTrackingArea {
            removeTrackingArea(existing)
            cursorTrackingArea = nil
        }
        // The geometry just moved, possibly out from under a pointer that never
        // budged. Enter and exit cannot report that — no event is owed when the
        // window moves rather than the mouse — so settle the state from the
        // pointer itself instead of waiting to be told.
        defer { refreshHoverZone() }

        guard let rect = cursorTrackingRect() else { return }
        let area = NSTrackingArea(
            rect: rect,
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
        cursorTrackingArea = area
    }

    /// The region whose cursor this view is responsible for, or nil when it
    /// owns none of the surface.
    ///
    /// The badge's art is taken whole rather than as four corner rects: the
    /// resolving is done from the pointer's position anyway (see
    /// `refreshHoverZone`), so four areas would be four times the bookkeeping
    /// and not one answer more correct.
    private func cursorTrackingRect() -> NSRect? {
        if let grips = cornerGripRegion() {
            // Handed to us in visual coordinates; a flipped view already agrees.
            return isFlipped
                ? grips
                : NSRect(x: grips.minX, y: bounds.height - grips.maxY,
                         width: grips.width, height: grips.height)
        }
        // The view is flipped, so the visual top is minY rather than maxY.
        let visualTopY = isFlipped ? bounds.minY + 2 : bounds.maxY - 2
        guard zoneAt(NSPoint(x: bounds.midX, y: visualTopY)) == .resize else { return nil }
        let thickness = resizeEdgeThickness
        let topY = isFlipped ? bounds.minY : bounds.maxY - thickness
        return NSRect(x: bounds.minX, y: topY, width: bounds.width, height: thickness)
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
        updateHoverZone(with: event)
        // Handed on, always. SwiftUI drives .onHover from these very events, so
        // an override that keeps them to itself silently disables every hover
        // in the drawer — no row highlight, no underlined title — while the
        // resize cursor this override exists for goes on working. The badge's
        // mascot wakes on hover through the same path.
        super.mouseEntered(with: event)
    }

    override func mouseExited(with event: NSEvent) {
        updateHoverZone(with: event)
        super.mouseExited(with: event)
    }

    /// Re-derives the hovered zone from where the pointer actually is, for the
    /// cases no mouse event covers: switching tabs or changing a filter resizes
    /// the drawer around a still pointer, and resizing the badge moves its own
    /// corners out from under the hand — the answer can change without the
    /// mouse having moved at all.
    func refreshHoverZone() {
        guard draggingHandle == nil, let window else { return }
        let local = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHoverZone(bounds.contains(local) ? zoneAt(local) : .none)
    }

    private func updateHoverZone(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        setHoverZone(bounds.contains(local) ? zoneAt(local) : .none)
    }

    private func setHoverZone(_ zone: Zone) {
        guard zone != hoverZone else { return }
        hoverZone = zone
        applyCursor()
    }

    /// Reasserts the cursor on every move inside a handle, so it cannot be
    /// left as whatever something else set.
    override func mouseMoved(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        let zone = bounds.contains(local) ? zoneAt(local) : .none
        setHoverZone(zone)
        if cursor(for: zone) != nil { applyCursor() }
        super.mouseMoved(with: event)
    }

    /// Called by AppKit when the pointer enters a `.cursorUpdate` area — the
    /// supported hook for asserting a cursor, and it reasserts after anything
    /// else changes it.
    override func cursorUpdate(with event: NSEvent) {
        // Only claim the cursor on the handles this view is responsible for;
        // anywhere else SwiftUI should be free to pick its own.
        guard draggingHandle != nil || cursor(for: hoverZone) != nil else {
            super.cursorUpdate(with: event)
            return
        }
        applyCursor()
    }

    private func applyCursor() {
        if draggingHandle != nil {
            // A closed fist for every handle, so hovering and grabbing never
            // look the same — whichever of them was grabbed.
            NSCursor.closedHand.set()
        } else if let cursor = cursor(for: hoverZone) {
            cursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// Last resort: leaving the window mid-drag means no mouse-up arrives, so
    /// put the pointer back rather than leaving it a fist.
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil {
            hoverZone = .none
            draggingHandle = nil
            NSCursor.arrow.set()
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
