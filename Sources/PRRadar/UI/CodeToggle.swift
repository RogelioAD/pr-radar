import SwiftUI
import PRRadarCore

/// The `file:line` line under a finding or a thread, which opens the code it is
/// about.
///
/// One control for both tabs, because a finding and a review thread are the
/// same kind of thing seen from two sides — somebody's remark, anchored to a
/// line. They were drawn separately and behaved differently: a finding kept its
/// code behind a chevron and a thread showed the hunk permanently, so a My PRs
/// row with three threads was three diff hunks tall before you had read a word
/// of what anybody said.
///
/// Sharing the control is what keeps that from coming back. The chevron, the
/// type size, the colour when open, the tooltip and the indent the code sits at
/// are each defined once here rather than agreed twice.
struct CodeToggle: View {
    let location: String
    /// Whether there is code to show. A location with no hunk behind it is
    /// still worth printing — it says where the remark is — but it is a label
    /// rather than a button, and must not offer a press that does nothing.
    let hasCode: Bool
    let isOpen: Bool
    var onToggle: () -> Void

    /// Where disclosed code starts, so it lines up under the text it belongs to
    /// rather than under the gutter.
    ///
    /// Matches the width of a finding's checkbox plus its spacing, which is
    /// what a finding's code has always been indented by. A thread has no
    /// checkbox, so this is purely the "it belongs to the thing above" cue
    /// there — the same cue, arrived at the same way.
    static let codeIndent: CGFloat = 15

    var body: some View {
        if hasCode {
            Button(action: onToggle) {
                HStack(spacing: 2) {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                    Text(location)
                        .font(.system(size: 9, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .foregroundStyle(isOpen ? AnyShapeStyle(Color.accentColor)
                                        : AnyShapeStyle(.tertiary))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pressable()
            .help(isOpen ? "Hide the code" : "Show the code this is about")
        } else {
            Text(location)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }
}

/// The code itself, under whatever disclosed it.
///
/// A view rather than a modifier so the indent and the trailing inset cannot be
/// applied at one call site and forgotten at the other.
struct DisclosedCode: View {
    let excerpt: DiffExcerpt

    var body: some View {
        DiffHunkView(excerpt: excerpt)
            .padding(.leading, CodeToggle.codeIndent)
            .padding(.trailing, 2)
    }
}

/// The coordinate space a row names so the things inside it can say where
/// their bottom edge falls.
///
/// One spelling of the name, used by the row that declares the space and by
/// every piece that measures against it. Two spellings would compile and report
/// nothing: `frame(in:)` against a space that was never named falls back to the
/// nearest one, so the cuts would be measured from somewhere else entirely and
/// the drawer would size itself to numbers that mean nothing.
enum RowSpace {
    static func name(_ rowKey: String) -> String { "row:\(rowKey)" }
}

extension View {
    /// Reports this view's bottom edge as a place the drawer may stop.
    ///
    /// Applied to each comment or finding, so an open row offers one stop per
    /// thing showing rather than one for the whole row.
    func rowCut(_ rowKey: String) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: RowCutsKey.self,
                    value: [rowKey: [geometry
                        .frame(in: .named(RowSpace.name(rowKey))).maxY]])
            }
        )
    }

    /// Names the coordinate space the cuts above are measured in.
    func rowCutSpace(_ rowKey: String) -> some View {
        coordinateSpace(name: RowSpace.name(rowKey))
    }
}
