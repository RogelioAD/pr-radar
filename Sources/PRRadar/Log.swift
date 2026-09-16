import AppKit

/// Debug tracing, off unless PRRADAR_DEBUG=1.
enum Log {
    static let enabled = ProcessInfo.processInfo.environment["PRRADAR_DEBUG"] == "1"

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
        guard enabled else { return }
        FileHandle.standardError.write(Data("[prradar] \(message())\n".utf8))
    }
}
