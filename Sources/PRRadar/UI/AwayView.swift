import PRRadarCore
import SwiftUI

/// What you see from the doorway.
///
/// Built to be read at four metres and ignored at one: a glyph that says the
/// Mac is spoken for, and two columns that say whether the work you walked away
/// from is still going. Everything is large, low-contrast against black, and
/// still — an animated screen in an empty room draws exactly the attention this
/// is meant to deflect.
///
/// Two headings rather than one list, because the two halves are answerable by
/// different people. **PR Radar** is work this app started and can speak for.
/// **Claude** is your own sessions, which it can only observe from the outside
/// — and a reader who cannot tell those apart cannot tell which half to trust.
///
/// **Nothing that can change size is allowed to move anything else.** The lock
/// and the title are pinned at a fixed distance from the top, the hint is
/// pinned to the bottom, and the columns hang from a fixed line below the
/// title and grow downward into the space between. A centred layout would have
/// been easier and is wrong for this screen: an agent finishing would nudge
/// the title up, which from across a room reads as the screen doing something
/// — and the one promise this screen makes is that it is sitting still.
struct AwayView: View {

    @ObservedObject var state: AppState
    var onUnlock: () -> Void

    /// How much room the title block is given. Fixed: it is an anchor
    /// everything else is positioned against, so it may not depend on content.
    ///
    /// Its distance from the top of the display is fixed too, but per screen
    /// rather than per app — see `AwayScreen.headerTop`.
    private let headerHeight: CGFloat = 112
    /// The gap between the title block and the columns. Also fixed, for the
    /// same reason.
    private let columnsTop: CGFloat = 38

    /// Ticks the elapsed times. One second, because these are stopwatches and a
    /// number that only moves once a minute does not look like it is measuring
    /// anything. The session list refreshes on its own slower beat — see
    /// `AwayController.pollFeed`.
    @State private var now = Date()
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var radar: AwayScreen.Status { state.awayStatus(now: now) }
    private var claude: ClaudeFeed.Digest { state.claudeFeed }

    var body: some View {
        // Measured rather than asked of `NSScreen`, because a cover is sized to
        // exactly one display and this is the only thing in the app that knows
        // *which*. A second monitor is rarely the same shape as the first, and
        // every number below used to be chosen for whichever one the app
        // happened to be developed on.
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black
                VStack(spacing: 0) {
                    header
                        .frame(height: headerHeight)
                        .padding(.top, AwayScreen.headerTop(forHeight: geometry.size.height))

                    columns(AwayScreen.columns(forWidth: geometry.size.width))
                        .padding(.top, columnsTop)

                    // Takes up whatever the columns did not. This is what lets
                    // them grow downward instead of pushing the hint around.
                    Spacer(minLength: 24)

                    // Says what actually happens, not what you wish happened.
                    // "Unlock" promised this screen could let you back in by
                    // itself; it cannot, and will not pretend to — a keypress
                    // hands the Mac to the login window, and being surprised by
                    // that at the keyboard is how you learn not to trust it.
                    Text("Press any key to sign back in")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.28))
                        .padding(.bottom, 56)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black)
        .ignoresSafeArea()
        .onReceive(tick) { now = $0 }
        // A trackpad nudge is the commonest way this gets touched, and it
        // should behave like any key: ask, rather than sit there.
        .contentShape(Rectangle())
        .onTapGesture { onUnlock() }
    }

    /// The two columns, set beside each other or above one another according to
    /// what the display can hold. See `AwayScreen.columns`.
    ///
    /// Top-aligned when side by side, so a long column never pushes a short one
    /// down; left-aligned when stacked, so the two still start on one edge.
    @ViewBuilder
    private func columns(_ layout: AwayScreen.Columns) -> some View {
        switch layout {
        case .sideBySide(let width):
            HStack(alignment: .top, spacing: AwayScreen.columnGap) {
                radarSection(width: width)
                claudeSection(width: width)
            }
        case .stacked(let width):
            VStack(alignment: .leading, spacing: 28) {
                radarSection(width: width)
                claudeSection(width: width)
            }
        }
    }

    private func radarSection(width: CGFloat) -> some View {
        section(title: "PR Radar", headline: radar.headline,
                lines: radar.lines, isWorking: radar.isWorking, width: width)
    }

    private func claudeSection(width: CGFloat) -> some View {
        section(title: "Claude", headline: claude.headline,
                lines: claude.lines, isWorking: claude.isWorking, width: width)
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.white.opacity(0.6))
            Text("Away")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    /// One heading and its lines.
    ///
    /// Left-aligned inside a centred pair, at a fixed width. Centring the lines
    /// themselves would give every row a different left edge, and a list whose
    /// rows do not start in the same place cannot be scanned — which is the
    /// only thing anybody does with this screen. The fixed width is what keeps
    /// the two columns from sliding sideways as their longest line changes.
    private func section(title: String,
                         headline: String,
                         lines: [String],
                         isWorking: Bool,
                         width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.32))

            Text(headline)
                .font(.system(size: 18, weight: .medium))
                // Dimmed when nothing is happening, so *working* and *idle*
                // are told apart from across the room without reading a word.
                .foregroundStyle(.white.opacity(isWorking ? 0.82 : 0.38))

            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    // One line each, always. Clipping happens upstream in the
                    // digest; this is the guarantee that a line which somehow
                    // escaped it still cannot change this column's height.
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
