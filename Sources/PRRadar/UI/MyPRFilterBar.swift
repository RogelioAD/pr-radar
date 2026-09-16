import SwiftUI
import PRRadarCore

/// Sort and narrow the My PRs list.
struct MyPRFilterBar: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(MyPRSortOrder.allCases, id: \.self) { order in
                    Button {
                        state.myPRSortOrder = order
                    } label: {
                        if state.myPRSortOrder == order {
                            Label(order.label, systemImage: "checkmark")
                        } else {
                            Text(order.label)
                        }
                    }
                }
            } label: {
                FilterPill(symbol: state.myPRSortOrder.symbol,
                           text: state.myPRSortOrder.label, active: false)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                ForEach(MyPRFilter.allCases, id: \.self) { filter in
                    Button {
                        state.myPRFilter = filter
                    } label: {
                        if state.myPRFilter == filter {
                            Label(label(for: filter), systemImage: "checkmark")
                        } else {
                            Text(label(for: filter))
                        }
                    }
                }
            } label: {
                FilterPill(symbol: "line.3.horizontal.decrease",
                           text: state.myPRFilter.label,
                           active: state.isMyPRFiltered)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            RepoFilterMenu(state: state)

            Spacer()

            if state.isMyPRFiltered || state.isRepoFiltered {
                Button {
                    state.myPRFilter = .all
                    state.repoFilter = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear filters")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Layout.filterBarHeight)
    }

    /// Counts in the menu make it obvious which filters are worth picking.
    private func label(for filter: MyPRFilter) -> String {
        let matching = state.myPRs.filter(filter.matches).count
        return filter == .all ? filter.label : "\(filter.label) (\(matching))"
    }
}

/// Narrows both tabs to one repository. Shared by both filter bars.
///
/// The menu shows the full `owner/name` so two repos with the same short name
/// cannot be confused; the pill shows the short name, which is all that fits.
struct RepoFilterMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        Menu {
            Button { state.repoFilter = nil } label: {
                if state.repoFilter == nil {
                    Label("All repos", systemImage: "checkmark")
                } else {
                    Text("All repos")
                }
            }
            if !state.repos.isEmpty { Divider() }
            ForEach(state.repos, id: \.self) { repo in
                Button {
                    // Picking the active repo again clears the filter.
                    state.repoFilter = (state.repoFilter == repo) ? nil : repo
                } label: {
                    if state.repoFilter == repo {
                        Label(label(for: repo), systemImage: "checkmark")
                    } else {
                        Text(label(for: repo))
                    }
                }
            }
        } label: {
            FilterPill(
                symbol: "folder",
                text: state.repoFilter.map(AppState.shortRepoName) ?? "All repos",
                active: state.isRepoFiltered
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    /// Counts for both tabs, so it is obvious what picking a repo will show.
    private func label(for repo: String) -> String {
        let counts = state.repoCount(repo)
        return "\(repo)  —  \(counts.reviews) review, \(counts.mine) mine"
    }
}

/// Shared pill used by both tabs' filter bars.
struct FilterPill: View {
    let symbol: String
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
            Text(text).font(.system(size: 10.5, weight: active ? .semibold : .regular))
                .lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(active ? Color.accentColor : .secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(active ? Color.accentColor.opacity(0.14)
                                  : Color.primary.opacity(0.07))
        )
    }
}
