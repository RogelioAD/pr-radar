import SwiftUI
import PRRadarCore

/// Which repositories the two unattended features are allowed to touch.
///
/// An allowlist rather than a blocklist, because the two failure modes are not
/// symmetric: forgetting to add a repo costs a review that did not happen, and
/// forgetting to block one costs an automated comment on a stranger's pull
/// request, under your own name, that cannot be taken back.
///
/// **Two ticks per repository, not one.** Safe-to-read and safe-to-write are
/// different questions, and one list would answer the second with an answer
/// given to the first — ticking a repo so a review could read it would quietly
/// also let an unattended session commit and push there. So the resolve column
/// starts empty even for a repository already ticked for review, and has to be
/// asked for on purpose.
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
        let allowed = Set(state.reviewRepos).union(state.resolveRepos)
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
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    Text("review")
                        .frame(width: Self.columnWidth)
                    Text("resolve")
                        .frame(width: Self.columnWidth)
                }
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

                ForEach(repos, id: \.self) { repo in
                    HStack(spacing: 4) {
                        Text(RepoScope.shortName(repo))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(repo)
                        Spacer(minLength: 4)
                        tick(isOn: Binding(get: { state.isReviewAllowed(repo) },
                                           set: { state.setReviewAllowed(repo, $0) }),
                             label: "Review pull requests in \(repo) automatically")
                        tick(isOn: Binding(get: { state.isResolveAllowed(repo) },
                                           set: { state.setResolveAllowed(repo, $0) }),
                             label: "Allow resolve runs to edit and push in \(repo)")
                    }
                }

                Text("Resolve writes. Separate tick on purpose.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .help("Safe-to-read and safe-to-write are different "
                          + "questions. Ticking a repository so a review may "
                          + "read it must not also let an unattended session "
                          + "commit and push there.")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Wide enough for the word above it, so the two columns line up with their
    /// headings rather than drifting with the length of a repository's name.
    private static let columnWidth: CGFloat = 46

    private func tick(isOn: Binding<Bool>, label: String) -> some View {
        Toggle("", isOn: isOn)
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: Self.columnWidth)
            .accessibilityLabel(label)
    }
}
