import SwiftUI
import PRRadarCore

/// Edits the leads for each repo. Suggestions come from the repo's members,
/// but any typed login can be added.
///
/// Draws rows only — no padding, no width, no window. It is a section of the
/// settings room now, and the box around it supplies all three. It had its own
/// `NSWindow` first, which is the thing this app had otherwise stopped doing:
/// a second window for one setting, reached from a menu item, while every
/// other setting lived in the drawer.
struct LeadsEditorView: View {
    let repos: [RepoRef]
    let search: (RepoRef, String) async throws -> [Member]
    let onChange: () -> Void
    /// Owned by the room, so clicking away from this field releases it — see
    /// `SettingsView.focus`.
    @FocusState.Binding var focus: SettingsField?

    @State private var repo: RepoRef?
    @State private var leads = Prefs.leadsByRepo
    @State private var text = ""
    @State private var suggestions: [Member] = []
    @State private var searchError: String?

    init(repos: [RepoRef], focus: FocusState<SettingsField?>.Binding,
         search: @escaping (RepoRef, String) async throws -> [Member],
         onChange: @escaping () -> Void) {
        _focus = focus
        // Repos that already have leads stay editable even if no PR is open.
        let known = Set(repos.map(\.id))
        let extra = Prefs.leadsByRepo.keys
            .filter { !known.contains($0) }
            .compactMap(Self.parse(storedKey:))
        self.repos = RepoRef.sorted(repos + extra)
        self.search = search
        self.onChange = onChange
        _repo = State(initialValue: RepoRef.sorted(repos + extra).first)
    }

    /// Turns a stored key back into the repo it names.
    ///
    /// Three segments is `host/owner/repo`; two is the unqualified key this was
    /// stored under before hosts were part of it, which is read as the default
    /// host. Anything else is not a key this app wrote and is dropped rather
    /// than guessed at — a malformed entry should not become a row offering to
    /// edit a repository that does not exist.
    private static func parse(storedKey key: String) -> RepoRef? {
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 3: return RepoRef(repo: "\(parts[1])/\(parts[2])", host: String(parts[0]))
        case 2: return RepoRef(repo: key)
        default: return nil
        }
    }

    private var current: [String] {
        guard let repo else { return [] }
        return Leads.leads(for: repo.repo, host: repo.host, in: leads)
    }

    /// Enough to pick from without the section growing taller than the list
    /// the drawer is there to show.
    private static let suggestionLimit = 4

    private var visibleSuggestions: [Member] {
        suggestions.filter { member in
            !current.contains { $0.caseInsensitiveCompare(member.login) == .orderedSame }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.settingsRowSpacing) {
            if repos.isEmpty {
                Text("No repos yet. Open a pull request and it will appear here.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Repo", selection: $repo) {
                    ForEach(repos) { Text($0.label).tag(Optional($0)) }
                }
                .pickerStyle(.menu)

                if current.isEmpty {
                    Text("No leads. PRs in this repo show no lead status.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    FlowChips(items: current) { remove($0) }
                }

                TextField("Add a lead — type to search members", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .focused($focus, equals: .leadSearch)
                    .onSubmit { add(text) }

                if let searchError {
                    Text(searchError).font(.caption).foregroundStyle(.secondary)
                }

                // A short plain list, not a `List` with a fixed height: this
                // sits inside the room's own scroller, and a nested one traps
                // the wheel and reports a height the drawer cannot measure.
                // Capped because a repo with four hundred mentionable users is
                // not offering a choice, it is offering a scroll.
                ForEach(visibleSuggestions.prefix(Self.suggestionLimit)) { member in
                    Button { add(member.login) } label: {
                        HStack(spacing: 4) {
                            Text(member.login)
                            if let name = member.name, !name.isEmpty {
                                Text(name).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: "\(repo?.id ?? "")|\(text)") { await runSearch() }
        // The room can be opened before the first fetch has named a repo, and
        // a picker left on nothing once the list arrives is a section that
        // looks broken until it is touched.
        .onChange(of: repos) { _, list in
            if repo == nil { repo = list.first }
        }
    }

    private func runSearch() async {
        guard let repo else { return }
        // Debounce: a newer keystroke cancels this task during the sleep.
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !Task.isCancelled else { return }
        do {
            let found = try await search(repo, text.trimmingCharacters(in: .whitespaces))
            suggestions = found
            searchError = nil
        } catch is CancellationError {
            return
        } catch {
            suggestions = []
            searchError = "Couldn't load members. You can still type a login and press Return."
        }
    }

    private func add(_ login: String) {
        guard let repo else { return }
        leads = Leads.add(login, to: repo.repo, host: repo.host, in: leads)
        commit()
        text = ""
    }

    private func remove(_ login: String) {
        guard let repo else { return }
        leads = Leads.remove(login, from: repo.repo, host: repo.host, in: leads)
        commit()
    }

    private func commit() {
        Prefs.leadsByRepo = leads
        onChange()
    }
}

/// Wrapping row of removable login chips.
private struct FlowChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { login in
                HStack(spacing: 4) {
                    Text(login).lineLimit(1)
                    Button { onRemove(login) } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(login)")
                }
                .font(.callout)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
        }
    }
}
