import SwiftUI
import PRRadarCore

/// Which repositories automatic review is allowed to touch.
///
/// An allowlist rather than a blocklist, because the two failure modes are not
/// symmetric: forgetting to add a repo costs a review that did not happen, and
/// forgetting to block one costs an automated comment on a stranger's pull
/// request, under your own name, that cannot be taken back.
///
/// A tick per repo rather than a text field, because the answer is almost
/// always one of the repos already in front of you — typing `owner/name` from
/// memory is a way to produce a list that quietly matches nothing. Repos that
/// are already allowed stay listed even when nothing of theirs is open, or
/// turning one off would mean waiting for a PR to appear first.
///
/// Draws rows only: the box around it supplies the padding and the width, the
/// same arrangement `LeadsEditorView` uses.
struct ReviewReposEditor: View {
    @ObservedObject var state: AppState

    private var repos: [String] {
        let live = Set(state.items.map(\.repo) + state.myPRs.map(\.repo))
        let allowed = Set(state.reviewRepos)
        return Array(live.union(allowed)).sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Layout.settingsRowSpacing) {
            Text("Repositories")

            if repos.isEmpty {
                Text("No repositories yet. They appear here as PRs arrive.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(repos, id: \.self) { repo in
                    Toggle(isOn: Binding(
                        get: { state.isReviewAllowed(repo) },
                        set: { state.setReviewAllowed(repo, $0) })
                    ) {
                        Text(RepoScope.shortName(repo))
                            .help(repo)
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("Review pull requests in \(repo) automatically")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
