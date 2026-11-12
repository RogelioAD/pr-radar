import AppKit
import SwiftUI
import PRRadarCore

/// The banner that drops in from the top of the screen when something worth a
/// nod happens — a trophy earned, or a pull request landing in one of the
/// repositories you work in.
///
/// Its own window rather than anything inside the drawer: the drawer is
/// usually shut at the moment this fires, and the badge — which for the
/// original of these was about to hide itself, because nothing was waiting —
/// is the wrong place to celebrate having nothing.
///
/// One class for both kinds, and it has to be one: two would each own a panel,
/// and a trophy and a merge arriving in the same round would put two cards in
/// the same place at the same time. Sharing the queue is what makes a round's
/// worth of news a queue instead of a pile.
///
/// The two kinds leave differently. A trophy holds for three seconds and lifts
/// out by itself; a merge waits to be dismissed, because the thing it is
/// telling you about is somebody else's work landing in something you are in
/// the middle of, and three seconds is the length of a glance away.
@MainActor
final class DropBanner {

    /// What one banner is showing: a drawing, a quiet standing line, and the
    /// loud one that carries the news.
    private struct Card {
        let emblem: SpriteLayout
        let headline: String
        let title: String
        /// Whether it stays until it is sent away.
        var waitsToBeDismissed = false
        /// How many merges this card stands for, so a queue of them can be
        /// collapsed into one line without losing the count. One for anything
        /// that speaks for itself.
        var represents = 1
        /// Where pressing the card goes. nil on a trophy, which is about
        /// something you did rather than somewhere to be, and on the summary
        /// line, which is not one pull request and so has nowhere to send you.
        var opens: URL?

        /// The line a crowded queue collapses to.
        static func mergeSummary(_ count: Int) -> Card {
            Card(emblem: .mergeEmblem(),
                 headline: MergeNotice.manyHeadline,
                 title: MergeNotice.manyTitle(count),
                 waitsToBeDismissed: true,
                 represents: count)
        }

        /// Whether a press on the card body does anything but dismiss it.
        var isLink: Bool { opens != nil }
    }

    /// How long a trophy stays once it has arrived. Long enough to read twice,
    /// short enough that it is gone before it becomes something to dismiss —
    /// it takes no clicks, so it must never need one.
    private static let hold: TimeInterval = 3.2
    private static let dropDuration: TimeInterval = 0.38
    private static let liftDuration: TimeInterval = 0.28
    /// Gap between one banner leaving and the next arriving, so a queue reads
    /// as several things rather than one thing flickering.
    private static let gap: TimeInterval = 0.25

    /// Past this many at once, the queue is abandoned for a single summary.
    ///
    /// Five banners is around eighteen seconds of the screen being used by
    /// something nobody asked for; twenty-five would be a minute and a half.
    /// A burst that size is almost always a backlog surfacing at once rather
    /// than twenty-five things you just did, and it is worth one line, not
    /// twenty-five.
    private static let maximumInARow = 5

    private var panel: NSPanel?
    /// What is on screen now, so an arriving burst can tell a card that will
    /// leave on its own from one that is waiting to be read.
    private var current: Card?
    private var pending: [Card] = []
    /// True from the first card of a run until the queue empties — including
    /// the quarter-second between one lifting out and the next dropping in,
    /// which is why `panel == nil` cannot answer this.
    private var isPlaying = false
    /// The hold, or the gap. One at a time, and cancelled before it is reused:
    /// two of these alive at once is two banners presented for one dismissal.
    private var timer: Task<Void, Never>?
    /// The screen the run is playing on, so every card in it arrives where the
    /// first one did even if the mouse has since moved to another display.
    private var screen: NSScreen?
    /// The visible frame of that screen, kept so a banner leaves by the same
    /// edge it entered.
    private var resting: NSRect?

