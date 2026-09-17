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
                   failed: !state.failedAccounts.isEmpty,
                   account: nil)
            ForEach(state.accounts) { account in
                button(id: account.id,
                       label: account.login.isEmpty ? "account" : account.login,
                       failed: state.failedAccounts.contains(account.id),
                       account: account)
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
    /// Carried in the tooltip rather than shown as a mark.
    ///
    /// A missing `read:org` is a standing condition the app cannot fix and the
    /// user may have chosen, so a permanent badge would become furniture — and
    /// the day something was actually wrong it would not be seen. The hover is
    /// exactly when someone is asking why this account reads zero.
    private func hint(_ label: String, failed: Bool, account: Account?) -> String {
        if failed { return "\(label): could not be read this refresh" }
        if account?.canReadTeams == false {
            return "\(label): missing read:org — reviews requested of a team "
                 + "will not appear here"
        }
        return label
    }

    private func button(id: String?, label: String, failed: Bool,
                        account: Account?) -> some View {
        let selected = state.accountFilter == id
        return Button { state.accountFilter = id } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 10.5,
                                  weight: failed || selected ? .semibold : .regular))
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
            // The whole label carries the failure, not just the mark beside it.
            // Two accounts on one host can differ by a single character —
            // `octocat` and `octocät`, or a name typed twice with one letter
            // out — and an 8pt glyph next to near-identical words asks the
            // reader to spot the difference before they can act on it. Colour
            // answers "which one is broken" without reading either name.
            .foregroundStyle(failed ? Health.bad.tint
                                    : (selected ? Color.primary : Color.secondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(failed ? Health.bad.tint.opacity(0.14)
                                 : (selected ? Color.primary.opacity(0.10) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(hint(label, failed: failed, account: account))
    }
}
