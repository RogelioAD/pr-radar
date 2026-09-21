import AppKit
import SwiftUI
import PRRadarCore

/// The banner that drops in from the top of the screen when the review queue
/// reaches zero.
///
/// Its own window rather than anything inside the drawer: the drawer is
/// usually shut at the moment this fires, and the badge — which is about to
/// hide itself, because nothing is waiting — is the wrong place to celebrate
/// having nothing.
@MainActor
final class AchievementBanner {

    /// How long it stays once it has arrived. Long enough to read twice,
    /// short enough that it is gone before it becomes something to dismiss —
    /// it takes no clicks, so it must never need one.
    private static let hold: TimeInterval = 3.2
    private static let dropDuration: TimeInterval = 0.38
    private static let liftDuration: TimeInterval = 0.28

    private var panel: NSPanel?
    private var dismissal: Task<Void, Never>?
    /// The visible frame of the screen this banner is on, kept so it leaves by
    /// the same edge it entered even if the mouse has since moved elsewhere.
    private var resting: NSRect?

    /// `screen` is the one the app's own panel is on, so on a second display
    /// the banner arrives where the badge already lives rather than wherever
    /// the keyboard happens to be.
    func show(on screen: NSScreen?) {
        // A second clearing while the first is still on screen restarts it
        // rather than stacking a second window behind the first.
        dismiss(animated: false)

        let scale = Layout.achievementScale(on: screen)
        let size = Achievement.size(scale: scale)
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
        panel.contentView = NSHostingView(rootView: AchievementBannerView(scale: scale))
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

        dismissal = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss(animated: true)
        }
    }

    private func dismiss(animated: Bool) {
        dismissal?.cancel()
        dismissal = nil
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

/// The banner's face: a star, a standing header, and the thing you did.
///
/// Every metric is a multiple of `scale`, which the screen chose — so this
/// draws the same banner at whatever size it was given without a second set of
/// numbers to keep in step.
struct AchievementBannerView: View {
    let scale: CGFloat

    private var padding: CGFloat { Achievement.paddingCells * scale }
    private var radius: CGFloat { Achievement.paddingCells * scale * 0.8 }

    var body: some View {
        HStack(spacing: Achievement.gapCells * scale) {
            // No halo. It rings the whole silhouette, notches included, which
            // fills the gaps between a star's legs and turns it into a blob —
            // and on a near-black banner the green has all the contrast it
            // needs without one.
            SpriteCanvas(layout: .achievementEmblem(), scale: scale)

            VStack(alignment: .leading, spacing: Achievement.lineGapCells * scale) {
                SpriteCanvas(layout: .bannerText(Achievement.headline, slot: .accent),
                             scale: Achievement.headlineScale(scale))
                SpriteCanvas(layout: .bannerText(Achievement.title, slot: .light),
                             scale: scale)
            }
        }
        .padding(padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(0.88))
        )
        .overlay(
            // Green, so the frame says the same thing the star does.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Health.good.tint, lineWidth: scale)
        )
        .shadow(color: .black.opacity(0.45), radius: 10 * scale, y: 4 * scale)
    }
}
