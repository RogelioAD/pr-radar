import Foundation

public struct ProcessResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }
}

public enum ProcessRunnerError: LocalizedError, Equatable {
    case notFound([String])
    case launchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notFound(let candidates):
            return "Not found. Looked in: \(candidates.joined(separator: ", "))"
        case .launchFailed(let message):
            return "Could not start the process: \(message)"
        }
    }
}

/// Runs a command and waits for it, without hanging.
///
/// `Token.runGH` is the precedent for the environmental half of this — absolute
/// paths, because a GUI-launched app inherits no shell `PATH`, and a re-seeded
/// `HOME` — but it is synchronous, untimed, and throws stderr away. None of
/// that survives a command that runs for minutes and whose failure message is
/// the only useful thing it produced.
///
/// Four things here are load-bearing, and each one is a hang if it is wrong:
///
/// 1. **Both pipes are drained concurrently.** A pipe buffer is about 64KB.
///    Reading stdout to EOF while stderr fills blocks the child forever — the
///    existing `runGH` gets away with a serial read only because `gh auth token`
///    prints one line.
/// 2. **stdin is `/dev/null`.** A child that reads an inherited stdin waits for
///    input that a background app is never going to send.
/// 3. **The timeout escalates.** A `--print` session can ignore `SIGTERM` in the
///    middle of a request, so a `SIGKILL` follows after a grace period.
/// 4. **Cancellation is honoured**, so quitting the app does not leave the
///    child running.
public enum ProcessRunner {

    public static func firstExecutable(among candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// The minimal environment a CLI needs when it was not started from a shell.
    ///
    /// `extraPaths` is how the caller adds the directory a helper lives in —
    /// a review skill shells out to `gh`, and it will not find it otherwise.
    public static func environment(extraPaths: [String] = []) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = environment["HOME"] ?? NSHomeDirectory()
        let base = ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let existing = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        environment["PATH"] = (extraPaths + base + existing)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
            .joined(separator: ":")
        return environment
    }

    public static func run(executable: String,
                           arguments: [String],
                           workingDirectory: URL? = nil,
                           environment: [String: String] = ProcessRunner.environment(),
                           timeout: TimeInterval,
                           grace: TimeInterval = 5) async throws -> ProcessResult {
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw ProcessRunnerError.notFound([executable])
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let workingDirectory { process.currentDirectoryURL = workingDirectory }

        // A child that reads an inherited stdin waits forever for input this
        // app will never send.
        process.standardInput = FileHandle.nullDevice

        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do { try process.run() }
        catch { throw ProcessRunnerError.launchFailed(error.localizedDescription) }

        // The child has its own copies now, so the parent must drop these or
        // the read ends never see EOF — every writer has to be gone for that,
        // and we would otherwise be one of them forever.
        try? out.fileHandleForWriting.close()
        try? err.fileHandleForWriting.close()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                // A dedicated thread, not a dispatch queue. See `collect`.
                Thread.detachNewThread {
                    let result = collect(from: process, out: out, err: err,
                                         timeout: timeout, grace: grace)
                    continuation.resume(returning: result)
                }
            }
        } onCancel: {
            // Quitting the app must not leave a review running for a quarter of
            // an hour. The collector below sees the exit and returns.
            process.terminate()
        }
    }

    /// Waits for the process on a thread of its own, draining both pipes with
    /// blocking reads on two more.
    ///
    /// **Everything here is a plain `Thread` on purpose.** Three designs were
    /// tried and the first two both hung:
    ///
    /// 1. `readabilityHandler` plus an `await Task.sleep` poll. A pipe at EOF
    ///    stays permanently *readable*, so a handler left installed after the
    ///    child exits re-fires as fast as its queue can call it. Two of those
    ///    spinning saturate the cooperative pool — and the loop that would have
    ///    cleared them was itself awaiting on that pool, so it never ran again.
    ///    100% CPU, never returns.
    /// 2. Blocking reads on `DispatchQueue.global()`. Better, until a child
    ///    leaves a grandchild holding the pipe: that reader blocks forever, and
    ///    enough of them exhaust libdispatch's thread limit. The next casualty
    ///    is `asyncAfter`, which is how the *timeout* was scheduled — so the one
    ///    mechanism that could have rescued the run was the thing starved by it.
    ///
    /// The lesson both times is the same: never put an unbounded blocking read
    /// on a shared pool. A detached thread is not pooled, cannot be starved by
    /// its siblings, and cannot starve anything else.
    private static func collect(from process: Process,
                                out: Pipe, err: Pipe,
                                timeout: TimeInterval,
                                grace: TimeInterval) -> ProcessResult {
        let collector = OutputCollector()
        let readers = DispatchSemaphore(value: 0)

        for (pipe, isStdout) in [(out, true), (err, false)] {
            Thread.detachNewThread {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if isStdout { collector.appendOut(data) } else { collector.appendErr(data) }
                readers.signal()
            }
        }

        // Sleeping on this thread rather than scheduling a timer somewhere
        // else, for the reason above: the timeout must not depend on a resource
        // the reads can exhaust.
        var timedOut = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            timedOut = true
            process.terminate()
            // A --print session can ignore SIGTERM mid-request, so the polite
            // ask gets a deadline of its own.
            let hard = Date().addingTimeInterval(grace)
            while process.isRunning && Date() < hard {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        process.waitUntilExit()

        // Bounded, because EOF needs *every* writer gone — including a
        // grandchild the killed process left behind holding the same pipe.
        // Waiting on that unbounded is the hang this whole design avoids; the
        // reader thread outlives us in that case and dies when the orphan does.
        for _ in 0..<2 { _ = readers.wait(timeout: .now() + 1) }

        return ProcessResult(exitCode: process.terminationStatus,
                             stdout: collector.stdout,
                             stderr: collector.stderr,
                             timedOut: timedOut)
    }
}

/// Somewhere for the two reader threads to put what they read. A lock rather
/// than an actor because they are plain threads and cannot await.
private final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var outData = Data()
    private var errData = Data()

    func appendOut(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); outData.append(data); lock.unlock()
    }

    func appendErr(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock(); errData.append(data); lock.unlock()
    }

    var stdout: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: outData, as: UTF8.self)
    }

    var stderr: String {
        lock.lock(); defer { lock.unlock() }
        return String(decoding: errData, as: UTF8.self)
    }
}
