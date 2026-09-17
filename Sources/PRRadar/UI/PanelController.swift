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

    /// The collapsed footprint, which is not a constant any more: with a mascot
    /// on, the widget grows with the counts beside it. Tracking it rather than
    /// fixing it to the worst case matters because the hosting view takes mouse
    /// events across the panel's whole bounds — an oversized panel is an
    /// invisible click target sitting on the desktop.
    private var badgeSize: CGSize {
        guard let layout = state.badgeLayout else {
            return Layout.tileBadgeSize(tile: state.badgeTileSize)
        }
        return Layout.badgeSize(for: layout, scale: badgeScale)
    }

    /// Where the badge's art sits inside the panel, from the visual top-left.
    ///
    /// Recomputed rather than cached on a timer: it changes whenever the
    /// composition does — a count appearing, a mood changing the mood mark,
    /// the character being switched. `applyFrame` is the one place that already
    /// runs on every one of those, so it is where this is refreshed.
    private var badgeArtRect: NSRect = .zero

    private func currentBadgeArtRect() -> NSRect {
        guard let layout = state.badgeLayout else {
            return Layout.tileArtRect(tile: state.badgeTileSize)
        }
        return Layout.badgeArtRect(for: layout, scale: badgeScale)
            ?? NSRect(origin: .zero, size: badgeSize)
    }

    /// The sprite scale the mascot badge is actually drawn at.
    ///
    /// Snapped to whole device pixels, so it advances in steps while the tile
    /// size the user is dragging moves continuously. That is the price of pixel
    /// art staying crisp, and it is the same bargain the drawer makes when it
    /// settles onto a row boundary.
    private var badgeScale: CGFloat {
        Layout.badgeScale(tile: state.badgeTileSize, backingScale: state.backingScale)
    }

    /// The screen the panel is actually on, for anything that has to appear
    /// beside it rather than wherever the keyboard happens to be.
    var currentScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
    }

    /// Keeps the view's idea of the backing scale in step with the screen the
    /// panel is really on, so the frame reserved and the pixels drawn agree.
    private func syncBackingScale() {
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
        let scale = screen?.backingScaleFactor ?? 2
        if state.backingScale != scale { state.backingScale = scale }
    }

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

    /// One-shot, so `PRRADAR_DEBUG=1` prints the badge's grip map on the first
    /// frame that has been laid out. The drawer's equivalent is printed every
    /// time it opens; the badge has no such moment, and refreshes come round
    /// often enough that logging on each would bury everything else.
    private var hasLoggedBadgeZones = false

    /// Captured on the first movement of a corner drag, so the whole gesture is
    /// measured against the press rather than accumulated frame to frame — the
    /// badge is being re-framed under the pointer on every one of them, and
    /// accumulating would let rounding walk it across the desktop.
    private var cornerDragOrigin: (tile: CGFloat, frame: NSRect)?

    var onOpen: (ReviewItem) -> Void = { _ in }
    var onOpenMyPR: (MyPullRequest) -> Void = { _ in }
    var onRefresh: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }

    init(state: AppState) {
        self.state = state
        self.badgeFrame = Self.initialBadgeFrame(size: Self.startingBadgeSize(state: state))

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
            onToggleTrophies: { [weak self] in self?.toggleTrophyRoom() },
            onHeaderControls: { [weak self] in self?.headerControls = $0 }
        )
        hostingView = DraggableHostingView(rootView: root)
        hostingView.zoneAt = { [weak self] point in self?.zone(at: point) ?? .move }
        hostingView.resizeEdgeThickness = Layout.resizeEdge
        hostingView.onMoveFinished = { [weak self] in self?.persistPosition() }
        hostingView.onResize = { [weak self] in self?.previewResize(to: $0) }
        hostingView.onResizeFinished = { [weak self] in self?.commitResize() }
        hostingView.onCornerDrag = { [weak self] corner, delta in
            self?.previewCornerResize(corner: corner, delta: delta)
        }
        hostingView.onCornerDragFinished = { [weak self] in self?.commitCornerResize() }
        // Supplied rather than probed, so the region the cursor changes over and
        // the region a press resizes from cannot drift apart.
        hostingView.cornerGripRegion = { [weak self] in
            guard let self, !self.state.expanded else { return nil }
            return self.badgeArtRect
        }
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
        syncBackingScale()
        // Counts move, and with a mascot on they move the widget's width with
        // them. Cheap: returns immediately unless the size actually changed.
        if !state.expanded { syncBadgeFrameSize() }
        applyFrame()
        if !hasLoggedBadgeZones, !state.expanded, hostingView.bounds.width > 0 {
            hasLoggedBadgeZones = true
            logZoneMap()
        }
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
        // `Carousel` is for sitting there clicking the mascot, so the count
        // starts again every time the drawer does.
        state.mascotCycles = 0
        // The room is persisted, so the drawer can open straight onto it
        // without `openTrophyRoom` ever being called.
        if state.showingTrophies, state.trophyState.hasUnseen {
            state.trophyState.markAllSeen()
        }
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
            // The rows measure themselves while this animation is still
            // running, and `adoptRowHeights` deliberately refuses to retarget a
            // frame in flight — so the first open of a session lands on the
            // estimate and stays there until something else asks for a layout.
            // A row and its estimate used to be within a few points of each
            // other, which is why this never showed; a stack group is not, and
            // the drawer opened a third of the height it needed.
            self.applyFrame(animated: true)
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
        // The character may have been switched in the header while the drawer
        // was open, so the badge it is folding back into is not necessarily the
        // size it was when it unfolded.
        syncBadgeFrameSize()
        animate(to: badgeFrame, curve: .easeIn) { [weak self] in
            guard let self else { return }
            self.state.expanded = false
            self.applyFrame()
            self.logZoneMap()
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
            self.hostingView.refreshHoverZone()
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
                            surface: state.activeSurface,
                            accountStrip: state.showsAccountStrip)
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
        badgeArtRect = currentBadgeArtRect()
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
            self?.hostingView.refreshHoverZone()
        })
    }

    private static let zones = DrawerZones(headerHeight: Layout.headerHeight,
                                           resizeEdge: Layout.resizeEdge)

    /// Classifies a point for the drag handler.
    ///
    /// Collapsed, the badge resizes from any of its four corners and moves from
    /// everywhere else. Expanded, only the drawer's top edge resizes and only
    /// its header moves; everywhere else belongs to SwiftUI so rows, menus and
    /// the footer buttons stay clickable. The drawer deliberately grows no
    /// corner grips — it has its own handle, and two would disagree.
    ///
    /// `NSHostingView` is flipped, so its y grows downward — the conversion to
    /// a distance-from-top is what keeps the zones the right way up.
    private func zone(at point: NSPoint) -> DraggableHostingView<RootView>.Zone {
        guard state.expanded else {
            if let corner = Layout.badgeZones.corner(at: point,
                                                     art: badgeArtRect,
                                                     viewHeight: hostingView.bounds.height,
                                                     isFlipped: hostingView.isFlipped) {
                return .corner(corner)
            }
            return .move
        }
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
        guard state.expanded else {
            logBadgeZoneMap()
            return
        }
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

    /// The same, for the collapsed badge: its four grips and its middle, probed
    /// through the path a real press takes. The flip is the trap here — this is
    /// what shows an inverted conversion without squinting at the screen.
    private func logBadgeZoneMap() {
        let size = hostingView.bounds.size
        let art = badgeArtRect
        guard art.width > 0, art.height > 0 else { return }
        let inset = Layout.badgeGrip / 2
        let probes: [(String, CGPoint)] = [
            ("top-left", CGPoint(x: art.minX + inset, y: art.minY + inset)),
            ("top-right", CGPoint(x: art.maxX - inset, y: art.minY + inset)),
            ("bottom-left", CGPoint(x: art.minX + inset, y: art.maxY - inset)),
            ("bottom-right", CGPoint(x: art.maxX - inset, y: art.maxY - inset)),
            ("middle", CGPoint(x: art.midX, y: art.midY)),
            // Must read `move`: the panel's own corner is transparent space a
            // long way from the art, and grabbing there was the bug.
            ("panel corner", CGPoint(x: size.width - 1, y: size.height - 1)),
        ]
        Log.debug("badge zone map (flipped=\(hostingView.isFlipped) "
                  + "panel=\(size) art=\(art.integral) tile=\(state.badgeTileSize)):")
        for (label, visual) in probes {
            // Probes are expressed from the visual top-left; convert back into
            // view space before asking the classifier.
            let pointY = hostingView.isFlipped ? visual.y : size.height - visual.y
            Log.debug("   \(label): \(zone(at: NSPoint(x: visual.x, y: pointY)))")
        }
    }

    private func persistPosition() {
        // When expanded, the badge's notional spot is the drawer's bottom-right.
        let frame = panel.frame
        let size = badgeSize
        badgeFrame = clamp(NSRect(
            x: frame.maxX - size.width,
            y: frame.minY,
            width: size.width,
            height: size.height
        ))
        Prefs.badgeOrigin = badgeFrame.origin
        recordParkedCorner()
    }

    /// Remembers which quarter of the screen the badge was left in.
    ///
    /// Quarters rather than anything tighter: `Four Corners` is about having
    /// moved the badge all the way round at some point, and a rule that
    /// wanted the badge within some number of points of a literal corner
    /// would be a rule nobody could satisfy on purpose or by accident.
    private func recordParkedCorner() {
        guard let visible = currentScreen?.visibleFrame, visible.width > 0 else { return }
        let horizontal = badgeFrame.midX < visible.midX ? "left" : "right"
        let vertical = badgeFrame.midY < visible.midY ? "bottom" : "top"
        state.trophyState.record(TrophyFact.badgeCorner("\(vertical)-\(horizontal)"))
    }

    /// Re-frames the collapsed badge when the widget's own size changes — a
    /// count crossing into two digits, or the mascot being switched off.
    ///
    /// Anchored bottom-right, which is the corner everything else is measured
    /// from: the drawer unfolds up and to the left of it, so growing leftwards
    /// keeps a parked badge where it was parked.
    func refreshBadgeSize() {
        syncBackingScale()
        guard !state.expanded, syncBadgeFrameSize() else { return }
        applyFrame()
    }

    /// Resizes the stored badge rect in place. Separate from the above because
    /// `collapse()` needs it while the drawer still counts as expanded — it is
    /// animating *towards* the badge frame, so a stale size lands the drawer
    /// somewhere the badge is not.
    @discardableResult
    private func syncBadgeFrameSize() -> Bool {
        let size = badgeSize
        guard abs(size.width - badgeFrame.width) > 0.5
                || abs(size.height - badgeFrame.height) > 0.5 else { return false }
        badgeFrame = clamp(NSRect(x: badgeFrame.maxX - size.width,
                                  y: badgeFrame.minY,
                                  width: size.width,
                                  height: size.height))
        Prefs.badgeOrigin = badgeFrame.origin
        return true
    }

    // MARK: - Resizing

    /// Live feedback while dragging the top edge.
    ///
    /// Follows the pointer one-to-one, clamped but not snapped. Snapping every
    /// frame made the drag lurch between rows rather than track the hand.
    private func previewResize(to windowHeight: CGFloat) {
        isDraggingHeight = true
        // The *active* surface's chrome, not the Reviews tab's. The trophy
        // room hides the tab strip and the filter bar, so charging the drag
        // for them put the content height 64pt — one whole row of trophies —
        // below what the window was actually showing, and the edge fought
        // the pointer all the way up.
        let chrome = Layout.chromeHeight(for: state.activeSurface,
                                         accountStrip: state.showsAccountStrip)
        let content = Layout.sizing(for: state.activeSurface,
                                    accountStrip: state.showsAccountStrip).clamp(
            windowHeight - chrome,
            rowHeights: state.activeRowHeights,
            itemCount: state.activeRowCount,
            limit: availableMaxHeight - chrome
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

        let snapped = Layout.sizing(for: state.activeSurface,
                                    accountStrip: state.showsAccountStrip).snap(
            draft,
            rowHeights: state.activeRowHeights,
            itemCount: state.activeRowCount,
            limit: availableMaxHeight - Layout.chromeHeight(
                for: state.activeSurface, accountStrip: state.showsAccountStrip)
        )
        state.userContentHeight = snapped
        Prefs.setDrawerContentHeight(snapped, for: state.activeSurface)
        // The edge jumps to the nearest row on release; .alignment is the
        // system feedback for exactly that, and on a trackpad it makes the snap
        // felt rather than only seen.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // A touch slower than a tab switch: this is a settle, and the travel
        // is at most half a row, so a quick snap reads as a jolt.
        applyFrame(animated: true, duration: 0.22)
    }

    // MARK: - Badge resizing

    /// Live feedback while dragging a badge corner.
    ///
    /// The corner opposite the one under the hand stays put, which is the whole
    /// promise of a resize handle — everything *else* about the badge anchors
    /// bottom-right, because that is the corner the drawer unfolds from.
    private func previewCornerResize(corner: BadgeCorner, delta: CGPoint) {
        // The drawer owns resizing while it is open, and the badge frame it
        // folds back into must not move under it.
        guard !state.expanded else { return }

        let start = cornerDragOrigin ?? (tile: state.badgeTileSize, frame: badgeFrame)
        cornerDragOrigin = start

        state.badgeTileSize = Layout.badgeSizing.tileSize(from: start.tile,
                                                          corner: corner,
                                                          delta: delta)
        let size = badgeSize
        badgeFrame = clamp(NSRect(
            origin: BadgeSizing.origin(dragging: corner, in: start.frame, newSize: size),
            size: size
        ))
        applyFrame()
    }

    /// On release, keep the size that was actually *drawn*.
    ///
    /// A mascot badge can only be crisp at whole device pixels, so the sprite
    /// scale snaps and the drawn size lands a little either side of what the
    /// hand asked for. Storing the asked-for number instead would let the badge
    /// drift a few points further every time it was resized and reopened. With
    /// the mascot off the tile scales continuously and there is nothing to
    /// reconcile.
    private func commitCornerResize() {
        cornerDragOrigin = nil
        if state.badgeLayout != nil {
            state.badgeTileSize =
                Layout.badgeSizing.clamp(Layout.tileSize(forBadgeScale: badgeScale))
        }
        Prefs.badgeOrigin = badgeFrame.origin
        // The same feedback the drawer gives when its edge settles onto a row:
        // on a trackpad it makes the end of the gesture felt rather than only
        // seen.
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        applyFrame()
        // The grips just moved out from under a pointer that may not have, so
        // the cursor has to be re-derived rather than waiting to be told.
        hostingView.updateTrackingAreas()
        logZoneMap()
    }

    /// Puts the badge back to the size it had before anyone dragged it: the
    /// user's Dock tile size. Reachable from the context menu, because a badge
    /// dragged down to its floor on a busy desktop is fiddly to grab again.
    func resetBadgeSize() {
        state.badgeTileSize = Layout.dockTileSize
        // Cleared rather than written back as the Dock's current size: the
        // default is "follow the Dock", and storing today's number would freeze
        // the badge at it the next time the Dock's slider moved.
        Prefs.badgeTileSize = nil
        refreshBadgeSize()
        hostingView.updateTrackingAreas()
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
        resettle()
    }

    /// Enters or leaves the trophy room.
    ///
    /// Leaving restores the tab underneath rather than picking a default:
    /// `selectedTab` was never changed, so there is nothing to restore — the
    /// surface simply stops being the shelf.
    func toggleTrophyRoom() {
        if state.showingTrophies {
            state.showingTrophies = false
        } else {
            state.openTrophyRoom()
        }
        resettle()
    }

    /// Everything that has to happen when the drawer changes what it is
    /// showing: a different set of measured rows, so a different height, and
    /// a different zone map under whatever the pointer is already over.
    private func resettle() {
        applyFrame(animated: true)
        hostingView.updateTrackingAreas()
        hostingView.refreshHoverZone()
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

    /// `badgeSize` needs a panel to pick a screen from, and there is not one
    /// yet at init. Main screen and no counts is close enough for the first
    /// frame; the first refresh corrects it.
    private static func startingBadgeSize(state: AppState) -> CGSize {
        guard let layout = state.badgeLayout else {
            return Layout.tileBadgeSize(tile: state.badgeTileSize)
        }
        let scale = Layout.badgeScale(tile: state.badgeTileSize,
                                      backingScale: NSScreen.main?.backingScaleFactor ?? 2)
        return Layout.badgeSize(for: layout, scale: scale)
    }

    private static func initialBadgeFrame(size: CGSize) -> NSRect {
        let width = size.width, height = size.height
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
