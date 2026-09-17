import AppKit
import SwiftUI
import PRRadarCore

/// Owns the floating panel: its position, its badge/drawer sizing, the
/// user-resizable drawer height, and click-outside-to-collapse.
@MainActor
final class PanelController {
    let panel: FloatingPanel
    private let state: AppState
    private var hostingView: DraggableHostingView<RootView>!
    private var outsideClickMonitor: Any?
    private var activationObservers: [Any] = []

    /// Source of truth for position: the badge's rect in screen coordinates.
    /// The expanded drawer is laid out relative to this, so collapsing always
    /// returns the badge to exactly where the user left it.
    private var badgeFrame: NSRect

    /// Where the header's controls are, reported by the view layer. The header
    /// is the drag handle, so without these a press on the update chip or the
    /// collapse button would be taken as a window drag and never reach it.
    private var headerControls: [CGRect] = []

    /// Height the user is dragging towards, live during a resize.
    private var resizeDraft: CGFloat?
    /// Set while the window is travelling between the badge and the drawer.
    /// Layout requests arriving mid-flight would retarget it and fight the
    /// animation, and a second toggle would start a competing one.
    private var isAnimatingFrame = false

    /// True only between mouse-down and mouse-up on the resize edge. While
    /// set, heights are clamped but not snapped, so the edge follows the
    /// pointer instead of jumping row to row.
    private var isDraggingHeight = false

