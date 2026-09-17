import SwiftUI
import PRRadarCore

/// The collapsed state.
///
/// With a mascot chosen this *is* the app icon: the character, its mood mark,
/// and a counter chip per non-zero count, all on one grid. With the mascot off
/// it is the original rounded-square tile and its Dock badges, unchanged — so
/// "off" restores what shipped rather than leaving a gap.
struct BadgeView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Group {
            if let mascot = state.selectedMascot, let layout = state.badgeLayout {
                mascotWidget(mascot, layout: layout)
            } else {
                tileBadge
            }
        }
        .help(tooltip)
    }

    // MARK: - Mascot

    /// The badge is on screen all day, so it holds frame zero and moves only on
    /// an edge: a reaction to being touched, or a fetch actually in flight.
    /// There is no free-running timeline here — that is the difference between
    /// this and the drawer, which stops existing when it collapses.
    private var shouldAnimate: Bool {
        state.reaction != nil || state.isRefreshing
    }

    private func mascotWidget(_ mascot: Mascot, layout: SpriteLayout) -> some View {
        let scale = Layout.badgeScale(backingScale: state.backingScale)
        let size = Layout.badgeSize(for: layout, scale: scale)
        return MascotView(mascot: mascot,
                          style: state.spriteStyle,
                          scale: scale,
                          counters: MascotView.Counters(
                            reviews: state.count,
                            reviewHealth: state.hasProblem ? .neutral
                                                           : state.worstStaleness.health,
                            readyToMerge: state.myPRsReadyToMerge),
                          animated: shouldAnimate,
                          halo: true,
                          shadow: true)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .onHover { hovering in
                // Cheap: a bounded reaction, not a clock.
                state.reaction = hovering ? .waking : nil
            }
    }

    // MARK: - Tile (mascot off)

    private var tileBadge: some View {
        ZStack {
            // Transparent bed at full panel size. The hosting view takes mouse
            // events across its whole bounds, so this stays draggable even
            // where nothing is drawn.
            Color.clear

            // Tile sits against the leading edge, vertically centred, leaving
            // equal overhang above and below for the two badges.
            tile
                .frame(width: Layout.tileBadgeWidth, height: Layout.tileBadgeHeight,
                       alignment: .leading)

            countBadge
                .frame(width: Layout.tileBadgeWidth, height: Layout.tileBadgeHeight,
                       alignment: .topTrailing)

            readyBadge
                .frame(width: Layout.tileBadgeWidth, height: Layout.tileBadgeHeight,
                       alignment: .bottomTrailing)
        }
        .frame(width: Layout.tileBadgeWidth, height: Layout.tileBadgeHeight)
    }

    // MARK: - Tile

    /// A plain rounded square, not a glass one. It picks up the system
    /// appearance so the glyph always has a predictable ground to sit on,
    /// rather than inheriting whatever happens to be behind the panel.
    private var tile: some View {
        let shape = RoundedRectangle(cornerRadius: Layout.badgeCornerRadius,
                                     style: .continuous)
        return ZStack {
            shape.fill(isDark ? Color.black.opacity(0.92)
                              : Color.white.opacity(0.95))
            // The outline lives on the tile, not the glyph, and contrasts
            // with it: white around a black tile, black around a white one.
            // This is what separates the tile from the desktop behind it.
            shape.strokeBorder(isDark ? .white.opacity(0.85) : .black.opacity(0.75),
                               lineWidth: 1.5)
            glyph
        }
        .frame(width: Layout.badgeTileSize, height: Layout.badgeTileSize)
    }

    // MARK: - Glyph

    /// White on the black tile, black on the white one. No outline — the tile
    /// it sits on already guarantees the contrast, so the glyph stays clean.
    ///
    /// Which way round follows the system Light/Dark appearance rather than the
    /// actual pixels behind the panel: sampling those needs Screen Recording
    /// permission, which is a lot to ask for an icon colour.
    private var fillColor: Color { isDark ? .white : .black }

    private var symbolName: String {
        state.hasProblem ? "key.slash" : "arrow.triangle.pull"
    }

    private var glyph: some View {
        Image(systemName: symbolName)
            .font(.system(size: Layout.badgeGlyphSize, weight: .medium))
            .foregroundStyle(fillColor)
    }

    /// A second badge on the tile's bottom-right counting my PRs that are
    /// ready to merge — same Dock styling and size as the review count, just
    /// green and below. Kept separate so the top number keeps meaning exactly
    /// one thing: reviews I owe other people.
    @ViewBuilder
    private var readyBadge: some View {
        if state.myPRsReadyToMerge > 0 {
            dockBadge(text: state.myPRsReadyToMerge > 99 ? "99+"
                            : "\(state.myPRsReadyToMerge)",
                      base: Health.good.tint)
                .help("\(state.myPRsReadyToMerge) of your PRs "
                      + "\(state.myPRsReadyToMerge == 1 ? "is" : "are") ready to merge")
        }
    }

    // MARK: - Count badge

    @ViewBuilder
    private var countBadge: some View {
        if state.hasProblem {
            dockBadge(text: "!", base: Color(white: 0.42))
        } else if state.count > 0 {
            dockBadge(text: state.count > 99 ? "99+" : "\(state.count)",
                      base: state.worstStaleness.tint)
        }
    }

    /// Matches a real macOS Dock badge: a flat filled circle with a bold white
    /// numeral and — deliberately — no ring. The Dock's badges carry no white
    /// stroke; an earlier version of this had a prominent one, which is what
    /// made it read as not-quite-native.
    ///
    /// No drop shadow either: anything that overhangs the tile casts onto the
    /// page behind the panel, which is glaringly visible over white.
    private func dockBadge(text: String, base: Color) -> some View {
        let diameter = Layout.countBadgeSize
        let multiDigit = text.count > 1
        // One font size for every badge, whatever the digit count. Scaling it
        // down for longer numbers would make the two badges disagree, which is
        // exactly what must not happen when they sit on the same tile.
        return Text(text)
            .font(.system(size: (diameter * 0.62).rounded(), weight: .semibold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .padding(.horizontal, multiDigit ? diameter * 0.20 : 0)
            .frame(minWidth: diameter, minHeight: diameter)
            .background(Capsule().fill(base))
            .contentTransition(.numericText())
    }

    private var tooltip: String {
        if let authError = state.authError { return authError }
        guard let oldest = state.items.map(\.pingedAt).min() else { return "No reviews waiting" }
        return "\(state.count) waiting · oldest \(TimeAgo.long(since: oldest, now: state.clock))"
    }
}
