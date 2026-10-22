import SwiftUI
import PRRadarCore

struct RowView: View {
    let item: ReviewItem
    let now: Date
    /// Whether the keyboard is on this row. Drawn as a ring rather than a
    /// fill, so it sits over the hover highlight instead of fighting it: the
    /// pointer and the keyboard can be on two different rows at once and both
    /// have to stay legible.
    var isSelected = false
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
    /// Adds a comment of your own. Returns whether it landed, so the fields
    /// keep what was typed when it did not.
    var onAddComment: ((PreparedFinding) -> Bool)?
    var onRemoveComment: ((String) -> Void)?
    /// Puts this row down until the given time, or nil where snoozing is not
    /// offered. Passed in rather than reached for, so the row stays a view.
    var onSnooze: ((Date) -> Void)?
    /// Brings it back now. Non-nil exactly when this row is asleep, which is
    /// also what decides whether the row wears its wake chip.
    var onWake: (() -> Void)?
    /// When this row wakes, if it is asleep.
    var wakesAt: Date?
    /// What the row says about having been opened, or nil if it has not been.
    var openedLabel: String?
    var openedHealth: Health = .neutral
    var openedHelp: String?
    /// Forgets that it was opened, for the row that says so.
    var onForgetOpened: (() -> Void)?
    /// The plain-English reading for a piece of text, or nil for its own words.
    ///
    /// A lookup rather than a flag and a store, so this row cannot accidentally
    /// read one while the lens is off: `AppState.lensReading` returns nil then,
    /// and there is nothing else here to consult.
    var lensReading: (String) -> String? = { _ in nil }
    /// This row's key in the measurement maps, so the findings on it can report
    /// where the drawer may stop.
    var rowKey: String = ""
    let onOpen: () -> Void

    @State private var hovering = false
    /// Approving is irreversible and this panel can be clicked while it is
    /// being dragged, so that one button asks twice.
    @State private var confirmingApprove = false
    /// Which findings have their code open, by finding id. One at a time would
    /// have been simpler, but comparing two findings in the same file is the
    /// commonest reason to open the code at all.
    @State private var openCode: Set<String> = []
    /// What is in the "other" box, kept here rather than in the record: an
    /// unfinished sentence is not a comment, and persisting one would redraw
    /// every row in the drawer on every keystroke.
    @State private var draft = ""

