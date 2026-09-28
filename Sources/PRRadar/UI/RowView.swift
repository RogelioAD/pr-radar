import SwiftUI
import PRRadarCore

struct RowView: View {
    let item: ReviewItem
    let now: Date
    /// Which account surfaced this row, or nil when saying so would be noise.
    var accountLabel: String?
    /// Where the automatic review has got to, or nil when there has not been
    /// one — in which case this row is exactly what it always was.
    var review: AutoReviewRecord?
    /// Where this row sits in the queue while it waits its turn, or nil when it
    /// is not waiting. Not part of `review`: a row waiting to be reviewed has
    /// no record yet, which is exactly why it used to say nothing.
    var waiting: AutoReviewQueue.Waiting?
    /// Whether one of this row's buttons is mid-round-trip. Every button is
    /// disabled while it is, because none of them change the record until the
    /// mutation returns — so the row would otherwise go on offering the press
    /// that is already in the air.
    var sending = false
    /// Whether the findings list is open.
    ///
    /// Owned by `AppState` rather than by this row, though it is still a way of
    /// looking at the row and still not persisted. The panel has to know: a
    /// findings list doubles the drawer's width, and the frame calculation
    /// cannot see a row's `@State`.
    var showingFindings = false
    var onToggleFindings: (() -> Void)?
    var onAction: ((AutoReviewCoordinator.Action) -> Void)?
    var onSetFinding: ((String, Bool) -> Void)?
    var onSetTier: ((FindingTier, Bool) -> Void)?
    let onOpen: () -> Void

    @State private var hovering = false
    /// Approving is irreversible and this panel can be clicked while it is
    /// being dragged, so that one button asks twice.
    @State private var confirmingApprove = false
    /// Which findings have their code open, by finding id. One at a time would
    /// have been simpler, but comparing two findings in the same file is the
    /// commonest reason to open the code at all.
    @State private var openCode: Set<String> = []

