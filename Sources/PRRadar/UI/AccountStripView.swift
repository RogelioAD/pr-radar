import SwiftUI
import PRRadarCore

/// Chooses which account the drawer — and the badge — is scoped to.
///
/// A strip of its own rather than more entries in the tab strip. `DrawerTab` is
/// an axis of work (what you owe, what you own) and an account is an axis of
/// identity; one control carrying both would put "Reviews" and "personal" side
/// by side as if they were alternatives, and picking either would have to mean
/// un-picking the other.
///
/// Shown only above one account, because a strip offering a single choice is a
/// control that cannot be used — and on those machines the app looks and
/// behaves exactly as it did before any of this.
struct AccountStripView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            button(id: nil,
                   label: "All",
                   failed: !state.failedAccounts.isEmpty)
            ForEach(state.accounts) { account in
                button(id: account.id,
                       label: account.login.isEmpty ? "account" : account.login,
                       failed: state.failedAccounts.contains(account.id))
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(height: Layout.accountStripHeight)
    }

    /// The warning mark is the whole point of the strip when something is wrong.
    /// An account that could not be read contributes nothing, and a tab reading
    /// `personal 0` is indistinguishable from an account with nothing waiting —
    /// which is the one reading that must never be produced by a failure.
    private func button(id: String?, label: String, failed: Bool) -> some View {
        let selected = state.accountFilter == id
        return Button { state.accountFilter = id } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
                    .lineLimit(1)
                if failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Health.bad.tint)
                } else {
                    Text("\(state.accountCount(id))")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .padding(.horizontal, 3.5)
                        .padding(.vertical, 0.5)
                        .background(
                            Capsule().fill(Color.primary.opacity(selected ? 0.16 : 0.10))
                        )
                }
            }
            .foregroundStyle(selected ? Color.primary : Color.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(selected ? Color.primary.opacity(0.10) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(failed ? "\(label): could not be read this refresh" : label)
    }
}