    var onOpen: (ReviewItem) -> Void = { _ in }
    var onOpenMyPR: (MyPullRequest) -> Void = { _ in }
    var onRefresh: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }

    init(state: AppState) {
        self.state = state
        self.badgeFrame = Self.initialBadgeFrame()

        panel = FloatingPanel(
            contentRect: badgeFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // shadows are drawn in SwiftUI
        panel.isFloatingPanel = true
        // Deliberately false. It reads like the cautious choice for a panel
        // that must not steal focus, but it refuses key status unless a view
        // wants text input — so the makeKeyAndOrderFront below never took, and
        // SwiftUI's hover tracking, which is live only in the key window, never
        // fired. No row highlighted and no title underlined. The resize cursor
        // was unaffected only because that tracking area is .activeAlways.
        //
        // Nothing here grabs focus on its own regardless: the badge is shown
        // with orderFrontRegardless, and the panel is made key only when the
        // drawer is deliberately opened.
        panel.becomesKeyOnlyIfNeeded = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.animationBehavior = .none
        // Without this the tracking area never receives mouseMoved, so the
        // cursor could not be reasserted while the pointer sat on the strip.
        panel.acceptsMouseMovedEvents = true

        let root = RootView(
            state: state,
            onOpen: { [weak self] in self?.onOpen($0) },
            onOpenMyPR: { [weak self] in self?.onOpenMyPR($0) },
            onCollapse: { [weak self] in self?.setExpanded(false) },
            onRefresh: { [weak self] in self?.onRefresh() },
            onRowHeights: { [weak self] in self?.adoptRowHeights($0) },
            onSelectTab: { [weak self] in self?.selectTab($0) },
            onHeaderControls: { [weak self] in self?.headerControls = $0 }
        )
        hostingView = DraggableHostingView(rootView: root)
        hostingView.zoneAt = { [weak self] point in self?.zone(at: point) ?? .move }
        hostingView.resizeEdgeThickness = Layout.resizeEdge
        hostingView.onMoveFinished = { [weak self] in self?.persistPosition() }
        hostingView.onResize = { [weak self] in self?.previewResize(to: $0) }
        hostingView.onResizeFinished = { [weak self] in self?.commitResize() }
        hostingView.onClick = { [weak self] in
            guard let self else { return }
            // A press on the resize edge that never moved: clear the drag flag
            // before treating it as a click, or layout would stay unsnapped.
            self.isDraggingHeight = false
            // Only the badge opens on a click. The expanded drawer's header is
            // for dragging the window, and closing belongs to the × in it —
            // a stray click while repositioning used to shut the drawer.
            guard !self.state.expanded else { return }
            self.setExpanded(true)
        }
        hostingView.contextMenuProvider = { [weak self] point in
            guard let self else { return nil }
            // Below the header the rows own the right-click — each carries its
            // own Open and Copy items. The app menu stays where it has always
            // been reachable: the collapsed badge, and the drawer's header.
            if self.state.expanded, self.zone(at: point) == .none { return nil }
            return self.menuProvider()
        }
        panel.contentView = hostingView

        observeActivation()
        applyFrame()
    }

    /// Hover only works while the panel is key, and a panel is only key while
    /// its app is active. Losing active status therefore leaves an open drawer
    /// looking normal but completely inert — no row highlights, no underlined
    /// titles — which is what a machine waking from sleep produces.
    ///
    /// Clicking outside already collapses the drawer, so treating any loss of
    /// active status the same way keeps one rule rather than two. Becoming
    /// active again re-takes key, for the paths that do not go through a
    /// collapse at all.
    private func observeActivation() {
        let centre = NotificationCenter.default
        activationObservers = [
            centre.addObserver(forName: NSApplication.didResignActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    Log.debug("app resigned active (expanded=\(self?.state.expanded ?? false))")
                    self?.setExpanded(false)
                }
            },
            centre.addObserver(forName: NSApplication.didBecomeActiveNotification,
                               object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.state.expanded else { return }
                    self.panel.makeKeyAndOrderFront(nil)
                    Log.debug("app became active; re-keyed "
                              + "(key=\(self.panel.isKeyWindow))")
                }
            },
        ]
    }

    deinit {
        activationObservers.forEach(NotificationCenter.default.removeObserver)
    }

    // MARK: - Visibility

    func show() {
        guard !state.shouldHidePanel else {
            hide()
            return
        }
        if !panel.isVisible { panel.orderFrontRegardless() }
        applyFrame()
    }

    func hide() {
        if state.expanded { setExpanded(false) }
        panel.orderOut(nil)
    }

    func syncVisibility() {
        state.shouldHidePanel ? hide() : show()
    }

    // MARK: - Expand / collapse

    func toggle() { setExpanded(!state.expanded) }

    func setExpanded(_ expanded: Bool) {
        guard state.expanded != expanded, !isAnimatingFrame else { return }
        expanded ? expand() : collapse()
    }

    /// Unfolds the drawer out of the badge.
    ///
    /// The state flips first so the drawer is being drawn while the window
    /// grows, which is what makes the travel visible at all — an empty window
    /// changing size shows nothing.
    private func expand() {
        state.expanded = true
        // A non-activating panel would otherwise leave the rows unclickable,
        // and a borderless one only takes key because FloatingPanel allows it.
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitor()
        animate(to: targetFrame(), curve: .easeOut) { [weak self] in
            guard let self else { return }
            // Hover is live only in the key window of an active app, so these
            // two flags are the difference between a working drawer and an
            // inert one that looks identical.
            Log.debug("expanded: appActive=\(NSApp.isActive) key=\(self.panel.isKeyWindow)")
            self.logZoneMap()
        }
    }

    /// Folds the drawer back into the badge.
    ///
    /// The state flip waits for the travel to finish, for the same reason in
    /// reverse: swapping to the badge first leaves an empty transparent window
    /// animating, so the drawer appears to vanish instead of collapsing.
    ///
    /// The badge is the drawer's own bottom-right corner, so the two frames
    /// interpolate directly with nothing faked in between.
    private func collapse() {
        removeOutsideClickMonitor()
        animate(to: badgeFrame, curve: .easeIn) { [weak self] in
            guard let self else { return }
            self.state.expanded = false
            self.applyFrame()
        }
    }

    private func animate(to frame: NSRect,
                         curve: CAMediaTimingFunctionName,
                         then finish: @escaping () -> Void) {
        isAnimatingFrame = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: curve)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.isAnimatingFrame = false
            finish()
            self.hostingView.updateTrackingAreas()
            self.hostingView.refreshEdgeHover()
        })
    }

    // MARK: - Geometry

    /// The screen the panel is on caps the drawer; past that the list scrolls.
    private var availableMaxHeight: CGFloat {
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) }
            ?? NSScreen.main
        return Layout.maxHeight(on: screen)
    }

    private var drawerHeight: CGFloat {
        Layout.drawerHeight(rowHeights: state.activeRowHeights,
                            itemCount: state.activeRowCount,
                            userContentHeight: state.userContentHeight,
                            maxHeight: availableMaxHeight,
                            snapping: !isDraggingHeight,
                            tab: state.selectedTab)
    }

    /// The drawer grows up and to the left, keeping the badge's bottom-right
    /// corner visually pinned where the user parked it.
    private func targetFrame() -> NSRect {
        guard state.expanded else { return badgeFrame }
        let raw = NSRect(
            x: badgeFrame.maxX - Layout.drawerWidth,
            y: badgeFrame.minY,
            width: Layout.drawerWidth,
            height: drawerHeight
        )
        return clamp(raw)
    }

    private func applyFrame(animated: Bool = false, duration: TimeInterval = 0.16) {
        let frame = targetFrame()
        guard animated, panel.isVisible else {
            panel.setFrame(frame, display: true)
            return
        }
        // Smooths the jump when switching tabs, and the settle after a resize.
        // Never used mid-drag: animating towards a target the pointer is still
        // moving would lag behind the cursor.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            // The drawer has finished travelling; whatever is under the pointer
            // now is the answer, whether or not the pointer moved to get there.
            self?.hostingView.refreshEdgeHover()
        })
    }

    private static let zones = DrawerZones(headerHeight: Layout.headerHeight,
                                           resizeEdge: Layout.resizeEdge)

    /// Classifies a point for the drag handler. Only the drawer's top edge
    /// resizes and only its header moves; everywhere else belongs to SwiftUI
    /// so rows, menus and the footer buttons stay clickable.
    ///
    /// `NSHostingView` is flipped, so its y grows downward — the conversion to
    /// a distance-from-top is what keeps the zones the right way up.
    private func zone(at point: NSPoint) -> DraggableHostingView<RootView>.Zone {
        guard state.expanded else { return .move }
        let distance = DrawerZones.distanceFromTop(
            pointY: point.y,
            viewHeight: hostingView.bounds.height,
            isFlipped: hostingView.isFlipped
        )
        // Always resizable: the handle is shown unconditionally now.
        return Self.zones.zone(distanceFromTop: distance,
                               distanceFromLeft: point.x,
                               canResize: true,
                               controls: headerControls)
    }

    /// Dumps what a press at each part of the real, laid-out drawer would do.
    /// Cheap insurance against the coordinate flip silently inverting again.
    private func logZoneMap() {
        guard Log.enabled else { return }
        let height = hostingView.bounds.height
        let probes: [(String, CGFloat)] = [
            ("grab edge (visual top)", 2),
            ("header", Layout.headerHeight / 2),
            ("filter bar", Layout.headerHeight + Layout.filterBarHeight / 2),
            ("first row", Layout.headerHeight + Layout.filterBarHeight + 30),
            ("footer / Refresh", height - Layout.footerHeight / 2),
        ]
        Log.debug("zone map (flipped=\(hostingView.isFlipped) height=\(height) "
                  + "rows=\(state.activeRowCount) max=\(availableMaxHeight)):")
        for (label, visualY) in probes {
            // Probes are expressed as distance from the visual top; convert
            // back into view space before asking the classifier.
            let pointY = hostingView.isFlipped ? visualY : height - visualY
            let zone = zone(at: NSPoint(x: Layout.drawerWidth / 2, y: pointY))
            Log.debug("   \(label): \(zone)")
        }
        // Each header control probed through the same path a real press takes.
        // These must read `.none`: a control the drag band still owns never
        // sees its click. Absent rects mean the preference never arrived, which
        // looks identical from the outside.
        for rect in headerControls {
            let pointY = hostingView.isFlipped ? rect.midY : height - rect.midY
            let zone = zone(at: NSPoint(x: rect.midX, y: pointY))
            Log.debug("   control \(rect.integral): \(zone)")
        }
        if headerControls.isEmpty { Log.debug("   control rects: none reported") }
    }

    private func persistPosition() {
        // When expanded, the badge's notional spot is the drawer's bottom-right.
        let frame = panel.frame
        badgeFrame = clamp(NSRect(
            x: frame.maxX - Layout.badgeWidth,
            y: frame.minY,
            width: Layout.badgeWidth,
            height: Layout.badgeHeight
        ))
        Prefs.badgeOrigin = badgeFrame.origin
    }

    // MARK: - Resizing

    /// Live feedback while dragging the top edge.
    ///
    /// Follows the pointer one-to-one, clamped but not snapped. Snapping every
    /// frame made the drag lurch between rows rather than track the hand.
    private func previewResize(to windowHeight: CGFloat) {
        isDraggingHeight = true
        let content = Layout.sizing(for: state.selectedTab).clamp(
            windowHeight - Layout.chromeHeight,
            rowHeights: state.activeRowHeights,
            itemCount: state.activeRowCount,
            limit: availableMaxHeight - Layout.chromeHeight
        )
        resizeDraft = content
        state.userContentHeight = content
        applyFrame()
    }

    /// On release, settle onto the nearest row edge — animated, so it glides
    /// into place instead of popping.
    private func commitResize() {
        isDraggingHeight = false
        guard let draft = resizeDraft else { return }
        resizeDraft = nil

        let snapped = Layout.sizing(for: state.selectedTab).snap(
            draft,
            rowHeights: state.activeRowHeights,
            itemCount: state.activeRowCount,
            limit: availableMaxHeight - Layout.chromeHeight
        )
        state.userContentHeight = snapped
        Prefs.setDrawerContentHeight(snapped, for: state.selectedTab)
        // The edge jumps to the nearest row on release; .alignment is the
        // system feedback for exactly that, and on a trackpad it makes the snap
        // felt rather than only seen.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // A touch slower than a tab switch: this is a settle, and the travel
        // is at most half a row, so a quick snap reads as a jolt.
        applyFrame(animated: true, duration: 0.22)
    }

    private func adoptRowHeights(_ heights: [String: CGFloat]) {
        guard !heights.isEmpty else { return }
        let changed = heights.contains { key, value in
            guard let existing = state.rowHeights[key] else { return true }
            return abs(existing - value) >= 1
        }
        guard changed else { return }
        state.rowHeights.merge(heights) { _, new in new }
        if state.expanded, !isAnimatingFrame { applyFrame() }
    }

    /// Re-lays out an open drawer after the list changes.
    func refreshLayoutIfExpanded() {
        if state.expanded, !isAnimatingFrame { applyFrame() }
    }

    /// Switching tabs changes which rows — and so which measured heights — are
    /// in play, so the frame is recomputed even though the width is fixed.
    func selectTab(_ tab: DrawerTab) {
        guard state.selectedTab != tab else { return }
        state.selectedTab = tab
        applyFrame(animated: true)
        hostingView.updateTrackingAreas()
        hostingView.refreshEdgeHover()
    }

    // MARK: - Screen fitting

    /// Keeps the panel on a visible screen — a resolution change or an
    /// unplugged monitor must not strand it offscreen.
    private func clamp(_ rect: NSRect) -> NSRect {
        let screen = NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return rect }
        var result = rect
        result.size.height = min(result.height, visible.height)
        result.origin.x = min(max(rect.minX, visible.minX), visible.maxX - result.width)
        result.origin.y = min(max(rect.minY, visible.minY), visible.maxY - result.height)
        return result
    }

    private static func initialBadgeFrame() -> NSRect {
        let width = Layout.badgeWidth, height = Layout.badgeHeight
        if let saved = Prefs.badgeOrigin {
            return NSRect(x: saved.x, y: saved.y, width: width, height: height)
        }
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        return NSRect(
            x: visible.maxX - width - Layout.screenInset,
            y: visible.minY + Layout.screenInset,
            width: width, height: height
        )
    }

    // MARK: - Click outside

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            if !self.panel.frame.contains(mouse) {
                Task { @MainActor in self.setExpanded(false) }
            }
        }
    }

    private func removeOutsideClickMonitor() {
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }
}
