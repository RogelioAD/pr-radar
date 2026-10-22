import SwiftUI
import PRRadarCore

/// A row on the My PRs tab: title, identity, then the signals that decide
/// whether this PR needs you — approvals and the lead gate, checks, open
/// threads, the merge blocker, stack position — and the rebase action.
struct MyPRRowView: View {
    let item: MyPullRequest
    let now: Date
    /// Whether the keyboard is on this row. See `RowView.isSelected`.
    var isSelected = false
    /// Posts a reply to a thread. Returns whether it landed, so the field can
    /// keep what was typed when it did not. nil hides the reply boxes.
    var onReply: ((String, String) async -> Bool)?
    /// Asks reviewers to look again. nil where there is nobody to ask.
    var onNudge: (([Approval]) -> Void)?
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

    /// Merges the base branch in, server-side. nil when the row cannot act.
    var onUpdateBranch: (() -> Void)?
    /// The plain-English reading for a comment, or nil for its own words.
    var lensReading: (String) -> String? = { _ in nil }
    /// This row's key in the measurement maps, so the comments on it can report
    /// where the drawer may stop. Empty when the row is not being measured.
    var rowKey: String = ""
    /// Whether something on this row is mid-round-trip.
    var acting = false

    @State private var hovering = false
    /// Which threads have their code open, by thread id.
    ///
    /// Local to the row and not persisted, exactly as the findings list's is.
    /// Opening code changes the row's height and nothing else — unlike opening
    /// the threads themselves, which widens the drawer and so has to live on
    /// `AppState` where the panel can see it.
    @State private var openCode: Set<String> = []
    /// Unsent replies, by thread id. Here rather than in the state for the
    /// reason the auto-review row keeps its own draft: an unfinished sentence
    /// is not a comment, and persisting one would redraw the drawer on every
    /// keystroke.
    @State private var drafts: [String: String] = [:]
    /// Threads with a reply in flight.
    @State private var sending: Set<String> = []

