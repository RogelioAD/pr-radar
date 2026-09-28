import XCTest
@testable import PRRadarCore

/// The only tests here that touch the world, and they earn it: the two bugs
/// that matter in a process runner are a deadlock and a hang, and neither is
/// reachable by a pure function. Everything they use — `/bin/sh`, `/bin/cat`,
/// `/bin/sleep` — is on every macOS install.
final class ProcessRunnerTests: XCTestCase {

    func testStdoutAndStderrAreBothCaptured() async throws {
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "echo out; echo err 1>&2"],
            timeout: 10)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "out")
        XCTAssertEqual(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines), "err")
        XCTAssertFalse(result.timedOut)
    }

    func testANonZeroExitIsReportedRatherThanThrown() async throws {
        let result = try await ProcessRunner.run(
            executable: "/bin/sh", arguments: ["-c", "exit 3"], timeout: 10)
        XCTAssertEqual(result.exitCode, 3)
    }

    /// A pipe buffer is about 64KB. Draining one stream to EOF before starting
    /// on the other blocks the child the moment the unread one fills — which a
    /// review's output does and `gh auth token`'s never did.
    func testOutputLargerThanAPipeBufferDoesNotDeadlock() async throws {
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes abcdefghijklmnopqrstuvwxyz | head -c 400000; "
                            + "yes 0123456789 | head -c 400000 1>&2"],
            timeout: 30)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.count, 400_000)
        XCTAssertEqual(result.stderr.count, 400_000)
    }

    /// A review that wedges must cost a timeout, not the feature.
    func testAProcessThatOutlivesItsTimeoutIsStopped() async throws {
        let started = Date()
        let result = try await ProcessRunner.run(
            executable: "/bin/sleep", arguments: ["30"], timeout: 1, grace: 1)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    /// A child that ignores SIGTERM still has to die, or the app leaks a
    /// process every time a review goes wrong.
    func testAProcessThatIgnoresSigtermIsKilled() async throws {
        let started = Date()
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "trap '' TERM; sleep 5"],
            timeout: 1, grace: 1)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 10)
    }

    /// A child reading an inherited stdin waits for input a background app is
    /// never going to send.
    func testAChildWaitingOnStdinDoesNotHang() async throws {
        let result = try await ProcessRunner.run(
            executable: "/bin/cat", arguments: [], timeout: 5)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.exitCode, 0)
    }

    /// The livelock this suite let through once, so it cannot again.
    ///
    /// A pipe at EOF stays permanently readable, so a `readabilityHandler` left
    /// installed after the child exits is re-fired as fast as its queue can
    /// call it. Two of those spinning starve the cooperative thread pool, the
    /// `Task.sleep` in the wait loop never resumes, and a run that should take
    /// milliseconds never returns at all — at 100% CPU, looking for all the
    /// world like a hung child. Twenty back-to-back runs is enough to catch it:
    /// it is a race, and it does not lose every time.
    func testManyShortRunsInARowAllReturnPromptly() async throws {
        let started = Date()
        for index in 0..<20 {
            let result = try await ProcessRunner.run(
                executable: "/bin/echo", arguments: ["run \(index)"], timeout: 10)
            XCTAssertEqual(result.exitCode, 0)
            XCTAssertTrue(result.stdout.contains("run \(index)"))
        }
        // Generous — the point is that it finishes at all, not that it is fast.
        XCTAssertLessThan(Date().timeIntervalSince(started), 60)
    }

    /// The same risk with real output on both streams: the handlers have work
    /// to do first, and then have to stop.
    func testABusyRunStillReturnsPromptlyAfterTheChildExits() async throws {
        let started = Date()
        let result = try await ProcessRunner.run(
            executable: "/bin/sh",
            arguments: ["-c", "yes hello | head -c 200000; yes err | head -c 200000 1>&2"],
            timeout: 30)
        XCTAssertEqual(result.stdout.count, 200_000)
        XCTAssertLessThan(Date().timeIntervalSince(started), 20)
    }

    func testAMissingExecutableIsReportedRatherThanCrashing() async {
        do {
            _ = try await ProcessRunner.run(
                executable: "/nope/not/here", arguments: [], timeout: 5)
            XCTFail("expected notFound")
        } catch let error as ProcessRunnerError {
            XCTAssertEqual(error, .notFound(["/nope/not/here"]))
        } catch {
            XCTFail("expected ProcessRunnerError, got \(error)")
        }
    }

    func testTheWorkingDirectoryIsHonoured() async throws {
        let result = try await ProcessRunner.run(
            executable: "/bin/pwd", arguments: [],
            workingDirectory: URL(fileURLWithPath: "/usr"), timeout: 10)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines), "/usr")
    }

    func testFirstExecutablePicksTheFirstOneThatExists() {
        XCTAssertEqual(
            ProcessRunner.firstExecutable(among: ["/nope", "/bin/sh", "/bin/cat"]), "/bin/sh")
        XCTAssertNil(ProcessRunner.firstExecutable(among: ["/nope", "/also/nope"]))
    }

    // MARK: - Environment

    /// A GUI-launched app inherits no shell PATH, and the skill shells out to
    /// `gh` — so wherever `gh` was found has to be on it.
    func testExtraPathsComeFirstOnPath() {
        let path = ProcessRunner.environment(extraPaths: ["/opt/homebrew/bin"])["PATH"]
        XCTAssertEqual(path?.hasPrefix("/opt/homebrew/bin:"), true)
        XCTAssertEqual(path?.contains("/usr/bin"), true)
    }

    func testPathEntriesAreNotDuplicated() {
        let path = ProcessRunner.environment(extraPaths: ["/usr/bin"])["PATH"] ?? ""
        let entries = path.split(separator: ":")
        XCTAssertEqual(entries.filter { $0 == "/usr/bin" }.count, 1)
    }

    /// A CLI needs HOME to find its own configuration.
    func testHomeIsAlwaysSet() {
        XCTAssertFalse((ProcessRunner.environment()["HOME"] ?? "").isEmpty)
    }
}
