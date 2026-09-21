import AppKit
import SwiftUI
import PRRadarCore

/// The banner that drops in from the top of the screen when a trophy is
/// earned.
///
/// Its own window rather than anything inside the drawer: the drawer is
/// usually shut at the moment this fires, and the badge — which for the
/// original of these was about to hide itself, because nothing was waiting —
/// is the wrong place to celebrate having nothing.
@MainActor
final class AchievementBanner {

    /// What one banner is showing.
    private struct Card {
        let emblem: SpriteLayout
        let title: String
    }

    /// How long one stays once it has arrived. Long enough to read twice,
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
    private var runner: Task<Void, Never>?
    /// The visible frame of the screen this banner is on, kept so it leaves by
    /// the same edge it entered even if the mouse has since moved elsewhere.
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
                          title: Achievement.manyTitle(trophies.count))]
        } else {
            cards = trophies.map { id in
                let trophy = Trophy.named(id)
                return Card(emblem: .trophy(trophy.art), title: trophy.name)
            }
        }
        play(cards, on: screen)
    }

    private func play(_ cards: [Card], on screen: NSScreen?) {
        // A fresh burst replaces whatever was still running. Queueing behind
        // it would mean a banner about something that happened two minutes
        // ago arriving after one about now.
        runner?.cancel()
        dismiss(animated: false)

        runner = Task { [weak self] in
            for (index, card) in cards.enumerated() {
                guard !Task.isCancelled else { return }
                self?.present(card, on: screen)
                try? await Task.sleep(for: .seconds(Self.hold))
                guard !Task.isCancelled else { return }
                self?.dismiss(animated: true)
                if index < cards.count - 1 {
                    try? await Task.sleep(for: .seconds(Self.liftDuration + Self.gap))
                }
            }
        }
    }

    private func present(_ card: Card, on screen: NSScreen?) {
        let sprite = card.emblem.layers.first?.sprite ?? Achievement.emblem
        let scale = Layout.achievementScale(on: screen, emblem: sprite, title: card.title)
        let size = Achievement.size(emblem: sprite, title: card.title, scale: scale)
        let visible = screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        let panel = NSPanel(
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
        // Nothing here is clickable, and a banner that swallowed a click on
        // whatever it flew over would be worse than no banner.
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(
            rootView: AchievementBannerView(emblem: card.emblem,
                                            title: card.title,
                                            scale: scale))
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

/// The banner's face: an emblem, a standing header, and the thing you did.
///
/// Every metric is a multiple of `scale`, which the screen chose — so this
/// draws the same banner at whatever size it was given without a second set of
/// numbers to keep in step. The emblem is the one exception, and it has a rule
/// of its own: see `Achievement.emblemScale`.
struct AchievementBannerView: View {
    let emblem: SpriteLayout
    let title: String
    let scale: CGFloat

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
                SpriteCanvas(layout: .bannerText(Achievement.headline, slot: .accent),
                             scale: Achievement.headlineScale(scale))
                SpriteCanvas(layout: .bannerText(title, slot: .light), scale: scale)
            }
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
    }
}