    /// Shows one banner per trophy, in turn.
    ///
    /// `screen` is the one the app's own panel is on, so on a second display
    /// the banner arrives where the badge already lives rather than wherever
    /// the keyboard happens to be.
    func show(_ trophies: [TrophyID], on screen: NSScreen?) {
        guard !trophies.isEmpty else { return }
        let cards: [Card]
        if trophies.count > Self.maximumInARow {
            cards = [Card(emblem: .achievementEmblem(),
                          headline: Achievement.headline,
                          title: Achievement.manyTitle(trophies.count))]
        } else {
            cards = trophies.map { id in
                let trophy = Trophy.named(id)
                return Card(emblem: .trophy(trophy.smallArt),
                            headline: Achievement.headline,
                            title: trophy.name)
            }
        }
        enqueue(cards, on: screen)
    }

    /// Shows one banner per merge, each waiting to be dismissed.
    ///
    /// Its own run limit, lower than the trophies'. A trophy burst is a
    /// backfill that happens once per machine; merges are a team's work
    /// landing, and a release train puts six in at once — see
    /// `MergeWatch.maximumInARow`. It matters more here than it ever did for
    /// trophies, because every one of these costs a press.
    func show(merges: [MergedPR], on screen: NSScreen?) {
        guard !merges.isEmpty else { return }
        let cards: [Card]
        if merges.count > MergeWatch.maximumInARow {
            cards = [.mergeSummary(merges.count)]
        } else {
            cards = merges.map { merge in
                Card(emblem: .mergeEmblem(),
                     headline: MergeNotice.headline(author: merge.authorLogin),
                     title: MergeNotice.title(merge),
                     waitsToBeDismissed: true,
                     opens: merge.url)
            }
        }
        enqueue(cards, on: screen)
    }

    // MARK: - The queue

    private func enqueue(_ cards: [Card], on screen: NSScreen?) {
        guard let first = cards.first else { return }
        self.screen = screen

        // A fresh burst of the kind that leaves on its own replaces whatever
        // of its own kind was still running. Queueing behind it would mean a
        // banner about something that happened two minutes ago arriving after
        // one about now.
        //
        // It is allowed to take back only its own. A card that is waiting to
        // be dismissed has not been read yet — taking it away to make room is
        // the one thing a banner that stays until dismissed must never do —
        // so a trophy arriving over one queues behind it like anything else.
        if !first.waitsToBeDismissed {
            pending.removeAll { !$0.waitsToBeDismissed }
            if current?.waitsToBeDismissed == false {
                timer?.cancel()
                timer = nil
                dismiss(animated: false)
                current = nil
                isPlaying = false
            }
        }

        pending += cards
        collapseIfCrowded()
        if !isPlaying { presentNext() }
    }

    /// Past the run limit, everything still waiting becomes one line.
    ///
    /// Across rounds, not within one — `show(merges:)` already collapses a
    /// single round. This is the other way a pile builds: four merges at noon
    /// that nobody was at the desk for, then three more at ten past. Each of
    /// these costs a press, so a stack of them is a stack of chores, and
    /// "7 PULL REQUESTS" is both one press and the more useful sentence.
    private func collapseIfCrowded() {
        let waiting = pending.filter(\.waitsToBeDismissed)
        guard waiting.count > MergeWatch.maximumInARow else { return }
        pending.removeAll { $0.waitsToBeDismissed }
        pending.append(.mergeSummary(waiting.reduce(0) { $0 + $1.represents }))
    }

