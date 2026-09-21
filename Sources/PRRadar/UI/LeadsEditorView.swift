import SwiftUI
import PRRadarCore

/// Edits the leads for each repo. Suggestions come from the repo's members,
/// but any typed login can be added.
struct LeadsEditorView: View {
    let repos: [String]
    let search: (String, String) async throws -> [Member]
    let onChange: () -> Void

    @State private var repo: String
    @State private var leads = Prefs.leadsByRepo
    @State private var text = ""
    @State private var suggestions: [Member] = []
    @State private var searchError: String?

    init(repos: [String], search: @escaping (String, String) async throws -> [Member],
         onChange: @escaping () -> Void) {
        // Repos that already have leads stay editable even if no PR is open.
        let known = Set(repos.map(Leads.key(for:)))
        let extra = Prefs.leadsByRepo.keys.filter { !known.contains($0) }
        let all = (repos + extra).sorted { $0.lowercased() < $1.lowercased() }
        self.repos = all
        self.search = search
        self.onChange = onChange
        _repo = State(initialValue: all.first ?? "")
    }

    private var current: [String] { Leads.leads(for: repo, in: leads) }

    private var visibleSuggestions: [Member] {
        suggestions.filter { member in
            !current.contains { $0.caseInsensitiveCompare(member.login) == .orderedSame }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if repos.isEmpty {
                Text("No repos yet. Open a PR and it will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Repo", selection: $repo) {
                    ForEach(repos, id: \.self) { Text($0).tag($0) }
                }

                if current.isEmpty {
                    Text("No leads. PRs in this repo show no lead status.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    FlowChips(items: current) { remove($0) }
                }

                TextField("Add a lead — type to search members", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { add(text) }

                if let searchError {
                    Text(searchError).font(.caption).foregroundStyle(.secondary)
                }

                if !visibleSuggestions.isEmpty {
                    List(visibleSuggestions) { member in
                        Button { add(member.login) } label: {
                            HStack {
                                Text(member.login)
                                if let name = member.name, !name.isEmpty {
                                    Text(name).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(height: 150)
                }
            }
        }
        .padding(16)
        .frame(width: 380)
        .task(id: "\(repo)|\(text)") { await runSearch() }
    }

    private func runSearch() async {
        guard !repo.isEmpty else { return }
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
        leads = Leads.add(login, to: repo, in: leads)
        commit()
        text = ""
    }

    private func remove(_ login: String) {
        leads = Leads.remove(login, from: repo, in: leads)
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
