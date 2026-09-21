import SwiftUI
import PRRadarCore

/// A row on the My PRs tab: title, identity, then the signals that decide
/// whether this PR needs you — approvals and the lead gate, checks, open
/// threads, the merge blocker, stack position — and the rebase action.
struct MyPRRowView: View {
    let item: MyPullRequest
    let now: Date
    let onOpen: () -> Void
    /// This PR's height in its stack, 1 at the base, or nil when it is not in
    /// one. Supplied by the group rather than read off the PR, because what
    /// counts as a stack depends on what is currently on screen.
    var stackPosition: Int?
    var stackDepth: Int?
    /// The width this row is laid out at. A card gives its rows less than the
    /// list does, and a row has to be told rather than infer it — see
    /// `Layout.listContentWidth`.
    var width: CGFloat = Layout.listContentWidth

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            Rectangle()
                .fill(item.health.tint)
                .frame(width: Self.barWidth)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                titleLine
                identityLine
                reviewChips
                stateChips
                if showsStackRow { stackRow }
            }
            // Definite, so the marker beside it is never squeezed out. The
            // chips inside wrap to fit this rather than pushing past it.
            .frame(width: contentWidth, alignment: .leading)

            if let position = stackPosition {
                pancakes(position: position)
            }
        }
        .padding(.horizontal, Self.padding)
        .padding(.vertical, 8)
        // Definite, not `maxWidth: .infinity`: chips are `.fixedSize()`, so a
        // crowded row reports a wider ideal than it was offered and pushes
        // whatever contains it past the drawer's edge. The clip below then
        // trims the overflowing chip instead, which is what a row without a
        // border has always quietly done.
        .frame(width: width, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.07) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .draggable(PRLink(url: item.url)) {
            Text(item.title).font(.system(size: 12)).padding(6)
        }
        .contextMenu {
            Button("Open in Browser") { onOpen() }
            Button("Copy Link") { Clipboard.copy(item.url.absoluteString) }
            Button("Copy Title") { Clipboard.copy(item.title) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), pull request \(item.number) "
                            + "in \(item.repoShortName), \(item.mergeBlocker.label)"
                            + stackDescription)
        .accessibilityAddTraits(.isButton)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: RowHeightsKey.self,
                    value: [RowHeightKeys.key(surface: .mine, id: item.id): geometry.size.height])
            }
        )
    }

    /// What the text column gets: the row, less its padding, the health bar,
    /// the gaps, and the space kept for the stack marker.
    ///
    /// Kept rather than competed for. A crowded row used to hand the whole
    /// width to the chips and leave the marker hanging off the end, where the
    /// row's clip removed it — so the deeper a stack got, the more likely its
    /// pancakes were to vanish.
    private var contentWidth: CGFloat {
        let marker = stackPosition == nil ? 0 : Layout.pancakeMarkerWidth + Self.gap
        return width - Self.padding * 2 - Self.barWidth - Self.gap - marker
    }

    private static let padding: CGFloat = 10
    private static let gap: CGFloat = 9
    private static let barWidth: CGFloat = 3

    // MARK: - Stack marker

    /// A pancake per PR from the base up to this one, on its own plate.
    ///
    /// Bottom-aligned, so every plate in a group lines up however tall the rows
    /// above them are — which is what makes the column of them read as one
    /// stack growing rather than as five unrelated drawings.
    private func pancakes(position: Int) -> some View {
        SpriteCanvas(layout: .pancakeStack(of: position),
                     scale: Layout.pancakeRowScale)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .help(stackHelp(position: position))
            .accessibilityHidden(true)
    }

    private func stackHelp(position: Int) -> String {
        guard let depth = stackDepth else { return "#\(position) in this stack" }
        let drawn = min(position, Pancakes.maxDrawn)
        let capped = drawn < position ? " (showing \(drawn))" : ""
        return "#\(position) of \(depth) in this stack\(capped)"
    }

    private var stackDescription: String {
        guard let position = stackPosition, let depth = stackDepth else { return "" }
        return ", number \(position) of \(depth) in a stack"
    }

    // MARK: - Lines

    private var titleLine: some View {
        HStack(alignment: .top, spacing: 6) {
            // Underlined while the row is hovered, so it reads as the link it
            // is. Driven by the row rather than by a hover on the text itself:
            // the whole row opens the PR, and a hover tracked on the Text
            // proved unreliable where the row's is not.
            Text(TitleText.attributed(item.title, underlined: hovering))
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
            Spacer(minLength: 2)
            Text(TimeAgo.short(since: item.createdAt, now: now))
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .help("Opened \(TimeAgo.long(since: item.createdAt, now: now))")
        }
    }

    private var identityLine: some View {
        HStack(spacing: 5) {
            Text("#\(item.number)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(item.repoShortName)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            if item.isDraft {
                Chip(text: "draft", health: .neutral)
            }
            Spacer(minLength: 2)
            Text("+\(item.additions) −\(item.deletions) · \(item.changedFiles)f")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    /// Approvals and the lead gate.
    private var reviewChips: some View {
        ChipFlow(spacing: 4) {
            if let lead = item.approvingLead {
                Chip(text: "lead: \(lead.shortName)", symbol: "checkmark.seal.fill",
                     health: .good, filled: true)
            } else {
                Chip(text: "lead needed", symbol: "seal", health: .attention)
            }

            let others = item.liveApprovals.filter { !$0.isLead }
            if !others.isEmpty {
                Chip(text: "\(others.count)", symbol: "checkmark",
                     health: .good)
                    .help("Approved by " + others.map(\.shortName).joined(separator: ", "))
            }

            // Shown rather than dropped: a dismissed approval is why a PR can
            // look approved on GitHub yet still be blocked.
            if !item.dismissedApprovals.isEmpty {
                Chip(text: "\(item.dismissedApprovals.count) dismissed",
                     symbol: "arrow.uturn.backward", health: .neutral)
                    .help("Dismissed: "
                          + item.dismissedApprovals.map(\.shortName).joined(separator: ", "))
            }

            if !item.changesRequestedBy.isEmpty {
                Chip(text: item.changesRequestedBy.map(\.shortName).joined(separator: ", "),
                     symbol: "xmark", health: .bad, filled: true)
                    .help("Changes requested")
            }
        }
    }

    /// Checks, threads, merge blocker, behind-by.
    private var stateChips: some View {
        ChipFlow(spacing: 4) {
            if item.checks.hasAny {
                checksChip
            }
            if item.unresolvedThreadCount > 0 {
                Chip(text: "\(item.unresolvedThreadCount) open",
                     symbol: "bubble.left.and.bubble.right", health: .attention)
                    .help("\(item.unresolvedThreadCount) unresolved of \(item.totalThreadCount) threads")
            } else if item.totalThreadCount > 0 {
                Chip(text: "\(item.totalThreadCount) resolved",
                     symbol: "bubble.left", health: .neutral)
            }

            // Behind and conflicted are said once, by the branch chip.
            if !coveredByBranchChip {
                Chip(text: item.mergeBlocker.label, symbol: "arrow.triangle.merge",
                     health: item.mergeBlocker.health)
            }

            branchChip
        }
    }

    private var checksChip: some View {
        let checks = item.checks
        let text: String = {
            if checks.failing > 0 { return "\(checks.failing) failing" }
            if checks.running > 0 { return "\(checks.running) running" }
            return "\(checks.passing) passed"
        }()
        let symbol = checks.failing > 0 ? "xmark.octagon"
            : (checks.running > 0 ? "circle.dotted" : "checkmark.circle")
        return Chip(text: text, symbol: symbol, health: checks.health,
                    filled: checks.failing > 0)
            .help("\(checks.passing) passed · \(checks.failing) failed · "
                  + "\(checks.running) running · \(checks.skipped) skipped"
                  + (checks.failingNames.isEmpty ? ""
                     : "\nFailing: " + checks.failingNames.joined(separator: ", ")))
    }

    /// Says plainly what the branch needs, instead of offering to do it.
    ///
    /// Rebasing from here was built and then removed: it meant a local
    /// checkout, five safety guards and a force-push, to save a command the
    /// terminal runs better. Naming the state is the useful half.
    @ViewBuilder
    private var branchChip: some View {
        switch item.branchState {
        case .upToDate:
            EmptyView()
        case .needsRebase(let behind):
            Chip(text: behind.map { "needs rebase · \($0) behind" } ?? "needs rebase",
                 symbol: "arrow.triangle.pull", health: .attention)
                .help("Update this branch from origin/\(item.baseRefName)")
        case .conflicts:
            Chip(text: "conflicts · needs rebase", symbol: "exclamationmark.triangle",
                 health: .bad, filled: true)
                .help("Conflicts with \(item.baseRefName); rebase to resolve")
        case .unknown:
            Chip(text: "base state unknown", symbol: "questionmark", health: .neutral)
                .help("Couldn't determine whether this branch is behind "
                      + "origin/\(item.baseRefName)")
        }
    }

    /// Whether the branch chip already covers the merge blocker.
    private var coveredByBranchChip: Bool {
        item.mergeBlocker.wantsRebase
    }

    // MARK: - Actions

    private var showsStackRow: Bool {
        (item.isStacked && stackPosition == nil) || !item.blocksRestackOf.isEmpty
    }

    private var stackRow: some View {
        ChipFlow(spacing: 5) {
            // Suppressed inside a group: the PR this one sits on is the row
            // directly below it, and saying so twice is noise on a row that
            // already carries four lines of chips.
            if let parent = item.stackedOn, stackPosition == nil {
                Chip(text: "stacked on #\(parent)", symbol: "square.stack.3d.up",
                     health: .neutral)
            }
            if !item.blocksRestackOf.isEmpty {
                Chip(text: "restacks " + item.blocksRestackOf.map { "#\($0)" }
                        .joined(separator: ", "),
                     symbol: "exclamationmark.triangle", health: .attention)
                    .help("Rebasing this branch leaves those PRs needing a restack")
            }
        }
    }

}
