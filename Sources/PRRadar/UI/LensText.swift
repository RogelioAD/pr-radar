import SwiftUI
import PRRadarCore

/// A piece of review language, shown plainly when the lens has a reading for it
/// and in its own words when not.
///
/// One view for both sides of the app — a finding's summary on Reviews and a
/// thread comment's body on My PRs — because the rule is the same in both
/// places and two copies of it would drift. The Reviews copy is the one that
/// matters: whatever it draws, `AutoReviewComment` composes the posted review
/// from `Finding` and never from here.
///
/// **The marker is not decoration.** On My PRs these are a colleague's words,
/// and a paraphrase of a person shown without a mark on it is a quotation of
/// something they did not say. The glasses say *somebody rewrote this*, and the
/// tooltip is the original, in full, always one hover away.
struct LensText: View {
    /// The text as it was written. What gets posted, where anything is posted.
    let source: String
    /// The plain reading, or nil to draw the source.
    let reading: String?
    var size: CGFloat = 10.5
    var lineLimit: Int?
    var dimmed = false

    private var isPlain: Bool { reading != nil }

    var body: some View {
        // The glyph and the text in one `Text`, so a wrapped paragraph flows
        // around the marker instead of leaving it stranded in a column of its
        // own. An `HStack` put it on the first line and left the rest indented
        // under nothing, which on a two-line summary reads as a bullet.
        Group {
            if isPlain {
                Text(Image(systemName: "eyeglasses"))
                    .foregroundStyle(.tertiary)
                + Text("  ")
                + Text(reading ?? source)
            } else {
                Text(source)
            }
        }
        .font(.system(size: size))
        .foregroundStyle(dimmed ? .secondary : .primary)
        .lineLimit(lineLimit)
        .multilineTextAlignment(.leading)
        .fixedSize(horizontal: false, vertical: true)
        .help(isPlain ? "In plain English. As written:\n\n\(source)" : source)
    }
}
