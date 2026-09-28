import SwiftUI
import PRRadarCore

/// A diff hunk, the way GitHub stacks one above an inline comment.
///
/// One view, two callers, and that is the point: a review finding on the
/// Reviews tab and an unresolved thread on My PRs are both "somebody's remark
/// about this line", and they were never going to stay looking alike if the
/// gutter widths and the tints were written out twice.
///
/// The excerpt arrives already sliced. Where its lines came from is the
/// caller's business — a worktree that no longer exists, in one case, and
/// GitHub's own `diffHunk` in the other — and this view is deliberately
/// incurious about which.
struct DiffHunkView: View {
    let excerpt: DiffExcerpt

    /// The lines themselves.
    ///
    /// Truncated rather than wrapped. A 440pt drawer cannot hold a long line
    /// either way, and wrapping one turns a seven-line hunk into thirty rows of
    /// reflowed code that no longer looks like code — the indentation, which is
    /// most of what makes a hunk scannable, is the first thing to go. The tail
    /// is what gets cut, so the indentation survives, and the whole line is on
    /// the tooltip.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(excerpt.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 0) {
                    Text(line.number.map(String.init) ?? "")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(.quaternary)
                        .frame(width: 26, alignment: .trailing)
                    Text(sign(line.kind))
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(tint(line.kind).opacity(0.9))
                        .frame(width: 11, alignment: .center)
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(line.kind == .removed ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(line.text)
                }
                .padding(.vertical, 0.5)
                .background(background(line, in: excerpt))
            }
        }
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8))
        .padding(.leading, 15)
        .padding(.trailing, 2)
    }

    private func sign(_ kind: DiffLine.Kind) -> String {
        switch kind {
        case .added: return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    private func tint(_ kind: DiffLine.Kind) -> Color {
        switch kind {
        case .added: return Health.good.tint
        case .removed: return Health.bad.tint
        case .context: return .secondary
        }
    }

    /// Added and removed are tinted the way a diff always is. The commented
    /// line is tinted *over* that, because which line the finding is actually
    /// about is the one thing this view exists to say.
    @ViewBuilder
    private func background(_ line: DiffLine, in excerpt: DiffExcerpt) -> some View {
        ZStack {
            switch line.kind {
            case .added: tint(.added).opacity(0.12)
            case .removed: tint(.removed).opacity(0.10)
            case .context: Color.clear
            }
            if excerpt.isFocused(line.number) {
                Color.accentColor.opacity(0.16)
            }
        }
    }
}
