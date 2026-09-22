import SwiftUI
import PRRadarCore

/// The room's text fields, so one owner can say which of them has the keyboard
/// — and take it back when the reader clicks somewhere that is not a field.
enum SettingsField: Hashable {
    case releaseRepo
    case leadSearch
}

/// Attaches a tooltip only when there is one.
private struct OptionalHelp: ViewModifier {
    let text: String?

    func body(content: Content) -> some View {
        if let text {
            content.help(text)
        } else {
            content
        }
    }
}

/// The settings room: everything that used to be a context-menu item or a
/// `defaults write`, in one place.
///
/// Built from stock controls — `Toggle`, `Picker`, `TextField`, `Button` — at
/// `.controlSize(.small)` rather than from the app's own chips and pills.
/// The rest of the drawer is custom because it is drawing something macOS has no
/// control for; a settings panel is not that, and a hand-drawn switch in a
/// window full of real ones is the kind of thing that reads as wrong long before
/// anyone can say why. `.small` is also what keeps them honest next to 11pt
/// rows: it is the system's own compact metric, so the type stays the system's
/// rather than being overridden to a number that merely looks close.
struct SettingsView: View {
    @ObservedObject var state: AppState
    let onRowHeights: ([String: CGFloat]) -> Void
    let onResetBadgeSize: () -> Void
    /// Changing a lead changes what every row's lead chip says, so the list has
    /// to be rebuilt — the setting is not about the app, it is about the data.
    let onRefresh: () -> Void

    @Environment(\.openURL) private var openURL

    /// Which field holds the keyboard, for the whole room rather than per
    /// field.
    ///
    /// Hoisted here because releasing focus is not something a text field can
    /// do for itself: clicking a piece of the panel that is not a control
    /// leaves an `NSTextField` first responder, so the ring stays lit and the
    /// selection stays blue on a field the user has visibly walked away from.
    /// One owner for both fields is what lets the background clear whichever
    /// of them is holding it.
    @FocusState private var focus: SettingsField?

