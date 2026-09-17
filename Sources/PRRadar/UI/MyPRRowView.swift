import SwiftUI
import PRRadarCore

/// A row on the My PRs tab: title, identity, then the signals that decide
/// whether this PR needs you — approvals and the lead gate, checks, open
/// threads, the merge blocker, stack position — and the rebase action.
struct MyPRRowView: View {
    let item: MyPullRequest
    let now: Date
    let onOpen: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Rectangle()
                .fill(item.health.tint)
                .frame(width: 3)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                titleLine
                identityLine
                reviewChips
                stateChips
                if showsStackRow { stackRow }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            + "in \(item.repoShortName), \(item.mergeBlocker.label)")
        .accessibilityAddTraits(.isButton)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: RowHeightsKey.self,
                                       value: ["mine:\(item.id)": geometry.size.height])
            }
        )
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
        HStack(spacing: 4) {
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
            Spacer(minLength: 0)
        }
    }

    /// Checks, threads, merge blocker, behind-by.
    private var stateChips: some View {
        HStack(spacing: 4) {
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
            Spacer(minLength: 0)
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
        item.isStacked || !item.blocksRestackOf.isEmpty
    }

    private var stackRow: some View {
        HStack(spacing: 5) {
            if let parent = item.stackedOn {
                Chip(text: "stacked on #\(parent)", symbol: "square.stack.3d.up",
                     health: .neutral)
            }
            if !item.blocksRestackOf.isEmpty {
                Chip(text: "restacks " + item.blocksRestackOf.map { "#\($0)" }
                        .joined(separator: ", "),
                     symbol: "exclamationmark.triangle", health: .attention)
                    .help("Rebasing this branch leaves those PRs needing a restack")
            }
            Spacer(minLength: 0)
        }
    }

}