    private func presentNext() {
        timer?.cancel()
        timer = nil
        guard !pending.isEmpty else {
            isPlaying = false
            current = nil
            return
        }
        isPlaying = true
        let card = pending.removeFirst()
        current = card
        present(card)

        // One that waits is left alone. The press is its clock.
        guard !card.waitsToBeDismissed else { return }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.hold))
            guard !Task.isCancelled else { return }
            self?.send()
        }
    }

    /// Opens the pull request the current card is about, and sends the card
    /// away.
    ///
    /// Dismissing as well as opening, rather than leaving it up: the banner
    /// exists to tell you something you did not know, and you now know it
    /// well enough to be reading the diff. A card still sitting there over
    /// the browser you just asked it to open is the app arguing with itself.
    private func open(_ url: URL) {
        NSWorkspace.shared.open(url)
        send()
    }

    /// Takes the current card away and starts the next after the gap.
    ///
    /// The one path out, whether a hold expired, somebody pressed the mark, or
    /// somebody went to read the pull request: several ways of leaving would
    /// be several places for the queue to stall.
    private func send() {
        timer?.cancel()
        current = nil
        dismiss(animated: true)
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.liftDuration + Self.gap))
            guard !Task.isCancelled else { return }
            self?.presentNext()
        }
    }

    // MARK: - The window

    private func present(_ card: Card) {
        let sprite = card.emblem.layers.first?.sprite ?? Achievement.emblem
        let scale = Layout.achievementScale(on: screen, emblem: sprite,
                                            title: card.title,
                                            headline: card.headline,
                                            dismissible: card.waitsToBeDismissed)
        let size = Achievement.size(emblem: sprite, title: card.title,
                                    headline: card.headline,
                                    dismissible: card.waitsToBeDismissed,
                                    scale: scale)
        let visible = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        // `FloatingPanel` for the one thing it exists to answer: a borderless
        // window refuses key status by default, and SwiftUI's hover tracking
        // is live only in the key window — so the dismiss mark would never
        // light up under the pointer. It still declines main, and the panel is
        // non-activating, so pressing it does not pull you out of whatever you
        // were typing in.
        let panel = FloatingPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false          // drawn in SwiftUI, like the drawer's
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .none
        // A banner that leaves on its own takes no clicks, so it must never
        // swallow one: the window is transparent to the mouse and whatever it
        // flew over is still clickable underneath.
        //
        // One that waits to be dismissed cannot have that — it has a button —
        // so it is going to eat a click on the strip of screen it is parked
        // on. Since it is eating it either way, the whole card is made to do
        // the thing you most likely wanted: it opens the pull request it is
        // announcing. The mark beside it is the way out for when you did not.
        //
        // Which is also why the mark is a button rather than the card having
        // two halves that do different things depending on where you hit it:
        // "go and read it" and "I have seen it" are different enough answers
        // that one of them has to be aimed at.
        panel.ignoresMouseEvents = !card.waitsToBeDismissed
        panel.contentView = BannerHostingView(
            rootView: DropBannerView(emblem: card.emblem,
                                     headline: card.headline,
                                     title: card.title,
                                     scale: scale,
                                     onOpen: card.opens.map { url in
                                         { [weak self] in self?.open(url) }
                                     },
                                     onDismiss: card.waitsToBeDismissed
                                         ? { [weak self] in self?.send() }
                                         : nil))
        self.resting = visible

        let x = visible.midX - size.width / 2
        // Starts fully above the screen's usable top, so it arrives from
        // offscreen rather than fading in on top of somebody's window.
        panel.setFrame(NSRect(x: x, y: visible.maxY, width: size.width, height: size.height),
                       display: true)
        panel.orderFrontRegardless()
        self.panel = panel

        let resting = NSRect(x: x,
                             y: visible.maxY - size.height - Layout.screenInset,
                             width: size.width,
                             height: size.height)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.dropDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(resting, display: true)
        }
    }

    private func dismiss(animated: Bool) {
        guard let panel else { return }
        self.panel = nil

        guard animated else {
            panel.orderOut(nil)
            return
        }
        var gone = panel.frame
        // Back out the way it came, past the top of the screen it arrived on.
        gone.origin.y = resting?.maxY ?? gone.maxY
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = Self.liftDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().setFrame(gone, display: true)
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }
}

/// Hosts the banner so that the first click lands on it.
///
/// Without `acceptsFirstMouse` the first press on a window of an app that is
/// not active is spent waking the window and never reaches the view — which
/// for a dismiss button means pressing it twice, on a banner whose whole
/// promise is that one press sends it away. The drawer learned this already;
/// see `DraggableHostingView`.
private final class BannerHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// The banner's face: an emblem, a standing header, and the news.
///
/// Every metric is a multiple of `scale`, which the screen chose — so this
/// draws the same banner at whatever size it was given without a second set of
/// numbers to keep in step. The emblem is the one exception, and it has a rule
/// of its own: see `Achievement.emblemScale`.
struct DropBannerView: View {
    let emblem: SpriteLayout
    let headline: String
    let title: String
    let scale: CGFloat
    /// nil where the card has nowhere to send you — a trophy, or the line that
    /// stands for several merges at once.
    var onOpen: (() -> Void)?
    /// nil for a banner that leaves on its own, which draws no mark and takes
    /// no presses.
    var onDismiss: (() -> Void)?

