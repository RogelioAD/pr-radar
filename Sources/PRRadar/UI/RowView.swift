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
    var onAction: ((AutoReviewCoordinator.Action) -> Void)?
    var onSetFinding: ((String, Bool) -> Void)?
    var onSetTier: ((FindingTier, Bool) -> Void)?
    let onOpen: () -> Void

    @State private var hovering = false
    /// Approving is irreversible and this panel can be clicked while it is
    /// being dragged, so that one button asks twice.
    @State private var confirmingApprove = false
    /// Whether the findings list is open. Row-local and not persisted: it is a
    /// way of looking at the row, not a fact about the review.
    @State private var showingFindings = false

    private var staleness: Staleness { Staleness.of(item.pingedAt, now: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            primary
            if let review {
                strip(review)
                if showingFindings, review.isAwaitingSelection { findings(review) }
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
                case .skipped:
                    Chip(text: review.failure ?? "not reviewed", health: .neutral)
                case .failed:
                    Chip(text: "review failed", symbol: "exclamationmark.triangle", health: .bad)
                        .help(review.failure ?? "")
                    RowButton(title: "Retry", symbol: "arrow.clockwise", health: .running) {
                        onAction?(.rerun)
                    }
                case .ready:
                    Chip(text: "review ready", symbol: "wand.and.sparkles", health: .running)
                    tiers(review)
                    if review.isAwaitingSelection {
                        RowButton(title: showingFindings ? "Hide findings" : "Choose findings",
                                  symbol: showingFindings ? "chevron.up" : "chevron.down",
                                  health: .neutral) {
                            showingFindings.toggle()
                        }
                    }
                    RowButton(title: postTitle(review), symbol: "paperplane",
                              health: .running, enabled: review.selection.chosen > 0) {
                        onAction?(.post)
                    }
                    .help(review.selection.chosen > 0
                          ? "Post the ticked findings as one review"
                          : "Tick at least one finding first")
                case .posted:
                    Chip(text: "PR Radar left a review", symbol: "text.bubble", health: .running)
                        .help("Opened on the PR — decide below, and this row stays until you do")
                    tiers(review)
                case .dismissed:
                    Chip(text: "done", symbol: "checkmark", health: .good)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if review.status == .posted {
                ChipFlow(spacing: 5, lineSpacing: 4) {
                    decisions
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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
        .help(allOn ? "Untick every \(tier.label)" : "Tick every \(tier.label)")
    }

    private func findingRow(_ prepared: PreparedFinding) -> some View {
        Button {
            onSetFinding?(prepared.id, !prepared.isSelected)
        } label: {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: prepared.isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10))
                    .foregroundStyle(prepared.isSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(prepared.finding.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(prepared.isSelected ? .primary : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 4) {
                        if let location = prepared.location {
                            Text(location)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        // Said out loud, because "it will be posted, just not
                        // where you are looking" is not something to discover
                        // on the PR afterwards.
                        if !prepared.isAnchored {
                            Text("summary only")
                                .font(.system(size: 9))
                                .foregroundStyle(.tertiary)
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(prepared.finding.recommendation)
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
    @ViewBuilder
    private var decisions: some View {
        RowButton(title: "Comment only", symbol: "text.bubble", health: .neutral) {
            onAction?(.commentOnly)
        }
        .help("Let the posted review stand. Nothing further is sent, and the row goes.")

        // Two presses, because it satisfies branch protection and tells a
        // colleague you read their code — and because this panel can be
        // clicked while it is being dragged.
        RowButton(title: confirmingApprove ? "Approve?" : "Mark approved",
                  symbol: "checkmark.seal",
                  health: .good,
                  enabled: item.nodeID != nil) {
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

        RowButton(title: "Request changes", symbol: "exclamationmark.bubble",
                  health: .bad, enabled: item.nodeID != nil) {
            onAction?(.requestChanges)
        }
        .help("Submit a review requesting changes, using the priority findings")

        RowButton(title: "Re-run", symbol: "arrow.clockwise", health: .running) {
            onAction?(.rerun)
        }
        .help("Review again and replace the review already posted")
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
