import SwiftUI
import PRRadarCore

/// A row on the My PRs tab: title, identity, then the signals that decide
/// whether this PR needs you — approvals and the lead gate, checks, open
/// threads, the merge blocker, stack position — and the rebase action.
struct MyPRRowView: View {
    let item: MyPullRequest
    let now: Date
    /// Which account surfaced this row, or nil when saying so would be noise.
    var accountLabel: String?
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
    /// Whether this row's unresolved threads are open.
    ///
    /// Held by `AppState` for the same reason a findings list is: opening one
    /// widens the drawer, and the panel cannot see a row's `@State`.
    var showingThreads = false
    var onToggleThreads: (() -> Void)?

    /// Where a resolve run on this PR has got to, or nil when there has not
    /// been one.
    var resolve: ResolveRecord?
    /// Why Resolve is not offered, from configuration alone. The rest of the
    /// guards need to ask git about a worktree, which is too expensive to do
    /// per row per poll — so they run on the press and report onto the row.
    var resolveBlock: ResolveBlock?
    /// Whether this row's resolve table is open.
    var showingResolve = false
    var onResolve: ((ResolveScope) -> Void)?
    /// Merges the base branch in, server-side. nil when the row cannot act.
    var onUpdateBranch: (() -> Void)?
    /// Stops the run on this row. nil when there is not one.
    var onStop: (() -> Void)?
    var onToggleResolve: (() -> Void)?
    var onResolveAction: ((ResolveCoordinator.Action) -> Void)?
    var onSetResolveRow: ((String, Bool) -> Void)?
    /// Whether something on this row is mid-round-trip.
    var acting = false

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
                if let resolve { resolveStrip(resolve) }
                if showingThreads, !item.unresolvedThreads.isEmpty { threads }
                if showingResolve, let table = resolve?.table, !table.threads.isEmpty {
                    resolveTable(table)
                }
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
            if let accountLabel {
                Chip(text: accountLabel, symbol: "person.crop.circle",
                     health: .neutral)
            }
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
            if item.hasLeadGate {
                if let lead = item.approvingLead {
                    Chip(text: "lead: \(lead.shortName)", symbol: "checkmark.seal.fill",
                         health: .good, filled: true)
                } else {
                    Chip(text: "lead needed", symbol: "seal", health: .attention)
                }
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

    /// The unresolved threads themselves, under the count that opened them.
    ///
    /// The count was always the whole of it — `3 open` tells you post has
    /// arrived and nothing about whether it matters. Reading them here is the
    /// trip to GitHub this saves, and the answer is usually that two of the
    /// three were nits.
    private var threads: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(item.unresolvedThreads) { thread in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if let location = thread.location {
                            Text(location)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.head)
                        }
                        // GitHub folds these away and so does the eye: still
                        // unresolved and still counted, but far likelier to be
                        // stale than unanswered.
                        if thread.isOutdated {
                            Text("outdated")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .help("The code this was written against has "
                                      + "changed since")
                        }
                    }
                    if let excerpt = thread.excerpt {
                        DiffHunkView(excerpt: excerpt)
                    }
                    ForEach(Array(thread.comments.enumerated()), id: \.offset) { _, comment in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(comment.author)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(comment.body)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.primary)
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    // Said rather than dropped: a thread cut off mid-argument
                    // reads as settled.
                    if thread.moreComments > 0 {
                        Text("+\(thread.moreComments) more")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 5)
                    .fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(Health.attention.tint.opacity(0.22), lineWidth: 0.8))
            }
        }
        .padding(.trailing, 2)
    }

    /// Checks, threads, merge blocker, behind-by.
    private var stateChips: some View {
        ChipFlow(spacing: 4) {
            if item.checks.hasAny {
                checksChip
            }
            if item.unresolvedThreadCount > 0 {
                // A button when there is something behind the count, and a
                // plain chip when there is not. The two can differ: threads are
                // fetched a hundred at a time and one without an id is dropped,
                // and a count that offers to open onto nothing is worse than a
                // count that says nothing.
                if item.unresolvedThreads.isEmpty {
                    Chip(text: "\(item.unresolvedThreadCount) open",
                         symbol: "bubble.left.and.bubble.right", health: .attention)
                        .help("\(item.unresolvedThreadCount) unresolved of "
                              + "\(item.totalThreadCount) threads")
                } else {
                    Button { onToggleThreads?() } label: {
                        Chip(text: "\(item.unresolvedThreadCount) open",
                             symbol: showingThreads
                                 ? "chevron.down"
                                 : "bubble.left.and.bubble.right",
                             health: .attention, filled: showingThreads)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    // Every other chip on this row is a label, so this one has
                    // to say it is not.
                    .pressable()
                    .help(showingThreads
                          ? "Hide the threads"
                          : "\(item.unresolvedThreadCount) unresolved of "
                            + "\(item.totalThreadCount) threads — click to read them")
                }
            } else if item.totalThreadCount > 0 {
                Chip(text: "\(item.totalThreadCount) resolved",
                     symbol: "bubble.left", health: .neutral)
            }

            resolveButton
            branchButtons

            // Behind and conflicted are said once, by the branch chip.
            if !coveredByBranchChip {
                Chip(text: item.mergeBlocker.label, symbol: "arrow.triangle.merge",
                     health: item.mergeBlocker.health)
            }

            branchChip
        }
    }

    // MARK: - Resolve

    /// Answer the threads, rather than only counting them.
    ///
    /// Beside the count, because it is the thing you want the moment you read
    /// one. Shown only when there is something to answer, and drawn disabled
    /// with its reason when the configuration is not there — a button that
    /// vanishes teaches nobody that the feature exists, and a button that says
    /// "not ticked for resolving" teaches them where to go.
    ///
    /// **Never automatic.** There is no switch anywhere that makes this happen
    /// by itself, and that is a decision rather than an omission: the bots
    /// comment again after every push, so a resolver on a timer would answer
    /// its own fixes for ever.
    @ViewBuilder
    private var resolveButton: some View {
        if item.unresolvedThreadCount > 0, onResolve != nil, canOfferResolve,
           // Not while the branch conflicts. The skill runs its conflicted-files
           // pass *before* triage for a reason it states plainly: a fix applied
           // to a branch that cannot merge gets re-resolved by hand later, and
           // an ALREADY-DONE verdict proved against a pre-merge head is simply
           // wrong. Offering both buttons at once would invite the order that
           // wastes the run — so while there are conflicts there is one button,
           // and it is the one to press first.
           !item.isConflicted {
            RowButton(title: acting ? "Resolving…" : "Resolve",
                      symbol: acting ? "hourglass" : "arrow.triangle.merge",
                      health: resolveBlock == nil ? .running : .neutral,
                      enabled: resolveBlock == nil && !acting) {
                onResolve?(.threads)
            }
            .help(resolveHelp)
        }
    }

    /// What the branch needs doing to it, offered rather than only named.
    ///
    /// The row has always *said* `needs rebase` and `conflicts`, and a rebase
    /// button was built here once and removed: it meant a local checkout, five
    /// safety guards and a force-push, to save a command the terminal runs
    /// better. Both of these answer that, and differently.
    ///
    /// **Update base** is not that rebase. GitHub merges base into head on its
    /// own servers — the same thing its own "Update branch" button does — so
    /// there is no checkout, no rewrite and nothing to force-push, and
    /// `expectedHeadOid` refuses the whole thing if the branch moved since this
    /// row was drawn. One mutation, no local state.
    ///
    /// **Resolve conflicts** is the case GitHub will not do for you, and it
    /// does need a checkout — so it is not a second feature with a second set
    /// of guards, it is the resolve run with a different sentence in its
    /// prompt. The five safety guards the old button would have needed exist
    /// now, and this goes through every one of them.
    @ViewBuilder
    private var branchButtons: some View {
        switch item.branchState {
        case .needsRebase(let behind):
            if showsUpdateButton {
                // The count rides the button rather than a chip beside it. A
                // chip saying `needs rebase · 3 behind` next to a button saying
                // `Update base` is the row stating a problem and offering its
                // answer as two separate things to read.
                RowButton(title: acting
                            ? "Updating…"
                            : behind.map { "Update base · \($0) behind" } ?? "Update base",
                          symbol: "arrow.triangle.pull",
                          health: .attention,
                          enabled: !acting) {
                    onUpdateBranch?()
                }
                .help("Merge origin/\(item.baseRefName) into this branch. GitHub "
                      + "does it server-side — no checkout, nothing rewritten, "
                      + "and it refuses if the branch has moved since this row "
                      + "was drawn.")
            }

        case .conflicts(let files):
            if showsConflictsButton {
                RowButton(title: acting
                            ? "Merging…"
                            : files.map { "Rebase & resolve · \($0) file"
                                        + ($0 == 1 ? "" : "s") }
                                ?? "Rebase & resolve",
                          symbol: "exclamationmark.triangle",
                          health: resolveBlock == nil ? .bad : .neutral,
                          enabled: resolveBlock == nil && !acting) {
                    onResolve?(.conflicts)
                }
                .help(conflictsHelp)
            }

        case .upToDate, .unknown:
            EmptyView()
        }
    }

    /// Whether Stop has already been pressed on this run.
    private var isStopping: Bool { resolve?.failure == "Stopping…" }

    /// Whether the row can offer to update the branch itself.
    ///
    /// A PR that arrived without its ids cannot be acted on, and a button that
    /// would fail is worse than a chip that explains — so the chip takes over
    /// in that case rather than the button being drawn disabled.
    private var showsUpdateButton: Bool {
        onUpdateBranch != nil && item.nodeID != nil && item.headOid != nil
    }

    private var showsConflictsButton: Bool {
        onResolve != nil && canOfferResolve
    }

    /// The same refusals the threads button shows, because it is the same run.
    private var conflictsHelp: String {
        if acting { return "Running — one at a time" }
        if let block = resolveBlock {
            return [block.reason, block.remedy].compactMap { $0 }.joined(separator: ". ")
        }
        return "Does the whole thing, in order: brings your checkout up to the "
             + "pull request if it has fallen behind, merges origin/"
             + "\(item.baseRefName) in, and resolves what conflicts using your "
             + "resolve skill.\n\nIt only ever fast-forwards your checkout — a "
             + "branch with commits of its own stops it rather than being "
             + "reset — and it refuses a tree with uncommitted work rather than "
             + "tidying up.\n\n" + conflictHelp
    }

    /// Which files, not just how many. `merge-tree --name-only` hands these
    /// over alongside the count, so withholding them would be a choice.
    private var conflictHelp: String {
        guard let files = item.conflictedFiles, !files.isEmpty else {
            return "Conflicts with \(item.baseRefName)."
        }
        let shown = files.prefix(12).joined(separator: "\n")
        return files.count > 12
            ? shown + "\n…and \(files.count - 12) more"
            : shown
    }

    /// Whether offering it makes sense at all. A run already in flight, or one
    /// whose result is still on the row, is not something to start again.
    private var canOfferResolve: Bool {
        guard let resolve else { return true }
        return resolve.status.mayRerun
    }

    private var resolveHelp: String {
        if acting { return "Running — one at a time" }
        guard let block = resolveBlock else {
            return "Run your resolve skill against these threads. It checks your "
                 + "checkout first and refuses rather than tidying it."
        }
        return [block.reason, block.remedy].compactMap { $0 }.joined(separator: ". ")
    }

    /// Where a run got to, in the review row's vocabulary so the two halves of
    /// the app read as one.
    @ViewBuilder
    private func resolveStrip(_ record: ResolveRecord) -> some View {
        ChipFlow(spacing: 4) {
            switch record.status {
            case .running:
                if let startedAt = record.startedAt {
                    TimelineView(.periodic(from: startedAt, by: 1)) { context in
                        stopwatch(record, now: context.date, health: .running)
                    }
                } else {
                    Chip(text: record.scope.runningLabel,
                         symbol: "arrow.triangle.merge", health: .running)
                }
                // The way out of a quarter-hour you have changed your mind
                // about. Not instant, and does not pretend to be: it asks the
                // session to stop rather than killing it, so a commit in flight
                // finishes instead of leaving a lock file behind.
                if onStop != nil {
                    RowButton(title: isStopping ? "Stopping…" : "Stop",
                              symbol: "stop.circle", health: .neutral,
                              enabled: !isStopping) {
                        onStop?()
                    }
                    .help(isStopping
                          ? "Asked to stop. Waiting for anything in flight to finish."
                          : "Ask it to stop. A commit already running is allowed to "
                            + "finish — stopping is not instant, and killing one "
                            + "mid-commit would leave a lock file in your repository.")
                }

            case .stopped:
                Chip(text: "stopped", symbol: "stop.circle", health: .neutral)
                    .help(record.failure ?? "")
                stopwatch(record, now: now, health: .neutral)

            case .blocked:
                Chip(text: record.block?.reason ?? record.failure ?? "not resolved",
                     symbol: "exclamationmark.triangle", health: .neutral)
                    .help(record.block?.remedy ?? "")

            case .failed:
                Chip(text: "resolve failed", symbol: "exclamationmark.triangle", health: .bad)
                    .help(record.failure ?? "")
                stopwatch(record, now: now, health: .bad)

            case .interrupted:
                Chip(text: "interrupted", symbol: "bolt.slash", health: .neutral)
                    .help("PR Radar stopped while this was running. Nothing had "
                          + "landed in your checkout.")

            // The one worth interrupting for. Code reached the branch and
            // nobody has read a word about it, so the row says where to look
            // and does not offer to run again on top of it.
            case .landedUnreported:
                Chip(text: "\(record.pushedShas.count) commit"
                        + "\(record.pushedShas.count == 1 ? "" : "s") landed unreported",
                     symbol: "exclamationmark.octagon", health: .bad)
                    .help(record.forensics ?? record.failure ?? "")
                if let forensics = record.forensics {
                    RowButton(title: "Copy check", symbol: "doc.on.doc", health: .neutral) {
                        Clipboard.copy(forensics)
                    }
                    .help(forensics)
                }

            case .orphaned:
                Chip(text: "still running elsewhere", symbol: "hourglass", health: .attention)
                    .help("A run from a previous launch of PR Radar is still "
                          + "working in \(record.treePath ?? "your checkout").")

            case .ready:
                mergeChips(record)
                dispositionChips(record)
                stopwatch(record, now: now, health: .good)
                if record.isAwaitingSelection {
                    RowButton(title: showingResolve ? "Hide replies" : "Choose replies",
                              symbol: showingResolve ? "chevron.up" : "chevron.down",
                              health: .neutral) {
                        onToggleResolve?()
                    }
                }
                if let table = record.table, table.selection.chosen > 0 {
                    RowButton(title: acting
                                ? "Sending…"
                                : "Post \(table.selection.chosen) of \(table.selection.total)",
                              symbol: "paperplane", health: .running, enabled: !acting) {
                        onResolveAction?(.post)
                    }
                    .help("Reply to each ticked thread and close the ones that "
                          + "were actually answered")
                }
                RowButton(title: "Dismiss", symbol: "xmark", health: .neutral,
                          enabled: !acting) {
                    onResolveAction?(.dismiss)
                }

            case .posted:
                if record.scope.producesReplies {
                    Chip(text: "\(record.postedThreadIDs.count) answered",
                         symbol: "checkmark.bubble", health: .good)
                }
                mergeChips(record)
                dispositionChips(record)

            case .dismissed:
                EmptyView()
            }

            // Said wherever it is true, because it is the highest-value thing a
            // run finds: real work, out of scope, and in nobody's backlog.
            if let gaps = record.table?.untrackedGaps, !gaps.isEmpty {
                Chip(text: "\(gaps.count) untracked", symbol: "tray.full",
                     health: .attention)
                    .help("Out of scope and nothing tracking it — "
                          + gaps.compactMap(\.asanaNote).joined(separator: "; "))
            }
            // A count that quietly meant something smaller is the failure this
            // whole feature exists to avoid.
            if let missing = record.table?.missing, !missing.isEmpty {
                Chip(text: "\(missing.count) not triaged", symbol: "questionmark.circle",
                     health: .attention)
                    .help("The run did not come back with these threads, so "
                          + "nothing has been decided about them.")
            }
        }
    }

    /// What a conflicts run did.
    ///
    /// Three outcomes worth telling apart, and the middle one is the reason
    /// this is not just a tick: a branch that turned out to merge cleanly after
    /// all is a different answer from one that was fixed, and reporting it as
    /// "resolved 0 files" would read as work done.
    @ViewBuilder
    private func mergeChips(_ record: ResolveRecord) -> some View {
        if let merge = record.table?.merge {
            if !merge.conflicted {
                Chip(text: "merged clean", symbol: "arrow.triangle.merge", health: .good)
                    .help("It merged without conflicting after all. Nothing was "
                          + "hand-resolved.")
            } else {
                Chip(text: "\(merge.files.count) file"
                        + "\(merge.files.count == 1 ? "" : "s") resolved",
                     symbol: "arrow.triangle.merge", health: .good)
                    .help(merge.files.isEmpty
                          ? (merge.resolution ?? "")
                          : merge.files.joined(separator: "\n"))
            }
            if let resolution = merge.resolution, !resolution.isEmpty {
                Chip(text: "how", symbol: "info.circle", health: .neutral)
                    .help(resolution)
            }
            if let sha = merge.sha, !sha.isEmpty {
                Chip(text: String(sha.prefix(7)), symbol: "checkmark.seal", health: .good)
                    .help("The merge commit, pushed")
            }
        }
    }

    @ViewBuilder
    private func dispositionChips(_ record: ResolveRecord) -> some View {
        if let table = record.table {
            ForEach(ResolveDisposition.allCases, id: \.self) { disposition in
                let count = table.count(disposition)
                if count > 0 {
                    Chip(text: "\(count) \(disposition.label)", health: disposition.health)
                }
            }
        }
    }

    @ViewBuilder
    private func stopwatch(_ record: ResolveRecord, now: Date, health: Health) -> some View {
        HStack(spacing: 4) {
            Chip(text: record.status == .running ? "resolving…" : "resolved",
                 symbol: "arrow.triangle.merge", health: health)
            if let seconds = record.runTime(now: now) {
                Chip(text: RunTime.clock(seconds), symbol: "stopwatch", health: health)
            }
        }
    }

    /// The table, one thread at a time, with the drafted reply under each.
    @ViewBuilder
    private func resolveTable(_ table: ResolveTable) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if !table.scope.isEmpty {
                Text(table.scope)
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Said before the replies, because it changes what every reply
            // below it means: while a draft review of yours is open, anything
            // posted into it is invisible to everybody else.
            if let pending = table.pending {
                Label("A draft review of yours holds \(pending.comments) comments. "
                      + "Replies are invisible to others until you submit it.",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 9))
                    .foregroundStyle(Health.attention.tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(table.threads) { row in
                resolveRow(row)
            }
        }
        .padding(.leading, 10)
        .padding(.top, 2)
    }

    @ViewBuilder
    private func resolveRow(_ row: ResolveRow) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Button {
                onSetResolveRow?(row.threadId, !row.isSelected)
            } label: {
                Image(systemName: row.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundStyle(row.isSelected ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pressable()
            .disabled(!row.mayResolve)
            .help(row.mayResolve
                  ? (row.isSelected ? "Do not send this one" : "Send this one too")
                  : "Nothing was decided about this one, so it stays open")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Chip(text: row.disposition.label, health: row.disposition.health)
                    if let sha = row.sha, !sha.isEmpty {
                        Text(String(sha.prefix(7)))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    // A reply citing a commit that is not on the remote is
                    // false the moment it lands, so it is held and says so.
                    if row.shaIsUnpushed {
                        Text("not pushed")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Health.bad.tint)
                            .help("That commit is not on the remote, so a reply "
                                  + "citing it would not be true. Held back.")
                    }
                }
                Text(row.reply)
                    .font(.system(size: 10))
                    .foregroundStyle(row.isSelected ? .primary : .secondary)
                    .lineLimit(4)
                    .fixedSize(horizontal: false, vertical: true)
                if let needs = row.needs, !needs.isEmpty {
                    Text("needs you: \(needs)")
                        .font(.system(size: 9))
                        .foregroundStyle(Health.attention.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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

    /// Says what the branch needs — when nothing beside it is offering to do it.
    ///
    /// Rebasing from here was built and then removed: it meant a local
    /// checkout, five safety guards and a force-push, to save a command the
    /// terminal runs better. Naming the state was the useful half, and for a
    /// long time it was the whole of it.
    ///
    /// It is now the fallback rather than the rule. Where the row can act — a
    /// server-side merge, or a resolve run through the guards that exist now —
    /// the button carries the state in its own title, and this draws nothing.
    /// Two controls saying `3 behind` is the row stating a problem and offering
    /// its answer as separate things to read.
    @ViewBuilder
    private var branchChip: some View {
        switch item.branchState {
        case .upToDate:
            EmptyView()
        case .needsRebase(let behind):
            if !showsUpdateButton {
                Chip(text: behind.map { "needs rebase · \($0) behind" } ?? "needs rebase",
                     symbol: "arrow.triangle.pull", health: .attention)
                    .help("Update this branch from origin/\(item.baseRefName)")
            }
        case .conflicts(let files):
            if !showsConflictsButton {
                Chip(text: files.map { "conflicts · \($0) file" + ($0 == 1 ? "" : "s") }
                        ?? "conflicts · needs rebase",
                     symbol: "exclamationmark.triangle",
                     health: .bad, filled: true)
                    .help(conflictHelp)
            }
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
