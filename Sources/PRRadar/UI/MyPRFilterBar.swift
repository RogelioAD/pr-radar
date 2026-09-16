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

            Spacer()

            if state.isMyPRFiltered {
                Button {
                    state.myPRFilter = .all
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
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