    @State private var isHovering = false

    private var padding: CGFloat { Achievement.paddingCells * scale }
    private var radius: CGFloat { Achievement.paddingCells * scale * 0.8 }
    private var halo: CGFloat { Achievement.haloCells * scale }

    private var emblemScale: CGFloat {
        guard let sprite = emblem.layers.first?.sprite else { return scale }
        return Achievement.emblemScale(sprite, textScale: scale)
    }

    var body: some View {
        HStack(spacing: Achievement.gapCells * scale) {
            // No halo. It rings the whole silhouette, notches included, which
            // fills the gaps between a star's legs and turns it into a blob —
            // and on a near-black banner the art has all the contrast it
            // needs without one.
            SpriteCanvas(layout: emblem, scale: emblemScale)

            VStack(alignment: .leading, spacing: Achievement.lineGapCells * scale) {
                SpriteCanvas(layout: .bannerText(headline, slot: .accent),
                             scale: Achievement.headlineScale(scale))
                SpriteCanvas(layout: .bannerText(title, slot: .light), scale: scale)
            }

            if let onDismiss { closeButton(onDismiss) }
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            // Green, so the frame says the same thing the emblem does.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Health.good.tint, lineWidth: scale)
        )
        // The halo, outside both. Filled rather than stroked: a fill under a
        // card inset by exactly the ring's width leaves a ring of even
        // thickness round every corner, where a stroke has to guess at how
        // two continuous curves of different radii line up.
        .padding(halo)
        .background(
            RoundedRectangle(cornerRadius: radius + halo, style: .continuous)
                .fill(Color(SpritePalette.halo))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .shadow(color: .black.opacity(0.45), radius: 10 * scale, y: 4 * scale)
        // The rest of the card, for a banner that is eating the click anyway:
        // it opens the pull request, or where there is none to open, it is
        // one more place to dismiss from. After the button in the modifier
        // order, so the mark keeps its own press rather than this swallowing
        // it.
        .modifier(PressAnywhere(action: onOpen ?? onDismiss,
                                isLink: onOpen != nil))
    }

    /// The mark, in a hit area the height of the type beside it.
    ///
    /// Seven cells is a small target — at 2x it is fourteen points — and a
    /// target that small on something that arrived uninvited is a nuisance.
    /// The drawing stays small and the *press* is the full height of the card,
    /// which costs nothing: the width it reserves is the width the banner was
    /// sized around either way.
    private func closeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SpriteCanvas(layout: .bannerClose(), scale: scale)
                .frame(width: Achievement.closeCells * scale,
                       height: Achievement.textHeight(scale: scale))
                .contentShape(Rectangle())
                // Lit under the pointer, so it reads as a thing to press
                // rather than as part of the drawing.
                .opacity(isHovering ? 1 : 0.65)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help("Dismiss")
        .accessibilityLabel("Dismiss this banner")
    }
}

/// Makes the whole card act on a press, where there is something for it to do.
///
/// A modifier rather than a bare `onTapGesture`, because the gesture must not
/// exist at all on a banner that ignores the mouse: an invisible tap target
/// over somebody's window is exactly what `ignoresMouseEvents` is there to
/// prevent, and a gesture that is never reached is still one more thing to be
/// wrong about later.
private struct PressAnywhere: ViewModifier {
    let action: (() -> Void)?
    /// Whether the press goes somewhere, as opposed to merely closing this.
    /// Only a link earns the pointing hand — a cursor that promises a
    /// destination on something that just goes away is a small lie told every
    /// time the pointer crosses the screen.
    let isLink: Bool

    func body(content: Content) -> some View {
        if let action {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .onHover { inside in
                    guard isLink else { return }
                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .help(isLink ? "Open this pull request on GitHub" : "Dismiss")
        } else {
            content
        }
    }
}
