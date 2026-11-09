import XCTest
@testable import PRRadarCore

final class GitFaultTests: XCTestCase {

    // MARK: - What the network looks like

    /// The one that started this. Verbatim from the log of a review that was
    /// counted as a failed review, spent an attempt and moved the feature one
    /// step closer to switching itself off, having reviewed nothing.
    func testTheResolverBlinkingIsTransient() {
        XCTAssertTrue(GitFault.isTransient(
            "fatal: unable to access 'https://github.com/acme/widgets.git/': "
            + "Could not resolve host: github.com"))
    }

    func testTheOtherWaysTheNetworkSaysNoAreTransient() {
        let messages = [
            "fatal: unable to access '…': Failed to connect to github.com port 443 "
                + "after 75003 ms: Couldn't connect to server",
            "fatal: unable to access '…': Operation timed out after 300000 milliseconds",
            "error: RPC failed; curl 92 HTTP/2 stream 5 was not closed cleanly",
            "fatal: the remote end hung up unexpectedly",
            "error: 6000 bytes of body are still expected\nfatal: early EOF",
            "fatal: unable to access '…': LibreSSL SSL_connect: SSL_ERROR_SYSCALL",
            "fatal: unable to access '…': The requested URL returned error: 502 Bad Gateway",
        ]
        for message in messages {
            XCTAssertTrue(GitFault.isTransient(message), message)
        }
    }

    func testCaseDoesNotMatter() {
        XCTAssertTrue(GitFault.isTransient("COULD NOT RESOLVE HOST: github.com"))
    }

    // MARK: - What the repository looks like

    /// The important half. Everything here is a real answer, and asking again
    /// would only spend seven seconds being told it twice — and, worse, would
    /// make a genuine error look like flakiness.
    func testARealAnswerIsNotRetried() {
        let messages = [
            "fatal: couldn't find remote ref refs/pull/901/head",
            "fatal: 'origin' does not appear to be a git repository",
            "remote: Repository not found.",
            "fatal: Authentication failed for 'https://github.com/acme/widgets.git/'",
            "fatal: '/tmp/pr-radar-901-abc' already exists",
            "error: pathspec 'main' did not match any file(s) known to git",
            "fatal: not a git repository (or any of the parent directories): .git",
        ]
        for message in messages {
            XCTAssertFalse(GitFault.isTransient(message), message)
        }
    }

    func testSilenceIsNotTransient() {
        XCTAssertFalse(GitFault.isTransient(""))
    }

    // MARK: - How long it takes to give up

    /// Two retries, three attempts, about seven seconds. The ceiling matters as
    /// much as the floor: a repository that has genuinely gone must not hold
    /// the single worker for a minute while the rest of the queue waits.
    func testGivingUpIsQuick() {
        XCTAssertEqual(GitFault.retryDelays.count, 2)
        XCTAssertEqual(GitFault.retryDelays.reduce(0, +), 7)
        XCTAssertTrue(GitFault.retryDelays.allSatisfy { $0 > 0 })
        // Rising, so the second ask is given longer than the first to be
        // answered rather than both landing inside one bad moment.
        XCTAssertEqual(GitFault.retryDelays, GitFault.retryDelays.sorted())
    }
}
