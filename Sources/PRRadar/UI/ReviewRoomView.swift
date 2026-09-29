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
            Text(state.claudePath == nil
                 ? "Claude Code is not installed, so there is nothing to run."
                 : "Name a review skill below and this can be switched on.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
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
            row("Run") {
                TextField("/code-review", text: $state.reviewSkillDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .skill)
                    .onSubmit { state.commitReviewSkill() }
                    .accessibilityLabel("The review skill to run")
                    .frame(width: 180)
            }
            if !state.reviewSkillDraft.isEmpty && !isSkillValid {
                warning("Not a skill command — this will be put back")
            }
            Text("Whichever review skill you already have. It runs headlessly, so "
                 + "one that stops to ask questions will time out — `/code-review` "
                 + "is known to work.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: focus) { previous, _ in
            if previous == .skill { state.commitReviewSkill() }
        }

        Divider()

        VStack(alignment: .leading, spacing: 4) {
            row("Spend limit",
                help: "The most one review may cost before the CLI stops it. "
                    + "Zero means no limit.") {
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
            // Named because the number is meaningless without it, and because
            // the default used to be a twentieth of this.
            Text(state.reviewBudget > 0 && state.reviewBudget < 2
                 ? "A real review of a real PR runs to a few dollars — below about $2 "
                   + "it will be cut off partway through."
                 : "A review of a substantial PR runs to a few dollars. Zero means no limit.")
                .font(.system(size: 10))
                .foregroundStyle(state.reviewBudget > 0 && state.reviewBudget < 2
                                 ? Health.attention.tint : .init(.tertiaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
        }

        Divider()

        // Next to the spend limit, because they are the same question asked
        // twice: how much of this may happen while you are not looking. This
        // one had an answer and no row — PRs came back "hourly limit reached"
        // with nothing on screen admitting a limit existed.
        VStack(alignment: .leading, spacing: 4) {
            row("Reviews per hour",
                help: "How many reviews may start in any hour. Zero means no limit.") {
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
            // Which edge of it is worth saying changes with the value: at zero
            // the thing to know is that nothing is pacing this, and otherwise
            // it is that a review which failed still spent its slot.
            //
            // The non-zero line names the zero, the way the spend limit's does.
            // Saying it only *once the value is zero* tells you what you have
            // already done and never that you could: the escape hatch was
            // reachable only by hovering for a tooltip, or by guessing.
            Text(state.reviewMaxPerHour == 0
                 ? "No limit — everything eligible is reviewed as fast as it arrives, "
                   + "at whatever that costs."
                 : "Counted from when a review starts, so one that fails still spends "
                   + "its slot. PRs past the limit wait, and say so. Set it to 0 for "
                   + "no limit.")
                .font(.system(size: 10))
                .foregroundStyle(state.reviewMaxPerHour == 0
                                 ? Health.attention.tint : .init(.tertiaryLabelColor))
                .fixedSize(horizontal: false, vertical: true)
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
            Text(state.reviewMode.detail)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
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

            Text(state.reviewWorkspace == nil
                 ? "Pick the folder your clones live in."
                 : FolderPicker.summary(cloneCount: state.reviewCloneCount(in: current),
                                        subfolderCount: subfolders.count))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Text("A review reads the code in your own checkout, in a throwaway "
                 + "worktree — your working tree is never touched. A repo with no "
                 + "clone says so on the row rather than being reviewed blind.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Bits

    private var isSkillValid: Bool {
        ReviewSkill.normalized(state.reviewSkillDraft) != nil
    }

    private func commitAll() {
        state.commitReviewSkill()
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