    private var staleness: Staleness { Staleness.of(item.pingedAt, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            primary
            if let review {
                strip(review)
                if showingFindings, review.isAwaitingSelection { findings(review) }
            } else if let waiting {
                queueStrip(waiting)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.07) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .onHover { hovering = $0 }
        .draggable(PRLink(url: item.url)) {
            Text(item.title).font(.system(size: 12)).padding(6)
        }
        .contextMenu {
            Button("Open in Browser") { onOpen() }
            Button("Copy Link") { Clipboard.copy(item.url.absoluteString) }
            Button("Copy Title") { Clipboard.copy(item.title) }
        }
        .accessibilityElement(children: .contain)
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: RowHeightsKey.self,
                    value: [RowHeightKeys.key(surface: .reviews, id: item.id): geometry.size.height])
            }
        )
    }

    /// The row as it has always been.
    ///
    /// The tap that opens the PR lives here rather than on the whole row, which
    /// it used to. Once a row can grow buttons, a gesture on the container is a
    /// gesture behind them — and a press meant for Approve that also opened a
    /// browser tab would be the kind of bug nobody reports and everybody
    /// works around. `MyPRRowView` already taps its content for the same reason.
    private var primary: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(staleness.tint)
                .frame(width: 3)
                .clipShape(Capsule())

            avatar

            VStack(alignment: .leading, spacing: 3) {
                // Underlined while the row is hovered, so it reads as the
                // link it is. Driven by the row rather than by a hover on the
                // text itself: the whole row opens the PR, and a hover tracked
                // on the Text proved unreliable where the row's is not.
                Text(TitleText.attributed(item.title, underlined: hovering))
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                // One metadata line rather than two.
                //
                // The author was on a line of its own, directly under a line
                // carrying the number and the repo — while the avatar two
                // columns to the left already said whose PR this was. Three
                // lines of chrome for a title, and one of them saying a second
                // time what the picture said first.
                HStack(spacing: 5) {
                    Text("#\(item.number)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(item.repoShortName)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .layoutPriority(1)
                    Text(item.authorLogin)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let accountLabel {
                        // A symbol rather than bare text: this row already
                        // shows an author login, and two logins side by side
                        // with nothing to tell them apart is worse than one.
                        Chip(text: accountLabel, symbol: "person.crop.circle",
                             health: .neutral)
                    }
                    if item.isDraft {
                        // The same chip `MyPRRowView` has always used for this.
                        // Hand-rolled here, it was a third pill height on a row
                        // that should only ever have one.
                        Chip(text: "draft", health: .neutral)
                    }
                }
            }

            Spacer(minLength: 4)

            Text(TimeAgo.short(since: item.pingedAt, now: now))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(staleness.tint)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(staleness.tint.opacity(0.14), in: Capsule())
                .help("Review requested \(TimeAgo.long(since: item.pingedAt, now: now))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(item.title), pull request \(item.number) "
                            + "in \(item.repoShortName) by \(item.authorLogin), "
                            + "requested \(TimeAgo.long(since: item.pingedAt, now: now))")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - The automatic review

    /// What a row says while it waits for the worker to reach it.
    ///
    /// Its own strip rather than a status on the record, because there is no
    /// record: nothing has happened to this pull request yet. One review runs
    /// at a time, so the second eligible one can sit for ten minutes looking
    /// exactly like a pull request the feature had decided to ignore.
    @ViewBuilder
    private func queueStrip(_ waiting: AutoReviewQueue.Waiting) -> some View {
        ChipFlow(spacing: 5, lineSpacing: 4) {
            Chip(text: waiting.label, symbol: "clock", health: .neutral)
                .help(waiting == .next
                      ? "Starts as soon as the review in progress finishes"
                      : "Waiting behind the reviews ahead of it")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What the review has done, and what is left for the reader to decide.
    ///
    /// Two bands, not one. What the review *found* and what you can *do* about
    /// it are different kinds of thing, and running them through a single
    /// `ChipFlow` let the boundary fall wherever the wrapping happened to put
    /// it — "Comment only" could end up beside a nit count, with the rest of
    /// the decisions on the line below. Giving the decisions their own flow
    /// puts the break where the meaning already is.
    @ViewBuilder
    private func strip(_ review: AutoReviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ChipFlow(spacing: 5, lineSpacing: 4) {
                switch review.status {
                case .queued:
                    Chip(text: "queued for review", symbol: "clock", health: .neutral)
                case .running:
                    Chip(text: "reviewing…", symbol: "wand.and.sparkles", health: .running)
                    runTime(review)
                case .skipped:
                    Chip(text: review.failure ?? "not reviewed", health: .neutral)
                case .failed:
                    Chip(text: "review failed", symbol: "exclamationmark.triangle", health: .bad)
                        .help(review.failure ?? "")
                    runTime(review)
                    RowButton(title: "Retry", symbol: "arrow.clockwise", health: .running) {
                        onAction?(.rerun)
                    }
                case .ready where review.foundNothing:
                    // Its own branch, and its own sentence. "review ready" over
                    // an empty findings list is a row announcing work and then
                    // not saying what the work found — the one thing anybody
                    // wants from a review that turned nothing up.
                    Chip(text: "no findings", symbol: "checkmark.circle", health: .good)
                        .help("The review ran and found nothing worth commenting on")
                    runTime(review)
                    // Beside the chip rather than on the band below, because it
                    // is the only decision this row has and the line it would
                    // otherwise sit on would hold nothing else.
                    approve
                case .ready:
                    Chip(text: "review ready", symbol: "wand.and.sparkles", health: .running)
                    runTime(review)
                    tiers(review)
                    if review.isAwaitingSelection {
                        RowButton(title: showingFindings ? "Hide findings" : "Choose findings",
                                  symbol: showingFindings ? "chevron.up" : "chevron.down",
                                  health: .neutral) {
                            onToggleFindings?()
                        }
                    }
                    // Shown even with nothing ticked, and disabled there: it
                    // is how the row says what it is holding. The way *off* a
                    // row with nothing ticked is the decisions below, not this.
                    if review.selection.total > 0 {
                        RowButton(title: sending ? "Sending…" : postTitle(review),
                                  symbol: sending ? "paperplane.fill" : "paperplane",
                                  health: .running,
                                  enabled: review.canPost && !sending) {
                            onAction?(.post)
                        }
                        .help(sending
                              ? "Already on its way to GitHub"
                              : review.canPost
                                ? "Post the ticked findings as one review"
                                : "Nothing ticked — decide below instead")
                    }
                case .posted:
                    Chip(text: "PR Radar left a review", symbol: "text.bubble", health: .running)
                        .help("Opened on the PR — decide below, and this row stays until you do")
                    runTime(review)
                    tiers(review)
                case .dismissed:
                    Chip(text: "done", symbol: "checkmark", health: .good)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if review.offersDecisions {
                ChipFlow(spacing: 5, lineSpacing: 4) {
                    decisions(review)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// The stopwatch: how long the review has been going, or how long it took.
    ///
    /// A review runs for minutes with nothing to show for it, and "reviewing…"
    /// alone cannot tell a long diff from a wedged session. Green or red once
    /// it stops, so the row says how it went and what it cost in one glance.
    @ViewBuilder
    private func runTime(_ review: AutoReviewRecord) -> some View {
        if review.status == .running, let startedAt = review.startedAt {
            // Its own timeline, redrawing this chip once a second and nothing
            // else. The app's shared clock ticks every thirty seconds — right
            // for "requested 28m ago", useless for something being watched —
            // and speeding that up would redraw every row in the drawer to
            // animate one number.
            TimelineView(.periodic(from: startedAt, by: 1)) { context in
                stopwatch(review, now: context.date, health: .running)
            }
        } else {
            stopwatch(review, now: Date(), health: review.status == .failed ? .bad : .good)
        }
    }

    @ViewBuilder
    private func stopwatch(_ review: AutoReviewRecord,
                           now: Date,
                           health: Health) -> some View {
        if let seconds = review.runTime(now: now) {
            Chip(text: RunTime.clock(seconds), symbol: "stopwatch", health: health)
                .help(review.status == .running
                      ? "Running for \(RunTime.spoken(seconds))"
                      : "Took \(RunTime.spoken(seconds))")
        }
    }

    private func postTitle(_ review: AutoReviewRecord) -> String {
        let (chosen, total) = review.selection
        guard total > 0 else { return "Post review" }
        return chosen == total ? "Post all \(total)" : "Post \(chosen) of \(total)"
    }

    /// The findings, tier by tier, each one a tick.
    ///
    /// Grouped by tier rather than listed flat because the tier is the whole
    /// basis on which somebody decides: three priority findings are read one
    /// way and nine nits another, and a flat list makes you re-sort them in
    /// your head. The heading doubles as the way to take a whole tier at once,
    /// which is what "all three nits, actually" needs in a 440pt drawer.
    @ViewBuilder
    private func findings(_ review: AutoReviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(FindingTier.allCases, id: \.self) { tier in
                let group = review.findings(in: tier)
                if !group.isEmpty {
                    tierHeader(tier, group: group)
                    ForEach(group) { prepared in
                        findingRow(prepared)
                    }
                }
            }
        }
        .padding(.leading, 13)
        .padding(.top, 2)
    }

    private func tierHeader(_ tier: FindingTier, group: [PreparedFinding]) -> some View {
        let allOn = group.allSatisfy(\.isSelected)
        return Button {
            onSetTier?(tier, !allOn)
        } label: {
            HStack(spacing: 4) {
                Chip(text: "\(group.count) \(tier.label)", health: tier.health)
                Text(allOn ? "none" : "all")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .pressable()
        .help(allOn ? "Untick every \(tier.label)" : "Tick every \(tier.label)")
    }

    @ViewBuilder
    private func findingRow(_ prepared: PreparedFinding) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            findingTick(prepared)
            if openCode.contains(prepared.id), let excerpt = prepared.excerpt {
                DiffHunkView(excerpt: excerpt).padding(.leading, 15).padding(.trailing, 2)
            }
        }
    }

    /// The tick and what it is a tick *for*.
    ///
    /// Two buttons rather than one: the checkbox and summary toggle the tick,
    /// and the file:line beneath opens the code. They were one button, and a
    /// disclosure nested inside a button that toggles a tick is a click whose
    /// meaning depends on which pixel it landed on.
    private func findingTick(_ prepared: PreparedFinding) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Button {
                onSetFinding?(prepared.id, !prepared.isSelected)
            } label: {
                Image(systemName: prepared.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundStyle(prepared.isSelected ? Color.accentColor : .secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pressable()
            .help(prepared.isSelected ? "Do not post this one" : "Post this one too")

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    onSetFinding?(prepared.id, !prepared.isSelected)
                } label: {
                    Text(prepared.finding.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(prepared.isSelected ? .primary : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(prepared.finding.recommendation)

                    HStack(spacing: 4) {
                        if let location = prepared.location {
                            locationLabel(prepared, location: location)
                        }
                        // Said out loud, because "it will be posted, just not
                        // where you are looking" is not something to discover
                        // on the PR afterwards.
                        if !prepared.isAnchored {
                            // Tinted rather than tertiary. It sat in the same
                            // grey as the file path beside it, so the one row
                            // that behaves differently from every other looked
                            // exactly like them — and the difference was found
                            // on the pull request afterwards instead of here.
                            Text("summary only")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Health.attention.tint)
                                .help("Not in this pull request's diff. It will be "
                                      + "posted in the summary rather than against "
                                      + "its line.")
                        }
                        if prepared.finding.suggestion != nil && prepared.isAnchored {
                            Image(systemName: "wand.and.stars.inverse")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .help("Carries a suggested fix")
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `file:line`, and the way into the code when there is code to show.
    ///
    /// Plain text when there is not. A record written before excerpts were kept
    /// has none, and neither has a finding that could not be anchored — in both
    /// cases a chevron would promise something the row cannot deliver.
    @ViewBuilder
    private func locationLabel(_ prepared: PreparedFinding, location: String) -> some View {
        if prepared.excerpt != nil {
            let open = openCode.contains(prepared.id)
            Button {
                if open { openCode.remove(prepared.id) } else { openCode.insert(prepared.id) }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                    Text(location)
                        .font(.system(size: 9, design: .monospaced))
                }
                .foregroundStyle(open ? AnyShapeStyle(Color.accentColor)
                                      : AnyShapeStyle(.tertiary))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pressable()
            .help(open ? "Hide the code" : "Show the code this is about")
        } else {
            Text(location)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    private func tiers(_ review: AutoReviewRecord) -> some View {
        ForEach(FindingTier.allCases, id: \.self) { tier in
            let count = review.count(tier)
            if count > 0 {
                Chip(text: "\(count) \(tier.label)", health: tier.health)
            }
        }
    }

    /// The four ways out. Until one of them is pressed the row stays put —
    /// which is the whole point of the feature: the comment is a prompt, not a
    /// dismissal.
    ///
    /// All four once a review has gone out. Exactly one — approving — when
    /// none has, because the other three act on a review that is not there.
    ///
    /// Approving is also the only one that would still *work*: it submits a
    /// real review, so GitHub drops the request and the row leaves the way it
    /// always does. A button that merely dismissed the record would have left
    /// the row sitting in the list with a tick on it, on a pull request still
    /// waiting to be reviewed.
    @ViewBuilder
    private func decisions(_ review: AutoReviewRecord) -> some View {
        if review.hasPostedReview {
            RowButton(title: "Comment only", symbol: "text.bubble", health: .neutral,
                      enabled: !sending) {
                onAction?(.commentOnly)
            }
            .help("Let the posted review stand. Nothing further is sent, and the row goes.")
        }

        approve

        if review.hasPostedReview {
            RowButton(title: "Request changes", symbol: "exclamationmark.bubble",
                      health: .bad, enabled: item.nodeID != nil && !sending) {
                onAction?(.requestChanges)
            }
            .help("Submit a review requesting changes, using the priority findings")

            RowButton(title: "Re-run", symbol: "arrow.clockwise", health: .running,
                      enabled: !sending) {
                onAction?(.rerun)
            }
            .help("Review again and replace the review already posted")
        }
    }

    /// Two presses, because it satisfies branch protection and tells a
    /// colleague you read their code — and because this panel can be clicked
    /// while it is being dragged.
    ///
    /// One button, drawn in two places: on the decisions band with the rest,
    /// and beside the chip on a review that found nothing, where it is the only
    /// decision there is. Extracted rather than written twice so the
    /// confirmation cannot be true in one of them and not the other.
    private var approve: some View {
        RowButton(title: confirmingApprove ? "Approve?" : "Mark approved",
                  symbol: "checkmark.seal",
                  health: .good,
                  enabled: item.nodeID != nil && !sending) {
            if confirmingApprove {
                confirmingApprove = false
                onAction?(.approve)
            } else {
                confirmingApprove = true
                Task {
                    try? await Task.sleep(for: .seconds(3))
                    confirmingApprove = false
                }
            }
        }
        .help(item.nodeID == nil
              ? "This PR arrived without an id, so it cannot be acted on from here"
              : "Submit an approving review")
    }

    private var avatar: some View {
        AsyncImage(url: item.authorAvatarURL) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Circle().fill(Color.secondary.opacity(0.25))
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(Circle())
    }
}