    var body: some View {
        ScrollView {
            VStack(spacing: Layout.settingsSectionSpacing) {
                ForEach(state.settingsSections) { section in
                    group(section)
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: RowHeightsKey.self,
                                    value: [state.rowKey(.settings, section.id):
                                                geometry.size.height])
                            }
                        )
                }
            }
            .padding(.horizontal, Layout.settingsInset)
            .padding(.vertical, Layout.listPadding / 2)
            // Clicking the room itself puts the keyboard down.
            //
            // On the content, not behind it: a `ScrollView` consumes the press
            // before anything layered underneath can see it, so a handler in
            // its background never fires and the field keeps its ring while the
            // caret goes — which looks like a bug rather than like focus.
            // Here, a press on a real control is that control's and stops
            // there; only the gaps and the labels fall through to this.
            .contentShape(Rectangle())
            .onTapGesture { focus = nil }
        }
        // Nothing to scroll when the drawer is tall enough to show every group,
        // and a panel that rubber-bands with no overflow reads as broken.
        .scrollBounceBehavior(.basedOnSize)
        .onPreferenceChange(RowHeightsKey.self, perform: onRowHeights)
        // The field writes through on Return and on losing focus; closing the
        // drawer does neither, so it is committed here as well rather than
        // thrown away.
        .onDisappear { state.commitUpdateRepo() }
    }

    // MARK: - Groups

    /// Header above the box rather than inside it, which is where a grouped
    /// form on this platform puts it.
    private func group(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(section.title, systemImage: section.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: Layout.settingsRowSpacing) {
                switch section {
                case .accounts: accounts
                case .general: general
                case .leads: leads
                case .appearance: appearance
                case .updates: updates
                }
            }
            // The type scale comes from here and is deliberately not set as a
            // point size: `.small` is the platform's own compact metric, and it
            // carries the labels as well as the controls — which lands the rows
            // just under the drawer's 12.5pt title without this room having to
            // guess a number that merely looks close. Measured against a hard
            // 11.5, which came out *larger* than the default it replaced.
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

    // MARK: - General

    @ViewBuilder
    private var general: some View {
        // Bound through a method rather than to a stored flag: enabling writes
        // a LaunchAgent and can fail, and the switch has to end up wherever the
        // filesystem actually landed.
        toggle("Open at login",
               help: "Start PR Radar automatically when you log in",
               isOn: Binding(get: { state.opensAtLogin },
                             set: { state.setOpensAtLogin($0) }))

        Divider()

        toggle("Celebrate a cleared queue",
               help: "Show the achievement banner when the last review is done",
               isOn: $state.celebrateCleared)
    }

    // MARK: - Accounts

    /// Who the app is looking as, and whether each of them is actually working.
    ///
    /// Read-only on purpose. Accounts are `gh`'s to add and remove — this app
    /// has always borrowed that login rather than owning one — so a control
    /// here would either lie about what it can do or shell out to a CLI on the
    /// user's behalf. What it can honestly offer is the thing `gh auth status`
    /// makes you leave the app to find out: which identities are in play, what
    /// each is contributing, and which one is the reason a count looks short.
    ///
    /// Shown at one account as well as many, unlike the filter bar's picker.
    /// A picker offering a single choice is a control that cannot be used; a
    /// *statement* of which account you are looking as is worth reading even
    /// when there is only one, and it is where the `read:org` warning finally
    /// has a home that is not a tooltip.
    @ViewBuilder
    private var accounts: some View {
        if state.accounts.isEmpty {
            Text("No account. PR Radar reads the login from `gh auth status`.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            ForEach(Array(state.accounts.enumerated()), id: \.element.id) { index, account in
                if index > 0 { Divider() }
                accountRow(account)
            }
        }
    }

    private func accountRow(_ account: Account) -> some View {
        let counts = state.accountCounts(account.id)
        let problem = state.accountProblem(account)
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(account.login.isEmpty ? "account" : account.login)
                if account.isActive {
                    // `gh`'s active account is the one every other tool on this
                    // machine will use, which is worth knowing when two of them
                    // disagree about what you can see.
                    Text("active")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.primary.opacity(0.10)))
                }
                Spacer(minLength: 8)
                Text("\(counts.reviews) review, \(counts.mine) mine")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 4) {
                if account.host != Leads.defaultHost {
                    Text(account.host).foregroundStyle(.tertiary)
                }
                if let problem {
                    Label(problem, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Health.bad.tint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.system(size: 10))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Leads

    /// The whole of James Wall's editor, in a box instead of a window.
    ///
    /// The token comes from an account that can see this repo rather than from
    /// whichever one `gh` has active: with two identities logged in the repo
    /// may belong to the other, and a search a token cannot satisfy returns an
    /// empty list rather than an error — which reads as "no members".
    @ViewBuilder
    private var leads: some View {
        LeadsEditorView(
            repos: state.leadRepos,
            focus: $focus,
            search: { ref, text in
                guard let account = state.account(forHost: ref.host),
                      let token = Accounts.token(for: account)
                else { throw TokenError.notFound }
                return try await GitHubClient(token: token)
                    .searchMembers(repo: ref.repo, matching: text)
            },
            onChange: onRefresh)
    }

    // MARK: - Appearance

    @ViewBuilder
    private var appearance: some View {
        // Tagged with `MascotID?` throughout, including "None": a picker whose
        // selection is optional matches on the tag's type, and a tag of the
        // non-optional type never equals the binding — which shows as a picker
        // that will not display what is selected.
        row("Mascot",
            help: "Which character keeps you company, on the badge and in the drawer") {
            Picker("Mascot", selection: $state.mascot) {
                ForEach(MascotID.allCases, id: \.self) { id in
                    Text(Mascot.named(id).name).tag(Optional(id))
                }
                Divider()
                Text("None").tag(MascotID?.none)
            }
            .pickerStyle(.menu)
            .labelsHidden()
            // Sized to its contents rather than stretched across the box: a
            // pop-up as wide as the drawer looks like a text field, and its
            // chevron ends up nowhere near the name it belongs to.
            .fixedSize()
        }

        Divider()

        row("Badge size", help: "Drag any corner of the badge to resize it") {
            Text("\(Int(state.badgeTileSize.rounded())) pt")
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Button("Reset", action: onResetBadgeSize)
                .disabled(!state.hasCustomBadgeSize)
                .accessibilityLabel("Reset badge size")
                .help(state.hasCustomBadgeSize
                      ? "Go back to following the Dock's icon size"
                      : "Already following the Dock's icon size")
        }
    }

    // MARK: - Updates

    @ViewBuilder
    private var updates: some View {
        // The running version is in the footer, where the room's own identity
        // belongs; this row answers the other half — what is published.
        row("Latest release") {
            switch state.updateStatus {
            case .available(let version, let url):
                Button("Get \(version.description)") { openURL(url) }
                    .help("Open the release page for \(version.description)")
            case .upToDate:
                Text("Up to date").foregroundStyle(.secondary)
            // Not checked yet, or the check failed — and those must not be told
            // apart by guessing, so neither claims to be current.
            case .unknown:
                Text("Not checked").foregroundStyle(.secondary)
            }
        }

        Divider()

        VStack(alignment: .leading, spacing: 4) {
            row("Releases from") {
                TextField("owner/repo", text: $state.updateRepoDraft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .releaseRepo)
                    .onSubmit { state.commitUpdateRepo() }
                    .accessibilityLabel("Repository to check for releases")
                    .frame(width: 190)
            }
            // Said plainly rather than by refusing the keystroke: a field that
            // silently discards what was typed leaves no way to tell a rejected
            // value from one that was accepted and did nothing.
            if !isDraftValid {
                Label("Not a repository — this will be put back",
                      systemImage: "exclamationmark.triangle")
                    .font(.system(size: 10))
                    .foregroundStyle(Health.bad.tint)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .help("Which repository's releases the update check watches — change it "
              + "if you are running a fork")
        // Committing on blur as well as on Return is what makes the field
        // behave the way every other settings field on this platform does.
        .onChange(of: focus) { previous, _ in
            if previous == .releaseRepo { state.commitUpdateRepo() }
        }
    }

    private var isDraftValid: Bool {
        ReleaseSource.normalized(state.updateRepoDraft) != nil
    }

    // MARK: - Rows

    /// Label on the leading edge, control on the trailing one, which is where
    /// this platform's settings put them.
    ///
    /// Written out rather than left to `LabeledContent`, which only lays a row
    /// out this way inside a `Form`: on its own it sets the control directly
    /// after the label, so each row started at a different x and the box read
    /// as a ragged list rather than as a column of settings.
    @ViewBuilder
    private func row<Content: View>(_ label: String,
                                    help: String? = nil,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(label)
            Spacer(minLength: 8)
            content()
        }
        .frame(maxWidth: .infinity)
        // Applied only when there is something to say: `.help("")` still
        // arms a tooltip, and one that opens empty reads as a glitch.
        .modifier(OptionalHelp(text: help))
    }

    /// The same row, with a switch in it.
    ///
    /// A switch rather than the checkbox a bare `Toggle` draws: every other row
    /// in this room puts its control on the trailing edge, and a checkbox is
    /// stuck to the leading edge of its own label. The label is therefore the
    /// row's, and the toggle keeps it only for VoiceOver.
    private func toggle(_ label: String, help: String,
                        isOn: Binding<Bool>) -> some View {
        row(label, help: help) {
            Toggle(label, isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityLabel(label)
        }
    }
}
