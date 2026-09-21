import SwiftUI
import PRRadarCore

/// Chooses which account the drawer — and the badge — is scoped to.
///
/// A pill in the filter bar, beside the repo one, rather than a strip of its
/// own above the tab strip. An account *is* a scope in the sense a repository
/// is — "I am working as this identity today" — so the control that picks one
/// should be the control that picks the other, and the two then sit under one
/// "clear filters" button reading as what they are: two ways of narrowing the
/// same list.
///
/// The strip this replaces cost a permanent 27pt band on exactly the machines
/// the feature is for. In a 440pt floating panel that is a whole row of the
/// list, spent on a control that is used rarely and read never — and it had to
/// be subtracted from the drawer's chrome on every surface, which is one more
/// thing for the geometry to get wrong.
///
/// Shown only above one account, because a picker offering a single choice is a
/// control that cannot be used — and on those machines the bar looks and
/// behaves exactly as it did before any of this.
struct AccountFilterMenu: View {
    @ObservedObject var state: AppState

    var body: some View {
        Menu {
            Button { state.accountFilter = nil } label: {
                if state.accountFilter == nil {
                    Label(allLabel, systemImage: "checkmark")
                } else {
                    Text(allLabel)
                }
            }
            Divider()
            ForEach(state.accounts) { account in
                Button {
                    // Picking the active account again clears the scope.
                    state.accountFilter =
                        (state.accountFilter == account.id) ? nil : account.id
                } label: {
                    if state.accountFilter == account.id {
                        Label(label(for: account), systemImage: "checkmark")
                    } else {
                        Text(label(for: account))
                    }
                }
            }
        } label: {
            // The short round is said with the symbol and the tooltip, not
            // with colour: these pills are `Menu` labels, and a menu paints its
            // own label's foreground — a tint set on the pill, on its leaves,
            // or on the menu itself is dropped. Tried all three.
            FilterPill(symbol: symbol,
                       text: pillText,
                       active: state.accountFilter != nil)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(helpText)
    }

    /// Two figures for "all", one for a single identity, and the warning mark
    /// when a count is short.
    ///
    /// The glyph tracks what the pill is actually saying rather than naming the
    /// control: a lone bust beside the words "All accounts" is a small
    /// contradiction, and this pill spends most of its life in that state.
    private var symbol: String {
        if state.isPartial { return "exclamationmark.triangle.fill" }
        // Filled once scoped to one identity, hollow while showing all. That
        // is not decoration: `active` is supposed to colour this pill and
        // cannot — a `Menu` paints its own label — so the weight of the glyph
        // is the only thing left that says a scope is on.
        return state.accountFilter == nil
            ? "person.crop.circle" : "person.crop.circle.fill"
    }

    private var allLabel: String { "All accounts  —  \(state.accountCount(nil))" }

    private var pillText: String {
        guard let id = state.accountFilter,
              let account = state.accounts.first(where: { $0.id == id })
        else { return "All accounts" }
        return Accounts.shortLogin(account.login)
    }

    /// What is wrong with an account, said in the menu rather than saved for a
    /// tooltip: a menu is already open because somebody is asking which
    /// identity they are looking at, and that is exactly when the answer
    /// "this one did not load" is worth having.
    private func label(for account: Account) -> String {
        let name = account.login.isEmpty ? "account" : account.login
        if state.failedAccounts.contains(account.id) {
            return "\(name)  —  could not be read"
        }
        // A missing read:org is a standing condition the app cannot fix and the
        // user may have chosen, so it is stated where it is being asked about
        // rather than badged permanently somewhere it would become furniture.
        if account.canReadTeams == false {
            return "\(name)  —  \(state.accountCount(account.id)), no read:org"
        }
        return "\(name)  —  \(state.accountCount(account.id))"
    }

    private var helpText: String {
        guard state.isPartial else { return "Scope both lists to one account" }
        return "A count is short — an account could not be read this refresh"
    }
}
