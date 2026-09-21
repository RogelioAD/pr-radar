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

    /// PRRADAR_FAIL_ACCOUNT=login forces that account's fetch to fail, so the
    /// short-round badge and the strip's mark can be inspected. Every account
    /// on a working machine is healthy, which otherwise leaves the one state
    /// this feature exists for as the one state nobody has ever seen. Same
    /// reason the two fakes below exist.
    ///
    /// PRRADAR_FAIL_ACCOUNT=mine fails only the My PRs half, which is the
    /// quieter case: the account answers, and still returns half a round.
    static var failAccount: String? {
        ProcessInfo.processInfo.environment["PRRADAR_FAIL_ACCOUNT"]
    }

    /// PRRADAR_FAKE_ACCOUNTS=n stands the drawer up as though `gh` were logged
    /// in to n accounts, by repeating the real one under invented logins.
    ///
    /// The whole point of this feature is what happens above one account, and
    /// that is the one thing a machine with a single login cannot show — the
    /// strip does not appear, the merge never dedupes, and the scope has
    /// nothing to scope to. `PRRADAR_FAIL_ACCOUNT` exists for the same reason
    /// and covers the other half.
    ///
    /// The copies carry the real account's token, so every one of them returns
    /// the *same* rows. That is not a limitation of the fake, it is the case
    /// worth seeing: two identities that both belong to a reviewing team really
    /// do surface one pull request twice, and `AccountMerge` giving it to the
    /// first account is the behaviour the strip's counts have to reflect.
    static var fakeAccounts: Int? {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_ACCOUNTS"]
            .flatMap(Int.init)
            .map { min(max($0, 1), 6) }
    }

    /// PRRADAR_FAKE_READY=1 forces every one of my PRs to look mergeable, so
    /// the badge's green dot can be inspected. Both real PRs are BLOCKED on
    /// reviews, so there is otherwise no way to see it.
    static var fakeReady: Bool {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_READY"] == "1"
    }

    /// PRRADAR_FAKE_STACKS=1 cuts the longest stack in half, so the list shows
    /// two groups instead of one. How several groups sit together — their
    /// outlines, their spacing, the drawer's height across them — cannot be
    /// looked at with a single stack in the data, and a second real one is not
    /// something you can conjure on demand.
    static var fakeStacks: Bool {
        ProcessInfo.processInfo.environment["PRRADAR_FAKE_STACKS"] == "1"
    }

    /// PRRADAR_FAKE_BANNER=<id>[,<id>…] drops those trophies' banners on the
    /// first refresh.
    ///
    /// Earning one is the thing you cannot arrange: the banner is the payoff
    /// for a queue emptying or a hundredth merge, and neither is available on
    /// a Tuesday afternoon. Named rather than a bare flag because the banner
    /// is now sized around whatever it is drawing — a one-word title beside a
    /// 32-cell trophy is a different shape from a two-word one — so seeing
    /// *a* banner is not the same as seeing the banner.
    ///
    /// `1` is the old spelling and still means the original: inbox zero.
    /// `many` fires enough at once to trip the summary.
    static var fakeBanner: [String] {
        guard let raw = ProcessInfo.processInfo.environment["PRRADAR_FAKE_BANNER"],
              !raw.isEmpty
        else { return [] }
        if raw == "1" { return ["inboxZero"] }
        return raw.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
    }

    /// PRRADAR_FAKE_TROPHIES=all|none forces the shelf to one of its two ends.
    ///
    /// Both ends are hard to reach honestly and both are worth looking at.
    /// `all` is the finished set — thirty drawings only work as a set if they
    /// can be seen as one, and earning them to find out whether two of the
    /// greens fight is not a workflow. `none` is what a stranger sees, which
    /// is otherwise visible for about four seconds on one machine ever: the
    /// silent backfill fills the shelf on the very first refresh.
    ///
    /// `none` also suppresses evaluation, or the backfill would undo it
    /// between the window opening and anybody looking at it.
    ///
    /// In memory only: neither ever writes, so quitting puts the real shelf
    /// back. `1` is the old spelling of `all`.
    /// `empty` rather than `none`, which as a case on an enum used through
    /// an `Optional` is the same spelling as "no value" and reads as either.
    enum Shelf: String {
        case all, empty
    }

    static var fakeShelf: Shelf? {
        switch ProcessInfo.processInfo.environment["PRRADAR_FAKE_TROPHIES"] {
        case "1", "all": return .all
        case "none", "empty": return .empty
        default: return nil
        }
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
