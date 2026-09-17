import Foundation
import Security

public enum TokenError: LocalizedError {
    case notFound

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "No GitHub token. Run `gh auth login`, or store one in the "
                 + "Keychain as service \"PRRadar\" account \"token\"."
        }
    }
}

public enum Token {

    /// A GUI-launched app does not inherit the shell `PATH`, so `gh` can never be
    /// found by bare name — these absolute candidates are checked in order.
    static let ghCandidates = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
        "/opt/local/bin/gh",
    ]

    /// Where a token came from — surfaced in diagnostics.
    public enum Source: String {
        case githubCLI = "gh CLI"
        case keychain = "Keychain"
    }

    public static func resolve() throws -> String {
        try resolveWithSource().token
    }

    public static func resolveWithSource() throws -> (token: String, source: Source) {
        if let token = fromGitHubCLI() { return (token, .githubCLI) }
        if let token = fromKeychain() { return (token, .keychain) }
        throw TokenError.notFound
    }

    static func fromGitHubCLI() -> String? {
        runGH(["auth", "token"])
    }

    /// The token for one named account, rather than whichever is active.
    ///
    /// `gh auth token` with no account answers for the active one only, which is
    /// why the app could never see a second identity's work. Naming the account
    /// is the whole of the fix at this layer.
    static func fromGitHubCLI(login: String, host: String) -> String? {
        runGH(["auth", "token", "--user", login, "--hostname", host])
    }

    /// The payload of `gh auth status --json hosts`, or nil when this `gh` is too
    /// old to support it.
    ///
    /// Nil is not an error: it means "this machine can only tell us about the
    /// active account", and the caller falls back to exactly the old behaviour
    /// rather than reporting that the user has no accounts.
    static func statusJSON() -> Data? {
        runGH(["auth", "status", "--json", "hosts"]).map { Data($0.utf8) }
    }

    /// Runs `gh` and returns its trimmed stdout, or nil if it could not be run or
    /// exited non-zero.
    static func runGH(_ arguments: [String]) -> String? {
        guard let gh = ghCandidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else { return nil }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: gh)
        process.arguments = arguments
        // Give `gh` a usable minimal environment; it needs HOME to find its config.
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin:" + (env["PATH"] ?? "")
        process.environment = env

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }

        let token = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    static func fromKeychain(service: String = "PRRadar", account: String = "token") -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        let token = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }
}
