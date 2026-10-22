import SwiftUI
import PRRadarCore

/// The whole cast, walking.
///
/// Earned by typing ↑↑↓↓←→←→BA into the open drawer, and good for nothing
/// whatsoever. It exists because this app already draws twelve hand-authored
/// characters that each get shown one at a time, and a line of all of them is
/// the thing the art has been owed since the second shelf went in.
///
/// The drawer fades out for the length of it and comes back afterwards. It was
/// drawn over the list to begin with, which was a mess: two sets of pixel art
/// at two scales on top of each other is not a parade. It still takes no
/// clicks, and the drawer keeps its frame throughout — emptying it would
/// collapse the panel and bounce it back seven seconds later, which is a worse
/// interruption than the one that fixes.
struct ParadeView: View {
    /// How long the whole thing takes, end to end.
    static let duration: TimeInterval = 7

    /// Sprite frames a second. The bob cycles are authored against a frame
    /// counter, so this is the one number that decides whether they amble or
    /// scurry. Eight is the drawer's own rate.
    private static let fps: Double = 8

    let width: CGFloat
    let onFinished: () -> Void

    /// Fixed at init rather than read from a clock inside the body: the
    /// timeline redraws constantly and a start time recomputed on each pass
    /// would leave the parade standing still, very smoothly.
    @State private var start = Date()

    /// Everybody, in the order the room shelves them — the oldest cohort
    /// first, which makes the line read as the cast's own history going past.
    private var cast: [Mascot] { MascotID.allCases.map(Mascot.named) }

    var body: some View {
        TimelineView(.animation) { timeline in
            let elapsed = timeline.date.timeIntervalSince(start)
            let frame = Int(elapsed * Self.fps)
            canvas(frame: frame, progress: min(1, elapsed / Self.duration))
        }
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(for: .seconds(Self.duration))
            onFinished()
        }
    }

    private func canvas(frame: Int, progress: Double) -> some View {
        // Right to left, starting fully off one edge and ending fully off the
        // other, so nobody is ever seen standing still waiting to begin.
        let travel = width + Self.lineWidth
        let offset = width - travel * progress

        return HStack(alignment: .bottom, spacing: Self.gap) {
            ForEach(Array(cast.enumerated()), id: \.element.id) { index, mascot in
                SpriteCanvas(
                    layout: .perch(mascot: mascot,
                                   // A different mood each, cycled: the line
                                   // is the one place the whole expression
                                   // range is on screen at once, and twelve
                                   // identical idles would waste it.
                                   style: Mood.allCases[index % Mood.allCases.count].style,
                                   // Staggered, so they bob out of step. In
                                   // lockstep a dozen characters read as one
                                   // object sliding past.
                                   frame: frame + index * 2,
                                   blink: false),
                    scale: Self.scale)
            }
        }
        .offset(x: offset)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .bottom)
        // Clear of the footer, so they walk along the list rather than over
        // the gear and the Refresh button. The overlay covers the whole
        // drawer because they should be able to pass behind the header's
        // material too — but the one band they must not stand on is the one
        // with the controls in it.
        .padding(.bottom, Layout.footerHeight + 6)
    }

    /// Whole, because a fractional cell is what turns pixel art into a blurry
    /// JPEG — the rule every other sprite on screen already follows.
    private static let scale: CGFloat = 2
    private static let gap: CGFloat = 14

    /// Roughly how wide the line is, for working out how far it has to go.
    /// It does not have to be exact: it decides when the last character has
    /// cleared the edge, and erring long only means a beat of empty drawer.
    private static var lineWidth: CGFloat {
        let widest = MascotID.allCases
            .map { CGFloat(SpriteLayout.blockWidth(for: Mascot.named($0))) }
            .max() ?? 48
        return CGFloat(MascotID.allCases.count) * (widest * scale + gap)
    }
}
