import SwiftUI
import PRRadarCore

/// A stack of your PRs, drawn as one card.
///
/// Base last. The PR everything else sits on is at the bottom, and each row's
/// own marker grows a pancake taller the higher it sits — so the group reads
/// bottom-up, the way a stack is built and the way it has to be merged.
struct MyPRStackView: View {
    let stack: MyPRStack
    let now: Date
    /// Which account surfaced each row, asked per PR rather than per card: a
    /// stack is usually one identity's chain, but nothing guarantees it — two
    /// accounts can both reach the same repo, and a card that named only the
    /// first would be quietly wrong about the rest.
    var accountLabel: (MyPullRequest) -> String? = { _ in nil }
    let onOpen: (MyPullRequest) -> Void

    var body: some View {
        VStack(spacing: Layout.rowSpacing) {
            ForEach(stack.members) { item in
                MyPRRowView(item: item,
                            now: now,
                            accountLabel: accountLabel(item),
                            onOpen: { onOpen(item) },
                            stackPosition: stack.position(of: item),
                            stackDepth: stack.depth,
                            width: Layout.stackRowWidth)
            }
        }
        .padding(Layout.stackGroupPadding)
        // Weightier than the drawer's own 0.14 border, which is aimed at the
        // desktop behind the panel. Inside the drawer's material the same value
        // survives only on the horizontal runs: the corners and the sides
        // disappear, and a card reads as a rule drawn across the list.
        .background(
            RoundedRectangle(cornerRadius: Layout.stackGroupRadius, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Layout.stackGroupRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.30), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Stack of \(stack.depth) pull requests, "
                            + "based on pull request \(stack.base.number)")
    }
}
