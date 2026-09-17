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

    /// OAuth scopes `gh` reports for this account. Empty when it did not say —
    /// an older CLI, or the stand-in used when accounts cannot be listed.
    public let scopes: [String]

    /// Host-qualified, because the same login can exist on github.com and on an
    /// Enterprise host and they are different accounts with different tokens.
    public var id: String { "\(host)/\(login)" }

    /// Whether this account can discover the teams it belongs to, which is how
    /// review requests aimed at a team rather than at you are found. nil means
    /// `gh` did not report scopes, which is not the same as reporting that the
    /// scope is absent.
    ///
    /// Unknown reads as "do not warn", the opposite of `isHealthy`, and
    /// deliberately: an unknown token state costs one skipped fetch, while an
    /// unknown scope would cost a standing warning about a shortfall that may
    /// not exist. Of the two scopes this app needs, a missing `repo` fails
    /// loudly at the first request and needs no warning of its own; `read:org`
    /// is the one that degrades in silence.
    public var canReadTeams: Bool? {
        scopes.isEmpty ? nil : scopes.contains("read:org")
    }

    public init(login: String, host: String, isActive: Bool, isHealthy: Bool,
                scopes: [String] = []) {
        self.login = login
        self.host = host
        self.isActive = isActive
        self.isHealthy = isHealthy
        self.scopes = scopes
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
                        isHealthy: $0.state == "success",
                        scopes: parseScopes($0.scopes))
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

    /// `"gist, read:org, repo"` into its parts. Splitting on the comma rather
    /// than searching the whole string for "read:org" keeps a future scope whose
    /// name contains another's from reading as both.
    static func parseScopes(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private struct StatusPayload: Decodable {
        let hosts: [String: [Entry]]

        struct Entry: Decodable {
            let login: String
            /// Optional throughout: an older or newer `gh` that drops a field
            /// should cost one account's metadata, never the whole list.
            let active: Bool?
            let state: String?
            /// One comma-separated string, as `gh` prints it.
            let scopes: String?
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

    /// Stands in for the active account when it cannot be named — an older `gh`
    /// without `auth status --json`.
    ///
    /// Both fields are empty rather than guessed. `gh` is equally at home on an
    /// Enterprise host, and naming github.com here would print a hostname this
    /// machine may never talk to: a placeholder that states a fact is worse
    /// than one that admits it knows nothing. Callers show a discovered value
    /// only when there is one.
    static let activeFallback = Account(login: "", host: "",
                                        isActive: true, isHealthy: true)

    /// The token for an account, preferring a named lookup and falling back to
    /// the active-account token for the placeholder above.
    public static func token(for account: Account) -> String? {
        guard !account.login.isEmpty else { return Token.fromGitHubCLI() }
        return Token.fromGitHubCLI(login: account.login, host: account.host)
            ?? (account.isActive ? Token.fromGitHubCLI() : nil)
    }
}
