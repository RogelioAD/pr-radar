import Foundation

/// Whether a git failure is the network's fault or the repository's.
///
/// A review reaches the network twice before any reviewing starts — the head
/// and then the base — and the network is entitled to a bad second. This
/// machine's resolver answers `github.com` with SERVFAIL about once every ten
/// minutes while answering everything around it; one of those landing on a
/// `git fetch` ended the review, spent one of the pull request's two attempts,
/// and counted toward the three failures that switch the whole feature off.
/// Nothing had been reviewed, and asking again a second later would have
/// worked.
///
/// Matched on the message rather than the exit code, because git exits 128 for
/// everything: a resolver that blinked and a branch that was deleted are the
/// same number. The list is deliberately short and deliberately specific — a
/// fault that is not on it is treated as real and reported, which is the right
/// way round. Retrying a genuine error only spends seven seconds confirming it,
/// but retrying is also the thing that hides it.
public enum GitFault {

    /// The phrases git, libcurl and the resolver actually print when the thing
    /// that went wrong was between here and the server.
    static let transient = [
        "could not resolve host",
        "could not resolve proxy",
        "temporary failure in name resolution",
        "failed to connect",
        "couldn't connect to server",
        "connection refused",
        "connection reset",
        "connection timed out",
        "operation timed out",
        "network is unreachable",
        "network is down",
        "unexpected disconnect",
        "early eof",
        "rpc failed",
        "the remote end hung up unexpectedly",
        "ssl_error_syscall",
        "gnutls_handshake() failed",
        "error in the http2 framing layer",
        "bad gateway",
        "service unavailable",
        "internal server error",
    ]

    public static func isTransient(_ message: String) -> Bool {
        let text = message.lowercased()
        return transient.contains { text.contains($0) }
    }

    /// How long to wait before each retry — and, by its length, how many there
    /// are. Two retries, so three attempts in all.
    ///
    /// About seven seconds end to end. Long enough for a resolver to come back
    /// and for a momentary handshake failure to pass; short enough that it
    /// cannot be mistaken for a hang. A queue stalling a minute on a repository
    /// that has genuinely gone would be a worse symptom than the one this
    /// exists to fix.
    public static let retryDelays: [TimeInterval] = [2, 5]
}