    var body: some View {
        HStack(alignment: .top, spacing: Self.gap) {
            Rectangle()
                .fill(item.health.tint)
                .frame(width: Self.barWidth)
                .clipShape(Capsule())

            VStack(alignment: .leading, spacing: 5) {
                titleLine
                identityLine
                // Three groups rather than two flows and a catch-all.
                //
                // `stateChips` had grown to carry the checks, the threads, the
                // branch and the waiting clock — four kinds of thing in one
                // undifferentiated flow, wrapping wherever the width ran out,
                // so the break never meant anything. This is the argument the
                // auto-review strip already makes about its own two bands:
                // giving the decisions their own flow puts the break where the
                // meaning already is.
                //
                // Who has signed off stays one group, and the dismissed count
                // stays in it. That chip exists to explain the `lead needed`
                // beside it, and across a group boundary it would be an
                // orphaned number.
                VStack(alignment: .leading, spacing: ChipMetrics.groupSpacing) {
                    reviewChips
                    blockingChips
                    contextChips
                }
                if showingThreads, !item.unresolvedThreads.isEmpty { threads }
                if showsStackRow { stackRow }
            }
            // Definite, so the marker beside it is never squeezed out. The
            // chips inside wrap to fit this rather than pushing past it.
            .frame(width: contentWidth, alignment: .leading)

            if let position = stackPosition {
                pancakes(position: position)
            }
        }
        .rowCutSpace(rowKey)
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
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .draggable(PRLink(url: item.url)) {
            Text(item.title).font(.system(size: 12)).padding(6)
        }
        .contextMenu {
            Button("Open in Browser") { onOpen() }
            Divider()
            // What the row will not do for you, written down so you do not
            // have to transcribe a branch name with four slashes in it. It
            // copies; it never runs.
            if let command = branchCommand {
                Button("Copy \(branchCommandTitle)") { Clipboard.copy(command) }
            }
            Button("Copy Branch Name") { Clipboard.copy(item.headRefName) }
            Divider()
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
        ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
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

    /// Where a thread is, and what is worth saying about where it is.
    ///
    /// Drawn only when it has something in it: a thread GitHub named no path
    /// for, which is not outdated, would otherwise contribute an empty row and
    /// the gap above it.
    @ViewBuilder
    private func threadLocation(_ thread: UnresolvedThread) -> some View {
        if thread.location != nil || thread.isOutdated {
            HStack(spacing: 4) {
                if let location = thread.location {
                    CodeToggle(location: location,
                               hasCode: thread.excerpt != nil,
                               isOpen: openCode.contains(thread.id)) {
                        if openCode.contains(thread.id) {
                            openCode.remove(thread.id)
                        } else {
                            openCode.insert(thread.id)
                        }
                    }
                }
                // GitHub folds these away and so does the eye: still
                // unresolved and still counted, but far likelier to be stale
                // than unanswered.
                if thread.isOutdated {
                    Text("outdated")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .help("The code this was written against has changed since")
                }
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
                // What somebody said, then where they said it, then — if you
                // ask — the code. The same three in the same order a finding
                // uses, and the same spacing between them, because a review
                // thread and a finding are one kind of thing: a remark about a
                // line. They were laid out differently and the difference was
                // not a decision; the thread put its location first and its
                // diff hunk *always* on, so three threads was three hunks of
                // code before a word of the conversation.
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(thread.comments.enumerated()), id: \.offset) { _, comment in
                        VStack(alignment: .leading, spacing: 1) {
                            // The name is never translated and never
                            // qualified. Who said it is a fact; the lens only
                            // ever touches what was said, and says so with its
                            // own mark rather than by hedging the author.
                            Text(comment.author)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(.secondary)
                            // Bounded the way a finding's summary is, at twice
                            // the lines because this is prose rather than a
                            // one-line verdict. The body is already cut to
                            // `UnresolvedThread.bodyLimit` upstream, so this is
                            // about one comment not dominating a thread rather
                            // than about length — and the whole of it is on the
                            // tooltip either way.
                            LensText(source: comment.body,
                                     reading: lensReading(comment.body),
                                     lineLimit: 4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // Each comment is a place the drag may land, so the
                        // drawer snaps to the nearest comment rather than
                        // treating six of them as one indivisible row.
                        .rowCut(rowKey)
                    }
                    // Said rather than dropped: a thread cut off mid-argument
                    // reads as settled.
                    if thread.moreComments > 0 {
                        Text("+\(thread.moreComments) more")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }

                    threadLocation(thread)

                    if openCode.contains(thread.id), let excerpt = thread.excerpt {
                        DisclosedCode(excerpt: excerpt)
                    }

                    if onReply != nil { replyBox(thread) }
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

    /// What stands between this pull request and a merge.
    ///
    /// Checks, the branch, and whatever the merge blocker says that the branch
    /// chip has not already said. Everything here is a reason it cannot go in.
    @ViewBuilder
    private var blockingChips: some View {
        if hasBlockingChips {
            ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
                if item.checks.hasAny {
                    checksChip
                }

                branchButtons

                // Behind and conflicted are said once, by the branch chip.
                if !coveredByBranchChip {
                    Chip(text: item.mergeBlocker.label, symbol: "arrow.triangle.merge",
                         health: item.mergeBlocker.health,
                         filled: fills(item.mergeBlocker.health, as: .blocker))
                }

                branchChip
            }
        }
    }

    /// Whether that group has anything in it, so an empty one costs no gap.
    ///
    /// Asked rather than left to `ChipFlow` returning nothing: the group
    /// spacing above is a `VStack`'s, and a `VStack` spaces an empty child
    /// exactly as it spaces a full one.
    private var hasBlockingChips: Bool {
        item.checks.hasAny
            || item.branchState != .upToDate
            || !coveredByBranchChip
    }

    /// Everything else the row knows — counts and clocks rather than blockers.
    @ViewBuilder
    private var contextChips: some View {
        if item.totalThreadCount > 0 || item.awaiting != nil || !item.nudgeable.isEmpty {
            ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
                threadChips
                awaitingChip
                // Last in the band and the only button in it: everything else
                // here is a count or a clock, and this is the one thing you
                // can do about them.
                nudgeButton
            }
        }
    }

    @ViewBuilder
    private var threadChips: some View {
        Group {
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
        }
    }

    /// Answering a thread without leaving.
    ///
    /// The whole conversation has been on screen since the drawer learned to
    /// read threads, and saying one word back meant a browser tab. That is an
    /// odd place to stop: a reply is a far smaller thing than the Approve
    /// button this row already has, and unlike an approval it can be edited
    /// afterwards by the person who wrote it.
    ///
    /// The field keeps what you typed when a send fails. Losing a sentence to
    /// a dropped connection is the one outcome that would stop anybody using
    /// this twice.
    @ViewBuilder
    private func replyBox(_ thread: UnresolvedThread) -> some View {
        let text = Binding(
            get: { drafts[thread.id] ?? "" },
            set: { drafts[thread.id] = $0 })
        let typed = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let busy = sending.contains(thread.id)

        HStack(spacing: 5) {
            TextField("Reply…", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 10.5))
                .lineLimit(1...4)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(0.07)))
                .disabled(busy)

            RowButton(title: busy ? "Sending…" : "Reply",
                      symbol: "arrowshape.turn.up.left",
                      health: .running,
                      // Nothing to send, or already sending it. A second press
                      // on a reply in flight is how one sentence becomes two
                      // comments.
                      enabled: !typed.isEmpty && !busy) {
                send(typed, to: thread)
            }
        }
        .padding(.top, 2)
    }

    private func send(_ body: String, to thread: UnresolvedThread) {
        guard let onReply else { return }
        sending.insert(thread.id)
        Task {
            let landed = await onReply(thread.id, body)
            sending.remove(thread.id)
            // Cleared only on success, so a failed send leaves the sentence
            // where it was rather than asking for it again.
            if landed { drafts[thread.id] = "" }
        }
    }

    /// Which signals on this row may draw themselves filled.
    ///
    /// Severe ones compete; calm ones do not. `2 blocking` and `conflicts`
    /// were both solid red at once and the eye had nowhere to land — so among
    /// the chips carrying the row's worst health, exactly one is filled, and
    /// the rest state the same thing outlined. Red is still red either way;
    /// filling is the row saying *this* is the thing to look at.
    ///
    /// A good verdict is unaffected: a filled green `lead: Alice` is the row
    /// being done rather than the row shouting, and two of those never happen.
    private enum RowSignal { case checks, branch, blocker }

    /// The one severe signal allowed to fill, in the order they are worth
    /// looking at. Ordered explicitly rather than by whichever is drawn first,
    /// so the choice does not move when the chips are rearranged.
    private var loudest: RowSignal? {
        let severe: [Health] = [.bad, .attention]
        guard severe.contains(item.health) else { return nil }
        let candidates: [(RowSignal, Health)] = [
            (.branch, branchHealth),
            (.checks, item.checks.health),
            (.blocker, item.mergeBlocker.health),
        ]
        return candidates.first { $0.1 == item.health }?.0
    }

    private var branchHealth: Health {
        switch item.branchState {
        case .conflicts: return .bad
        case .needsRebase: return .attention
        case .upToDate, .unknown: return .neutral
        }
    }

    /// Whether a chip of this health, from this signal, draws itself filled.
    private func fills(_ health: Health, as signal: RowSignal) -> Bool {
        guard health == .bad || health == .attention else { return false }
        return loudest == signal
    }

    /// Asking the people who requested changes to look again.
    ///
    /// Offered only where somebody has **already reviewed** and asked for
    /// changes, which is the whole of what GitHub's re-request does. They said
    /// no, you fixed it, and nothing you do to the branch tells them so.
    ///
    /// There is deliberately no button for the other case. A reviewer who has
    /// simply not looked yet is already in the request list, and re-adding
    /// them does nothing at all — the only thing that would notify is removing
    /// and re-adding, which means a window where a failed second call has
    /// quietly dropped somebody off your pull request. Not worth it for a
    /// reminder, so the row says nothing rather than offering a button that
    /// looks like it worked.
    @ViewBuilder
    private var nudgeButton: some View {
        let people = item.nudgeable
        if !people.isEmpty, let onNudge {
            RowButton(title: nudgeTitle(people),
                      symbol: "bell",
                      health: .attention,
                      enabled: !acting) { onNudge(people) }
                .help(nudgeHelp(people))
        }
    }

    private func nudgeTitle(_ people: [Approval]) -> String {
        people.count == 1
            ? "Ask \(people[0].shortName) again"
            : "Ask \(people.count) again"
    }

    private func nudgeHelp(_ people: [Approval]) -> String {
        let names = people.map(\.shortName).joined(separator: ", ")
        return "Re-requests a review from \(names), who asked for changes. "
             + "They are notified; nothing on the branch changes."
    }

    /// How long this has been sitting with its reviewers.
    ///
    /// The app could say to the hour what you owe other people and nothing at
    /// all about the other direction — this row has carried
    /// `awaitingReviewers` since the tab was built and never drew it, so a
    /// pull request you asked three people to look at four days ago looked
    /// exactly like one you opened this morning.
    ///
    /// The same ladder the Reviews tab ages its requests by, so the two tabs
    /// cannot come to mean different things by the same colour.
    @ViewBuilder
    private var awaitingChip: some View {
        if let awaiting = item.awaiting {
            Chip(text: awaiting.label(now: now), symbol: "hourglass",
                 health: awaiting.health(now: now))
                .help(awaiting.help(now: now))
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
    /// **Conflicts** it does not offer to do anything about. That needs a
    /// checkout, and the run that used to own one is gone — so the row names
    /// the state and leaves the merge to the terminal, which does it better.
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

        case .conflicts, .upToDate, .unknown:
            EmptyView()
        }
    }

    /// Whether the row can offer to update the branch itself.
    ///
    /// A PR that arrived without its ids cannot be acted on, and a button that
    /// would fail is worse than a chip that explains — so the chip takes over
    /// in that case rather than the button being drawn disabled.
    private var showsUpdateButton: Bool {
        onUpdateBranch != nil && item.nodeID != nil && item.headOid != nil
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

    /// The checks tally, and — once the second phase has answered — how much
    /// of it stands between this branch and a merge.
    ///
    /// `12 passed · 2 failing` counted a required build and somebody's
    /// optional lint job identically, so a row could wear the worst chip on
    /// the tab over two failures nothing gates on. It says `2 failing · none
    /// blocking` when it has been told, and `2 failing` exactly as before when
    /// it has not — because nothing asked is not the same as nothing required.
    private var checksChip: some View {
        let checks = item.checks
        let text: String = {
            if let failures = checks.failureLabel { return failures }
            if checks.running > 0 { return "\(checks.running) running" }
            return "\(checks.passing) passed"
        }()
        let symbol = checks.failing > 0 ? "xmark.octagon"
            : (checks.running > 0 ? "circle.dotted" : "checkmark.circle")
        return Chip(text: text, symbol: symbol, health: checks.health,
                    filled: fills(checks.health, as: .checks))
            .help(checksHelp)
    }

    private var checksHelp: String {
        let checks = item.checks
        var lines = ["\(checks.passing) passed · \(checks.failing) failed · "
                     + "\(checks.running) running · \(checks.skipped) skipped"]
        if !checks.failingNames.isEmpty {
            lines.append("Failing: " + checks.failingNames.joined(separator: ", "))
        }
        switch checks.requiredFailingNames {
        case nil:
            break
        case let required? where required.isEmpty:
            lines.append("None of them is a required check, so they are not "
                         + "what is blocking the merge.")
        case let required?:
            lines.append("Required: " + required.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }

    /// Says what the branch needs — when nothing beside it is offering to do it.
    ///
    /// Rebasing from here was built and then removed: it meant a local
    /// checkout, five safety guards and a force-push, to save a command the
    /// terminal runs better. Naming the state was the useful half, and for a
    /// long time it was the whole of it.
    ///
    /// It is now the fallback rather than the rule. Where the row can act — a
    /// server-side merge — the button carries the state in its own title, and
    /// this draws nothing.
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
            // `conflicts` alone where the count could not be had. It used to
            // read `conflicts · needs rebase`, which spent half a chip saying
            // what the first word already says — a conflicted branch plainly
            // needs work. The rule it was protecting is untouched: no number
            // is invented, and `conflicts · 0 files` is still not a thing the
            // row says.
            Chip(text: files.map { "conflicts · \($0) file" + ($0 == 1 ? "" : "s") }
                    ?? "conflicts",
                 symbol: "exclamationmark.triangle",
                 health: .bad, filled: fills(.bad, as: .branch))
                .help(conflictHelp)
        case .unknown:
            Chip(text: "base state unknown", symbol: "questionmark", health: .neutral)
                .help("Couldn't determine whether this branch is behind "
                      + "origin/\(item.baseRefName)")
        }
    }

    /// The command this branch's state calls for, or nil when it needs none.
    ///
    /// A conflicted branch gets the checkout as well, because resolving one
    /// means being on it; a branch that is merely behind does not, since
    /// **Update base** does that on GitHub's servers without a checkout at all.
    private var branchCommand: String? {
        switch item.branchState {
        case .conflicts:
            return BranchCommand.resolve(head: item.headRefName,
                                         base: item.baseRefName)
        case .needsRebase:
            return BranchCommand.rebase(onto: item.baseRefName)
        case .upToDate, .unknown:
            return nil
        }
    }

    private var branchCommandTitle: String {
        if case .conflicts = item.branchState { return "Resolve Command" }
        return "Rebase Command"
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
        ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
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
