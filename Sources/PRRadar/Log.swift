import AppKit
import OSLog

/// Debug tracing. Always recorded through unified logging, and additionally
/// echoed to stderr when PRRADAR_DEBUG=1.
///
/// The stderr half only reaches anyone running the binary from a terminal,
/// which an app started by a LaunchAgent never is — diagnosing it meant
/// rewriting the agent to capture a file. The unified log is readable after the
/// fact in Console.app, filtered on this subsystem, with no such surgery:
///
///     log stream --predicate 'subsystem == "com.rogelioacosta.prradar"'
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["PRRADAR_DEBUG"] == "1"

    private static let logger = Logger(subsystem: "com.rogelioacosta.prradar",
                                       category: "app")

    /// PRRADAR_EXPAND=1 opens the drawer on launch — lets the expanded state be
    /// inspected without a click.
    static let startExpanded = ProcessInfo.processInfo.environment["PRRADAR_EXPAND"] == "1"

    /// PRRADAR_APPEARANCE=light|dark forces the app's appearance, so the
    /// opposite colour scheme can be inspected without switching the system.
    static var forcedAppearance: NSAppearance? {
        switch ProcessInfo.processInfo.environment["PRRADAR_APPEARANCE"]?.lowercased() {
        case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua)
        default: return nil
        }
    }

    /// PRRADAR_FAKE_BEHIND=N forces every one of my PRs to look N commits
    /// behind, so the branch-state chip can be inspected. Both real PRs are
    /// level with their bases, so there is otherwise no way to see it.
    static var fakeBehind: Int? {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_BEHIND"].flatMap(Int.init)
    }

    /// PRRADAR_FAKE_READY=1 forces every one of my PRs to look mergeable, so
    /// the badge's green dot can be inspected. Both real PRs are BLOCKED on
    /// reviews, so there is otherwise no way to see it.
    static var fakeReady: Bool {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_READY"] == "1"
    }

    static func debug(_ message: @autoclosure () -> String) {
        let text = message()
        // Notice rather than debug: debug-level records live in memory and are
        // gone before anyone thinks to look, which is precisely the situation
        // this exists for. Notice is persisted and readable after the fact.
        //
        // Public: this is a developer tool logging its own state, and redacted
        // placeholders would make the log useless for the thing it exists for.
        logger.notice("\(text, privacy: .public)")
        guard enabled else { return }
        FileHandle.standardError.write(Data("[prradar] \(text)\n".utf8))
    }
}