    private var staleness: Staleness { Staleness.of(item.pingedAt, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            primary
            if let wakesAt { sleepBand(wakesAt) }
            if let openedLabel { openedBand(openedLabel) }
            if let since = item.sinceReview { sinceBand(since) }
            if let review {
                strip(review)
                if showingFindings, review.isAwaitingSelection { findings(review) }
            } else if let waiting {
                queueStrip(waiting)
            }
        }
        .rowCutSpace(rowKey)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Color.primary.opacity(0.07) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 0)
        )
        .onHover { hovering = $0 }
        .draggable(PRLink(url: item.url)) {
            Text(item.title).font(.system(size: 12)).padding(6)
        }
        .contextMenu {
            Button("Open in Browser") { onOpen() }
            if let diff = item.sinceReview?.incrementalDiff(of: item.url) {
                Button("Open Changes Since Your Review") { NSWorkspace.shared.open(diff) }
            }
            Divider()
            if let onWake {
                Button("Wake Now", action: onWake)
            } else if let onSnooze {
                Menu("Snooze") {
                    ForEach(SnoozeOption.allCases, id: \.self) { option in
                        Button(option.label) { onSnooze(option.wake(from: now)) }
                    }
                }
            }
            Divider()
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

                // One line of what the author wrote, under the line saying
                // which pull request this is. Dimmed and clipped to one line:
                // it is context for the title rather than a second title, and
                // a row that grew three lines of somebody's template would
                // cost more than it told you. The rest is in the tooltip.
                if let summary = item.summary {
                    Text(summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .help(summary)
                }

                if let signals = item.signals { triage(signals) }
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
        .accessibilityLabel(spokenLabel)
        .accessibilityAddTraits(.isButton)
    }

    /// What the review will cost, and whether it is worth starting.
    ///
    /// Its own band under the metadata line rather than more pills on it. That
    /// line already carries a number, a repository, a login and sometimes two
    /// chips, and these are a different kind of thing from all of them: it
    /// says *which* pull request this is, and this says *what you are in for*.
    ///
    /// A `ChipFlow` for the reason the My PRs row uses one — three chips and a
    /// long repository name is a row that has to wrap rather than truncate the
    /// words that make it worth reading.
    @ViewBuilder
    private func triage(_ signals: ReviewSignals) -> some View {
        ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
            Chip(text: signals.sizeLabel, symbol: "plusminus",
                 health: signals.weight)
                .help(signals.sizeHelp)

            if let checks = signals.checks {
                Chip(text: checks.label, symbol: checks.symbol, health: checks.health)
                    .help(checks.isFailing
                          ? "CI has already failed on this head commit"
                          : "GitHub's rollup for the head commit")
            }

            // Said either way. "Nobody else was asked" is the more useful half
            // and it is the half a count alone cannot express — a row with no
            // reviewer chip would read as a row nobody had got round to
            // measuring, which is what a missing signal already means here.
            Chip(text: Self.reviewerText(signals.otherReviewers),
                 symbol: signals.otherReviewers == 0 ? "person" : "person.2",
                 health: .neutral)
                .help(Self.reviewerHelp(signals.otherReviewers))

            if signals.approvals > 0 {
                Chip(text: "\(signals.approvals) approved", symbol: "checkmark.seal",
                     health: .good)
                    .help(Self.approvalHelp(signals.approvals))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private static func reviewerText(_ count: Int) -> String {
        count == 0 ? "only you" : "\(count) other" + (count == 1 ? "" : "s")
    }

    private static func reviewerHelp(_ count: Int) -> String {
        guard count > 0 else { return "Nobody else is being waited on for this one" }
        let verb = count == 1 ? " reviewer is" : " reviewers are"
        return "\(count)\(verb) also being waited on"
    }

    private static func approvalHelp(_ count: Int) -> String {
        let who = count == 1 ? "1 reviewer" : "\(count) reviewers"
        return "Already approved by \(who) — yours may not be the one holding it up"
    }

    /// What a sleeping row says about when it comes back.
    ///
    /// A row you put down still has to say what you did to it and when it
    /// undoes itself. The whole bargain of the snooze is that the count goes
    /// quiet without anything going missing, and a sleeping row that looked
    /// identical to a waking one would be holding up neither half.
    @ViewBuilder
    private func sleepBand(_ wakesAt: Date) -> some View {
        ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
            Chip(text: "wakes \(TimeAgo.until(wakesAt, now: now))", symbol: "zzz",
                 health: .neutral)
                .help("Snoozed. It comes back on its own, and a new review "
                      + "request brings it back at once.")
            if let onWake {
                RowButton(title: "Wake now", symbol: "sun.max",
                          health: .running, action: onWake)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// That you started this one and did not finish.
    ///
    /// The weakest claim the app can make and the only one it witnessed: you
    /// opened it. Never that you read it, never that you got anywhere.
    @ViewBuilder
    private func openedBand(_ label: String) -> some View {
        ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
            Chip(text: label, symbol: "book", health: openedHealth)
                .help(openedHelp ?? "")
            if let onForgetOpened {
                // Because the record can be wrong in the one direction that
                // matters: you opened it, decided it was not yours, and told
                // somebody so in a channel this app cannot see. Nothing else
                // clears it short of reviewing a pull request you are not
                // going to review.
                RowButton(title: "Not mine", symbol: "xmark",
                          health: .neutral, action: onForgetOpened)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// What has landed since you last reviewed this one.
    ///
    /// Its own band, outside `primary`, rather than another chip in the triage
    /// flow. Everything in `primary` sits under the tap that opens the pull
    /// request, and this chip is a link of its own to a different page — a
    /// press meant for the incremental diff that also opened the whole diff
    /// behind it is the bug nobody reports and everybody works around. The
    /// review strip is outside for the same reason.
    @ViewBuilder
    private func sinceBand(_ since: SinceReview) -> some View {
        ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
            if let diff = since.incrementalDiff(of: item.url) {
                Button { NSWorkspace.shared.open(diff) } label: {
                    Chip(text: since.label, symbol: since.symbol, health: since.health)
                }
                .buttonStyle(.plain)
                .pressable()
                .help(since.help(now: now))
                .accessibilityLabel("\(since.label). Opens just what has changed.")
            } else {
                // No anchor, so no link. The sentence is still worth saying —
                // it is the difference between re-reading nine hundred lines
                // and knowing you have to.
                Chip(text: since.label, symbol: since.symbol, health: since.health)
                    .help(since.help(now: now))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The whole row, spoken.
    ///
    /// Assembled here rather than in the modifier it feeds. Built inline it
    /// was a four-way `+` chain of interpolations inside a view builder, which
    /// is the shape the type checker gives up on — and it gave up on this one.
    private var spokenLabel: String {
        let when = TimeAgo.long(since: item.pingedAt, now: now)
        let who = "in \(item.repoShortName) by \(item.authorLogin)"
        return "\(item.title), pull request \(item.number) \(who), requested \(when)"
            + triageSpoken
    }

    /// The triage band, spoken. Kept beside the band rather than inlined into
    /// the row's label so the two cannot drift apart.
    private var triageSpoken: String {
        guard let signals = item.signals else { return "" }
        var parts = ["\(signals.lines) lines across \(signals.changedFiles) files"]
        if let checks = signals.checks { parts.append(checks.label) }
        parts.append(signals.otherReviewers == 0
                     ? "no other reviewers"
                     : "\(signals.otherReviewers) other reviewers")
        if signals.approvals > 0 { parts.append("\(signals.approvals) already approved") }
        return ", " + parts.joined(separator: ", ")
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
        ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
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
            ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
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
                    rerun
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
                    // Last, after the thing this row is for. A review you have
                    // read and do not believe is the commonest reason to want
                    // another one, and until now the only way to ask was to
                    // post the one you distrusted first.
                    rerun
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
                ChipFlow(spacing: ChipMetrics.spacing, lineSpacing: ChipMetrics.lineSpacing) {
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
        let authored = Set(review.authored.map(\.id))
        VStack(alignment: .leading, spacing: 6) {
            ForEach(FindingTier.allCases, id: \.self) { tier in
                let group = review.findings(in: tier)
                if !group.isEmpty {
                    tierHeader(tier, group: group)
                    ForEach(group) { prepared in
                        findingRow(prepared, isAuthored: authored.contains(prepared.id))
                    }
                }
            }
            other(review)
        }
        .padding(.leading, 13)
        .padding(.top, 2)
    }

    /// The thing the review missed.
    ///
    /// Last, under the nits, because that is where you arrive having read
    /// everything the skill had to say — which is the moment you know what it
    /// did not say. Until now the findings list was a closed question: you
    /// could decline what was found and could not add to it, so the one
    /// sentence you actually wanted to leave meant opening GitHub.
    ///
    /// **One field.** It had three — a comment, a file and a line — so the
    /// thing could post inline beside the skill's findings. That was wrong
    /// twice over: typing a path into a 440pt drawer is slow and is the part
    /// you get wrong, and a path GitHub cannot resolve takes the *whole* review
    /// down with it, since it all goes out as one mutation. What you want to
    /// add is usually about the pull request rather than one line of it, so it
    /// goes in the summary and the two fields that made it fragile are gone.
    @ViewBuilder
    private func other(_ review: AutoReviewRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Chip(text: "other", symbol: "pencil", health: .neutral)
                Text("something it missed")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }

            HStack(alignment: .bottom, spacing: 4) {
                TextField("What you want to say", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .font(.system(size: 10))
                    .accessibilityLabel("A comment of your own")
                RowButton(title: "Add", symbol: "plus", health: .neutral,
                          enabled: composed != nil) {
                    add()
                }
                .help(composed == nil
                      ? "Type something first"
                      : "Add it to the list above, ticked")
            }

            note("Goes in the review's summary, in your own words.")
        }
        .padding(.top, 4)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The comment the field currently adds up to, or nil while it does not add
    /// up to one. Both the Add button's enablement and the press itself read
    /// this, so a disabled button and a refused press cannot disagree.
    private var composed: PreparedFinding? {
        AutoReviewComment.authored(text: draft)
    }

    private func add() {
        guard let comment = composed else { return }
        // Cleared only on success. A comment refused because an identical one
        // is already in the list must not also take the text away, leaving
        // nothing on screen to explain why nothing happened.
        if onAddComment?(comment) == true { draft = "" }
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
    private func findingRow(_ prepared: PreparedFinding, isAuthored: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            findingTick(prepared, isAuthored: isAuthored)
            if openCode.contains(prepared.id), let excerpt = prepared.excerpt {
                DisclosedCode(excerpt: excerpt)
            }
        }
        // Each finding is a place the drag may land, the same way each comment
        // is on My PRs. A row with eight findings open offered one stop before
        // this, between "closed" and "all eight".
        .rowCut(rowKey)
    }

    /// The tick and what it is a tick *for*.
    ///
    /// Two buttons rather than one: the checkbox and summary toggle the tick,
    /// and the file:line beneath opens the code. They were one button, and a
    /// disclosure nested inside a button that toggles a tick is a click whose
    /// meaning depends on which pixel it landed on.
    private func findingTick(_ prepared: PreparedFinding, isAuthored: Bool) -> some View {
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
                    // The tick beside this still posts the finding's own words.
                    // What the lens changes is what you read, never what goes.
                    LensText(source: prepared.finding.summary,
                             reading: lensReading(prepared.finding.summary),
                             lineLimit: 2,
                             dimmed: !prepared.isSelected)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                    HStack(spacing: 4) {
                        if let location = prepared.location {
                            locationLabel(prepared, location: location)
                        }
                        // Said out loud, because "it will be posted, just not
                        // where you are looking" is not something to discover
                        // on the PR afterwards.
                        // Not on a comment you wrote: unanchored is what one
                        // *is*, not something that went wrong with it. The
                        // warning exists for a skill finding that named a file
                        // and could not be pinned to it.
                        if !prepared.isAnchored && !isAuthored {
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
                        // Yours, and so deletable — which the skill's own
                        // findings are not. Unticking one is a decision about
                        // a review and is worth keeping on the row; a sentence
                        // you typed by mistake is just a mistake.
                        if isAuthored {
                            Image(systemName: "pencil")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                                .help("You wrote this one")
                            Button {
                                onRemoveComment?(prepared.id)
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.tertiary)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .pressable()
                            .help("Remove it")
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
        let open = openCode.contains(prepared.id)
        CodeToggle(location: location, hasCode: prepared.excerpt != nil, isOpen: open) {
            if open { openCode.remove(prepared.id) } else { openCode.insert(prepared.id) }
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

    /// Review it again, and throw away whatever is on the row now.
    ///
    /// One button, drawn in three places: on a failed row, where it reads as
    /// Retry; on the decisions band of a posted review, where it also retires
    /// the review already sent; and here, on a finished review nobody has acted
    /// on yet — which is where it was missing, and is the likeliest moment to
    /// want it. Reading `2 priority · 5 mild` and not believing it was, until
    /// now, a reason to post a review you distrusted just to earn the button
    /// that would replace it.
    ///
    /// Nothing is superseded from here: `supersede` returns early without a
    /// `reviewNodeID`, and a review that has not been posted has none. So the
    /// help text promises a fresh run and not a replacement.
    ///
    /// Deliberately not the two-press confirmation `approve` wears. That dance
    /// exists because approving is irreversible and this is not — a re-run
    /// spends money and discards findings that can be produced again, which is
    /// a cost, not a consequence. Ticks already made do go, and that is what
    /// the help text has to say out loud.
    private var rerun: some View {
        RowButton(title: "Re-run", symbol: "arrow.clockwise", health: .running,
                  enabled: !sending) {
            onAction?(.rerun)
        }
        .help("Review again from scratch. What is on the row now, including "
              + "anything you have ticked, is thrown away.")
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
