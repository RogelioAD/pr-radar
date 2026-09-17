import Foundation

/// One GitHub account `gh` is logged in to.
///
/// The app has always asked `gh auth token` for *the* token, which is whichever
/// account is active and nothing else. Anyone logged in to two — a work identity
/// and a personal one being the common pair — therefore had a badge that answered
/// "who is waiting on you" for only one of them, with nothing about the number
/// looking partial. That is the failure this type exists to end: a count that is
/// right about half your work reads exactly like a count that is right.
public struct Account: Hashable, Sendable, Identifiable {
    public let login: String
    public let host: String

    /// The account `gh` uses when not told otherwise. Kept so that a machine with
    /// one account behaves exactly as it did before any of this existed.
    public let isActive: Bool

    /// `gh` reports auth state per account, so a token that has expired or lost a
    /// scope is known before it is used rather than at the first failed fetch.
    /// Anything other than a reported success counts as unhealthy: an unfamiliar
    /// state is not evidence of a working token.
    public let isHealthy: Bool

    /// Host-qualified, because the same login can exist on github.com and on an
    /// Enterprise host and they are different accounts with different tokens.
    public var id: String { "\(host)/\(login)" }

    public init(login: String, host: String, isActive: Bool, isHealthy: Bool) {
        self.login = login
        self.host = host
        self.isActive = isActive
        self.isHealthy = isHealthy
    }
}

/// Discovering which accounts are available, and in what order to show them.
public enum Accounts {

    /// Parses the payload of `gh auth status --json hosts`.
    ///
    /// Kept pure and separate from running `gh` because the cases worth testing —
    /// two accounts, an unhealthy one, an Enterprise host alongside github.com —
    /// cannot be produced on a machine logged in to a single healthy account.
    public static func parse(statusJSON data: Data) -> [Account] {
        guard let payload = try? JSONDecoder().decode(StatusPayload.self, from: data)
        else { return [] }

        let accounts = payload.hosts.flatMap { host, entries in
            entries.map {
                Account(login: $0.login,
                        // `host` is echoed per entry, but the dictionary key is the
                        // authority: an entry missing it would otherwise be filed
                        // under an empty host and never match its token.
                        host: host,
                        isActive: $0.active ?? false,
                        isHealthy: $0.state == "success")
            }
        }
        return sorted(accounts)
    }

    /// Active account first, then alphabetically.
    ///
    /// The active one leads because it is the account the app used to show on its
    /// own, so an upgrade leaves the familiar list where it was. The rest are
    /// alphabetical rather than in `gh`'s order, which is unspecified and has no
    /// reason to stay stable between releases — and a tab strip that reorders
    /// itself between launches is a strip nobody can build muscle memory for.
    static func sorted(_ accounts: [Account]) -> [Account] {
        accounts.sorted {
            if $0.isActive != $1.isActive { return $0.isActive }
            if $0.host != $1.host { return $0.host.lowercased() < $1.host.lowercased() }
            return $0.login.lowercased() < $1.login.lowercased()
        }
    }

    private struct StatusPayload: Decodable {
        let hosts: [String: [Entry]]

        struct Entry: Decodable {
            let login: String
            /// Optional throughout: an older or newer `gh` that drops a field
            /// should cost one account's metadata, never the whole list.
            let active: Bool?
            let state: String?
        }
    }
}

extension Accounts {

    /// Every account `gh` knows about on this machine.
    ///
    /// Falls back to a single account standing for "whatever `gh` considers
    /// active" when the installed `gh` predates `auth status --json`. That keeps
    /// a machine with an older CLI working exactly as it did, rather than
    /// showing an empty account strip and no work — which would read as "you
    /// have nothing waiting", the one thing this must never say by accident.
    public static func discover() -> [Account] {
        guard let data = Token.statusJSON() else { return [activeFallback] }
        let parsed = parse(statusJSON: data)
        return parsed.isEmpty ? [activeFallback] : parsed
    }

    /// Stands in for the active account when it cannot be named. `login` is empty
    /// because nothing has told us what it is; the UI shows a discovered login
    /// only when there is one to show.
    static let activeFallback = Account(login: "", host: "github.com",
                                        isActive: true, isHealthy: true)

    /// The token for an account, preferring a named lookup and falling back to
    /// the active-account token for the placeholder above.
    public static func token(for account: Account) -> String? {
        guard !account.login.isEmpty else { return Token.fromGitHubCLI() }
        return Token.fromGitHubCLI(login: account.login, host: account.host)
            ?? (account.isActive ? Token.fromGitHubCLI() : nil)
    }
}
