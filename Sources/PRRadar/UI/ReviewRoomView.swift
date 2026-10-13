import SwiftUI
import PRRadarCore

/// Automatic review, in a room of its own.
///
/// It began as a section of the settings room, reached by a header button that
/// had to *open settings* to explain itself — a control whose only answer to
/// being pressed was to show you somewhere else. It is a room now for the same
/// reason the trophy shelf is one: it is a place in this app, with a state of
/// its own worth looking at, rather than a preference you set once.
///
/// Borrows the settings room's furniture — the boxed groups, the
/// label-then-control rows, `.controlSize(.small)` — because these are the same
/// kind of thing and a second visual language one button along would read as
/// wrong long before anyone could say why.
struct ReviewRoomView: View {
    @ObservedObject var state: AppState
    let onRowHeights: ([String: CGFloat]) -> Void

    @FocusState private var focus: ReviewField?

    private enum ReviewField: Hashable {
        case skill
        case resolveSkill
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.settingsSectionSpacing) {
                ForEach(state.reviewSections) { section in
                    group(section)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: RowHeightsKey.self,
                                    value: [state.rowKey(.review, section.id):
                                                geometry.size.height])
                            }
                        )
                }
            }
            .padding(.horizontal, Layout.settingsInset)
            .padding(.vertical, Layout.listPadding / 2)
            // Clicking the room itself puts the keyboard down. On the content
            // rather than behind it, for the reason the settings room gives: a
            // `ScrollView` consumes the press before anything layered under it
            // can see it.
            .contentShape(Rectangle())
            .onTapGesture { focus = nil }
        }
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(RowHeightsKey.self, perform: onRowHeights)
        // The fields write through on Return and on losing focus; closing the
        // drawer does neither, so they are committed here as well rather than
        // thrown away.
        .onDisappear { commitAll() }
    }

    @ViewBuilder
    private func group(_ section: ReviewSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(section.title, systemImage: section.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: Layout.settingsRowSpacing) {
                switch section {
                case .status: status
                case .skill: skill
                case .clones: clones
                case .resolve: resolve
                case .resolveAnswers: resolveAnswers
                case .repositories: ReviewReposEditor(state: state)
                }
            }
            .controlSize(.small)
            .frame(width: Layout.settingsContentWidth, alignment: .leading)
            .padding(Layout.settingsSectionPadding)
            .background(
                RoundedRectangle(cornerRadius: Layout.settingsSectionRadius,
                                 style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Layout.settingsSectionRadius,
                                 style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    // MARK: - Status

    /// Whether it is running, what it is doing, and what it needs before it
    /// can. The first group because it is the question the room is opened to
    /// answer.
    @ViewBuilder
    private var status: some View {
        row("Review automatically",
            help: "Run your review skill on every PR waiting on you, in the "
                + "repositories ticked below") {
            Toggle("Review automatically", isOn: Binding(
                get: { state.autoReviewEnabled },
                set: { wanted in
                    if wanted != state.autoReviewEnabled { state.toggleAutoReview() }
                }))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(!state.canAutoReview && !state.autoReviewEnabled)
                .accessibilityLabel("Review automatically")
        }

        if !state.canAutoReview {
            note(state.claudePath == nil
                 ? "Claude Code is not installed, so there is nothing to run."
                 : "Name a review skill below and this can be switched on.")
        }

        Divider()

        row("Now") {
            if let key = state.reviewInFlight,
               let running = state.items.first(where: { $0.pingKey == key }) {
                Chip(text: "\(running.repoShortName)#\(running.number)",
                     symbol: "wand.and.sparkles", health: .running)
            } else {
                Text(state.autoReviewEnabled ? "Idle" : "Off")
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        row("Claude Code") {
            HStack(spacing: 6) {
                if let path = state.claudePath {
                    Text(FolderPicker.display(path))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(path)
                } else {
                    Label("Not found", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Health.bad.tint)
                        .help("Looked in the usual places and asked your login "
                              + "shell. Point at it by hand if it lives "
                              + "somewhere else.")
                }
                Spacer(minLength: 4)
                Button(state.claudePath == nil ? "Locate…" : "Change…") { chooseClaude() }
                    .buttonStyle(.link)
                    .font(.system(size: 10))
                    .help("Choose the claude binary yourself")
            }
        }
    }

    /// Lets the developer name the binary when nothing found it for them.
    ///
    /// Worth a control of its own because the alternative is a dead end: the
    /// row says it is not installed, the feature will not switch on, and a
    /// developer looking straight at `claude` in their own terminal has no way
    /// to tell the app where it is. Hidden files are shown, because two of the
    /// commonest homes for it — `~/.claude/local` and `~/.nvm` — are hidden.
    private func chooseClaude() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.title = "Choose the claude binary"
        panel.prompt = "Use"
        if let current = state.claudePath {
            panel.directoryURL = URL(fileURLWithPath: current).deletingLastPathComponent()
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Prefs.claudePath = url.path
        state.claudePath = AppState.findClaude()
        // A path that turned out not to be runnable is not kept: it would sit
        // there outranking a perfectly good one the search can find.
        if state.claudePath == nil { Prefs.claudePath = nil }
    }

    // MARK: - Skill

    @ViewBuilder
    private var skill: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Run",
                help: "A review skill of your own, written to run headlessly: it "
                    + "has to answer in one pass — ask nothing, post nothing, and "
                    + "return the JSON schema PR Radar parses. An interactive one "
                    + "stalls and times out, /code-review among them.") {
                TextField("/your-review-skill", text: $state.reviewSkillDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .skill)
                    .onSubmit { state.commitReviewSkill() }
                    .accessibilityLabel("The review skill to run")
                    .frame(width: 180)
            }
            if !state.reviewSkillDraft.isEmpty && !isSkillValid {
                warning("Not a skill command — this will be put back")
            }
            note("One you wrote to run headlessly. An interactive skill stalls.")
        }
        .onChange(of: focus) { previous, _ in
            if previous == .skill { state.commitReviewSkill() }
        }

        Divider()

        // The two limits are one question asked twice — how much of this may
        // happen while you are not looking — so they are one group with one
        // line under them rather than two groups with a rule between.
        VStack(alignment: .leading, spacing: 4) {
            row("Spend limit",
                help: "The most one review may cost before the CLI stops it. A "
                    + "review of a substantial PR runs to a few dollars, and a cap "
                    + "below about $2 cuts every one off partway through. Zero "
                    + "means no limit.") {
                HStack(spacing: 4) {
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField("10", value: $state.reviewBudget,
                              format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .accessibilityLabel("Spend limit per review, in dollars")
                    Stepper("Spend limit", value: $state.reviewBudget, in: 0...100, step: 1)
                        .labelsHidden()
                }
            }
            row("Per hour",
                help: "How many reviews may start in any hour. Counted from when "
                    + "one starts, so a review that fails still spends its slot. "
                    + "Zero means no limit.") {
                HStack(spacing: 4) {
                    TextField("6", value: $state.reviewMaxPerHour, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .accessibilityLabel("Reviews that may start per hour")
                    Stepper("Reviews per hour", value: $state.reviewMaxPerHour,
                            in: 0...50, step: 1)
                        .labelsHidden()
                }
            }
            // Only the edges. The ordinary case is in the tooltips above; what
            // has to be on screen is a value that will not work and a value
            // that has taken the brakes off, because neither looks wrong.
            if state.reviewBudget > 0 && state.reviewBudget < 2 {
                caution("Below about $2 a review is cut off partway through.")
            }
            if state.reviewMaxPerHour == 0 {
                caution("No limit — everything eligible is reviewed as it arrives.")
            }
            // Said plainly rather than only in a tooltip: an escape hatch
            // nobody can see is one nobody uses.
            if state.reviewBudget > 0 || state.reviewMaxPerHour > 0 {
                note("0 removes either limit.")
            }
        }

        Divider()

        // Posting is the irreversible half, so it gets a choice of its own
        // rather than being folded into the switch above.
        VStack(alignment: .leading, spacing: 4) {
            row("When it finishes") {
                Picker("When it finishes", selection: $state.reviewMode) {
                    ForEach(AutoReviewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("What happens when a review finishes")
            }
            note(state.reviewMode.detail)
        }
    }

    // MARK: - Clones

    /// A menu that walks down the tree, rather than a field you type a path
    /// into from memory.
    ///
    /// Typing it was the first version and it is the wrong control for this
    /// question: a path typed from memory is either right or silently wrong,
    /// and "silently wrong" here means every review skipping with *no local
    /// clone* until somebody goes looking. Walking down means every step is a
    /// folder that demonstrably exists, and the line underneath answers the
    /// question actually being asked — not "is this a folder" but "are your
    /// clones in it".
    ///
    /// Each pick sets the folder outright rather than browsing towards a
    /// separate Choose button. There is no half-chosen state to get stuck in,
    /// and going one level too far is one press to undo.
    @ViewBuilder
    private var clones: some View {
        let current = state.reviewBrowsingFrom
        let subfolders = state.reviewSubfolders(of: current)

        VStack(alignment: .leading, spacing: 4) {
            row("Folder") {
                Menu {
                    if let parent = FolderPicker.parent(of: current) {
                        Button {
                            state.reviewWorkspace = parent
                        } label: {
                            Label("Up to \(FolderPicker.name(of: parent))",
                                  systemImage: "arrow.up")
                        }
                        Divider()
                    }

                    if subfolders.isEmpty {
                        Text("No subfolders")
                    } else {
                        ForEach(subfolders.prefix(FolderPicker.limit), id: \.self) { name in
                            Button(name) {
                                state.reviewWorkspace =
                                    (current as NSString).appendingPathComponent(name)
                            }
                        }
                        // A capped list that did not say so would be quietly
                        // claiming the rest are not there.
                        if subfolders.count > FolderPicker.limit {
                            Divider()
                            Text("…and \(subfolders.count - FolderPicker.limit) more")
                        }
                    }
                } label: {
                    Text(state.reviewWorkspace == nil
                         ? "Choose…"
                         : FolderPicker.display(current))
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 180)
                .help(current)
                .accessibilityLabel("The folder your repository clones live in")
            }
            .help("Both features read code from your own clones. A review takes a "
                  + "throwaway worktree and never touches your working tree; a "
                  + "resolve works in the checkout that already holds the branch, "
                  + "and refuses if there is anything in it.")

            // This one stays: it is the answer to the question actually being
            // asked, and it changes as you walk the tree. "Is this a folder" is
            // obvious; "are your clones in it" is not.
            note(state.reviewWorkspace == nil
                 ? "Pick the folder your clones live in."
                 : FolderPicker.summary(cloneCount: state.reviewCloneCount(in: current),
                                        subfolderCount: subfolders.count))
        }
    }

    // MARK: - Resolve

    /// What answers the threads on your own pull requests.
    ///
    /// A section rather than a room of its own, because it shares the clones
    /// folder, the `claude` binary and half the vocabulary of the one above it —
    /// and two rooms with the same three pickers in them would drift.
    ///
    /// There is deliberately **no "resolve automatically" switch**. The bots
    /// comment again after every push, so a resolver on a timer would answer
    /// its own fixes for ever and spend money doing it. This is pressed, from
    /// the row, or it does not happen.
    @ViewBuilder
    private var resolve: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Run",
                help: "A skill that answers review threads on your own pull "
                    + "requests: reads each one, fixes what it can, and replies. "
                    + "Its gates are answered for it below, so it never stops to "
                    + "ask.") {
                TextField("/resolve", text: $state.resolveSkillDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .resolveSkill)
                    .onSubmit { state.commitResolveSkill() }
                    .accessibilityLabel("The resolve skill to run")
                    .frame(width: 180)
            }
            if !state.resolveSkillDraft.isEmpty && !isResolveSkillValid {
                warning("Not a skill command — this will be put back")
            }
            note("A Resolve button on every PR of yours with open threads. "
                 + "Never runs on its own.")
        }
        .onChange(of: focus) { previous, _ in
            if previous == .resolveSkill { state.commitResolveSkill() }
        }

        Divider()

        VStack(alignment: .leading, spacing: 4) {
            row("When it finishes") {
                Picker("When it finishes", selection: $state.resolveMode) {
                    ForEach(ResolveMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("How much of a resolve run happens unattended")
            }
            note(state.resolveMode.detail)

            // Said once, under the two modes it is true of. Curated review
            // promises nothing has happened yet; curated resolve cannot, and a
            // reader who carries the first promise across to the second will be
            // wrong in a way that costs a push.
            if state.resolveMode.writesCode {
                caution("Edits your checkout and pushes. Refuses a tree with work in it.")
            }
        }

        Divider()

        VStack(alignment: .leading, spacing: 4) {
            row("Spend limit",
                help: "The most one resolve run may cost. More than a review's, "
                    + "because there is more in it. Zero means no limit.") {
                HStack(spacing: 4) {
                    Text("$").foregroundStyle(.secondary)
                    TextField("25", value: $state.resolveBudget,
                              format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .accessibilityLabel("Spend limit per resolve run, in dollars")
                    Stepper("Spend limit", value: $state.resolveBudget, in: 0...200, step: 5)
                        .labelsHidden()
                }
            }
            row("Give up after",
                help: "How long one run may take before it is asked to stop. Far "
                    + "longer than a review because there is more in it: the "
                    + "fixes, the repository's own test suite, and a commit "
                    + "behind a pre-commit hook that often runs the suite again. "
                    + "It is asked to stop and never killed — killing one "
                    + "mid-commit leaves a lock file in your repository.") {
                HStack(spacing: 4) {
                    TextField("90", value: $state.resolveTimeoutMinutes, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                        .accessibilityLabel("Minutes before a resolve run is stopped")
                    Text("min").foregroundStyle(.secondary)
                    Stepper("Give up after", value: $state.resolveTimeoutMinutes,
                            in: 5...240, step: 15)
                        .labelsHidden()
                }
            }
            note("A run that overruns is asked to stop, never killed.")
        }

        Divider()

        // Beside the timeout, because this is what the timeout is mostly spent
        // on. A one-file conflict took sixteen minutes and almost all of it was
        // the Android suite followed by a pre-commit hook running the Rust
        // workspace again — both correct, both what you would have skipped if
        // you had been sitting there.
        VStack(alignment: .leading, spacing: 4) {
            row("Checking") {
                Picker("Checking", selection: $state.resolveGates) {
                    ForEach(ResolveGates.allCases) { gates in
                        Text(gates.title).tag(gates)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("How much checking a resolve run does")
            }
            note(state.resolveGates.detail)
            if state.resolveGates.isUnverified {
                caution("Nothing is run locally. Your commit hooks still are.")
            }
        }
    }

    /// The questions your resolve skill would stop and ask, answered in advance.
    ///
    /// This section exists because of a specific failure: a skill with
    /// interactive gates, run headlessly, does not fail — it *waits*, for a
    /// quarter of an hour, and then times out having done nothing. Every
    /// control here is one of those gates, and the answer is passed into the
    /// session's framing so it never reaches the menu.
    @ViewBuilder
    private var resolveAnswers: some View {
        VStack(alignment: .leading, spacing: 4) {
            row("Work outside the PR's job") {
                Picker("Work outside the PR's job", selection: $state.resolveOutOfScope) {
                    ForEach(ResolveOutOfScope.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("What to do with out-of-scope comments")
            }
            note(state.resolveOutOfScope.detail)
        }

        Divider()

        VStack(alignment: .leading, spacing: 4) {
            row("An unsubmitted draft review") {
                Picker("An unsubmitted draft review", selection: $state.resolvePending) {
                    ForEach(ResolvePendingPolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                .accessibilityLabel("What to do about a pending review of your own")
            }
            note(state.resolvePending.detail)
        }

        Divider()

        // Rules, not controls — three of them, and they were three stacked
        // lines of grey under two pickers, which is the shape of a paragraph
        // nobody reads. One line says there are rules and the tooltip says what
        // they are, which is the right way round for things that cannot be
        // changed: knowing they exist is what matters on every glance, and
        // knowing exactly what they say matters once.
        Label("Four things this always does, whatever is picked above.",
              systemImage: "lock")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .help("""
                  A thread needing a product or design call is always left open.

                  Nothing is ever written to Asana — a ticket created with nobody \
                  watching is one nobody approved, so gaps are reported instead.

                  A reply citing a commit is held back until that commit is \
                  actually on the remote.

                  No gate is ever bypassed to make a fix land — no `--no-verify`, \
                  no lint suppression, no weakened assertion. Running fewer \
                  checks is yours to choose; defeating one that runs is not.
                  """)
    }

    // MARK: - Bits

    private var isSkillValid: Bool {
        ReviewSkill.normalized(state.reviewSkillDraft) != nil
    }

    private var isResolveSkillValid: Bool {
        ReviewSkill.normalized(state.resolveSkillDraft) != nil
    }

    private func commitAll() {
        state.commitReviewSkill()
        state.commitResolveSkill()
    }

    /// A line of body text under a control.
    ///
    /// The room's one rule about prose, and it took six groups to learn it: a
    /// line earns its place only when it **changes with the value** or
    /// **warns**. Everything else is the row's tooltip. The room had a
    /// paragraph under all fourteen controls, which is more words than
    /// controls, and a wall of tertiary grey is not read — it is scrolled past,
    /// taking the two lines that mattered with it.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// A value that will not work, or one that has taken the brakes off.
    /// Tinted, because neither looks wrong in the field it is typed into.
    private func caution(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(Health.attention.tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Said plainly rather than by refusing the keystroke: a field that
    /// silently discards what was typed leaves no way to tell a rejected value
    /// from one that was accepted and did nothing.
    private func warning(_ text: String) -> some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(.system(size: 10))
            .foregroundStyle(Health.bad.tint)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Label leading, control trailing — the settings room's row, because these
    /// are the same kind of thing.
    @ViewBuilder
    private func row<Content: View>(_ label: String,
                                    help: String? = nil,
                                    @ViewBuilder content: () -> Content) -> some View {
        let line = HStack(spacing: 6) {
            Text(label)
            Spacer(minLength: 8)
            content()
        }
        .frame(maxWidth: .infinity)

        if let help {
            line.help(help)
        } else {
            line
        }
    }
}
