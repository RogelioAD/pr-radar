import AppKit
import UserNotifications
import PRRadarCore

/// Native notifications for newly-pinged PRs.
///
/// `UNUserNotificationCenter.current()` traps when the process has no bundle
/// identifier, which is exactly the case for a bare `swift run` binary — so the
/// framework is only touched once a bundle is confirmed, and an unbundled run
/// falls back to `osascript`.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {

    private let isBundled = Bundle.main.bundleIdentifier != nil
    private var authorized = false

    /// Categories have to exist before a notification claims one, so they are
    /// registered up front rather than at post time.
    private enum Category {
        static let review = "review-request"
        static let update = "app-update"
        static let comment = "pr-comment"
    }

    private enum Action {
        static let open = "open"
        static let snooze = "snooze"
    }

    /// Puts a ping down for an hour. Set by the app delegate, which owns the
    /// store; nil until it is, so a banner that somehow arrives first simply
    /// offers nothing rather than dropping the press on the floor.
    var onSnooze: ((String) -> Void)?

    func prepare() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.review,
                actions: [
                    UNNotificationAction(identifier: Action.open,
                                         title: "Open PR",
                                         options: [.foreground]),
                    // The other half of what you can do about a review
                    // request, offered where the request arrives. A ping that
                    // lands mid-focus can now be dealt with from the banner
                    // instead of being dismissed and forgotten — dismissing a
                    // notification is the one response that leaves no trace
                    // anywhere, and it is the one people reach for.
                    //
                    // No `.foreground`: putting a row down should not haul the
                    // drawer in front of whatever you were doing. That is the
                    // whole point of pressing it.
                    UNNotificationAction(identifier: Action.snooze,
                                         title: "Snooze 1 hour",
                                         options: []),
                ],
                intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Category.update,
                actions: [UNNotificationAction(identifier: Action.open,
                                               title: "Open Release",
                                               options: [.foreground])],
                intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Category.comment,
                actions: [UNNotificationAction(identifier: Action.open,
                                               title: "Open PR",
                                               options: [.foreground])],
                intentIdentifiers: []),
        ])
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.authorized = granted
            Log.debug("notification authorization granted=\(granted) "
                      + "error=\(error?.localizedDescription ?? "none")")
        }
    }

    /// Notifies about pings not seen before. The remembered key includes the
    /// ping timestamp, so a re-request correctly notifies again.
    /// Returns whether anything new actually fired, so the caller can react to
    /// the same edge rather than working it out a second time — the mascot's
    /// startle hangs off this.
    @discardableResult
    func notifyNewPings(in items: [ReviewItem]) -> Bool {
        var seen = Prefs.seenPings
        let fresh = items.filter { !seen.contains($0.pingKey) }
        guard !fresh.isEmpty else { return false }

        // On a first run, seed the store silently rather than firing a burst
        // of notifications for a backlog the user already knows about.
        let isFirstRun = seen.isEmpty
        for item in items { seen.insert(item.pingKey) }
        Prefs.seenPings = seen
        guard !isFirstRun else { return false }

        for item in fresh { post(item) }
        return true
    }

    /// Notifies about comments on your own pull requests that have not been
    /// announced before.
    ///
    /// The same shape as `notifyNewPings`, including the part that matters
    /// most: **the first run seeds the store silently.** A new install with
    /// four pull requests and thirty bot comments between them would otherwise
    /// open with thirty banners describing a backlog the user has already read,
    /// which is how somebody learns to turn a feature off in its first minute.
    ///
    /// Collapsed per pull request rather than one banner per comment. A push
    /// wakes three bot reviewers at once and they answer within seconds of each
    /// other; eleven banners for one push is the feature making the problem it
    /// was built to solve worse.
    ///
    /// Returns whether anything fired, so the caller can react to the same edge
    /// rather than working it out again — which is what the mascot's startle
    /// hangs off for the review list.
    @discardableResult
    func notifyNewComments(in pullRequests: [MyPullRequest]) -> Bool {
        guard Prefs.notifyComments else { return false }

        let all = PRComment.harvest(from: pullRequests,
                                    includingBots: Prefs.notifyBotComments)
        var seen = Prefs.seenComments
        let fresh = all.filter { !seen.contains($0.id) }
        guard !fresh.isEmpty else { return false }

        let isFirstRun = seen.isEmpty
        // Everything currently visible is marked seen, not just what fired.
        // A comment filtered out by the bot switch must not arrive in a burst
        // the moment that switch is turned back on.
        for comment in all { seen.insert(comment.id) }
        Prefs.seenComments = seen
        guard !isFirstRun else { return false }

        for (_, group) in Dictionary(grouping: fresh, by: \.number) {
            post(group)
        }
        return true
    }

    /// One banner for one pull request's worth of new comments.
    private func post(_ comments: [PRComment]) {
        // The newest is the one worth naming: `harvest` sorts oldest first, so
        // a conversation reads to its latest turn rather than its first.
        guard let latest = comments.last else { return }

        let title = comments.count == 1
            ? latest.headline
            : "\(comments.count) new on #\(latest.number)"
        let body = comments.count == 1
            ? latest.body
            : "\(spokenAuthors(of: comments)) · \(latest.body)"

        guard isBundled, authorized else {
            postViaOsascript(title: title, body: body)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": latest.url.absoluteString]
        content.categoryIdentifier = Category.comment
        // One stack per repository, matching the review banner's rule.
        content.threadIdentifier = latest.repo
        // Changes requested is the one that stops you shipping, so it is the
        // one allowed to break through. Everything else can wait for the next
        // time the drawer is opened.
        if comments.contains(where: { $0.kind == .review(.changesRequested) }) {
            content.interruptionLevel = .timeSensitive
        }

        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: latest.id, content: content, trigger: nil))
    }

    /// "alice and 2 others", for a banner with one line to say who.
    private func spokenAuthors(of comments: [PRComment]) -> String {
        var seen: [String] = []
        for comment in comments where !seen.contains(comment.author) {
            seen.append(comment.author)
        }
        switch seen.count {
        case 0: return ""
        case 1: return seen[0]
        case 2: return "\(seen[0]) and \(seen[1])"
        default: return "\(seen[0]) and \(seen.count - 1) others"
        }
    }

    /// Announces a new PR Radar release. Clicking opens the release page.
    func notifyUpdate(version: String, url: URL) {
        let title = "PR Radar \(version) available"
        let body = "You're running an older build. Click to open the release."

        guard isBundled, authorized else {
            postViaOsascript(title: title, body: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": url.absoluteString]
        content.categoryIdentifier = Category.update
        content.threadIdentifier = "pr-radar-update"
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "update-\(version)",
                                  content: content, trigger: nil))
    }

    private func post(_ item: ReviewItem) {
        let title = "Review requested"
        let body = "\(item.authorLogin) · #\(item.number) \(item.title)"

        guard isBundled, authorized else {
            Log.debug("posting via osascript fallback (bundled=\(isBundled) authorized=\(authorized))")
            postViaOsascript(title: title, body: body)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // The ping key rides along so the Snooze button knows which request it
        // is putting down. The url alone would not do it: a re-request is the
        // same pull request at the same address and a different ping, and
        // snoozing it by url would silence the new one with the old one's key.
        content.userInfo = ["url": item.url.absoluteString, "ping": item.pingKey]
        content.categoryIdentifier = Category.review
        // One thread per repository, so a busy repo collapses into a single
        // stack in Notification Center instead of a flat run of banners.
        content.threadIdentifier = item.repo
        // Already-stale requests are the ones worth interrupting for; a fresh
        // one can wait for the next time the drawer is opened.
        if Staleness.of(item.pingedAt, now: Date()) == .stale {
            content.interruptionLevel = .timeSensitive
        }
        if let avatar = item.authorAvatarURL,
           let attachment = Self.attachment(for: avatar, id: item.id) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: item.pingKey, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Author avatar, shown as the banner's thumbnail. Fetched synchronously
    /// because posting is already off the critical path and an avatar is a few
    /// kilobytes; any failure simply yields a notification without one.
    ///
    /// The file must outlive the call — the system copies it into its own
    /// store when the request is accepted — so it lands in the temporary
    /// directory rather than being cleaned up here.
    private static func attachment(for url: URL, id: String) -> UNNotificationAttachment? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let safe = id.replacingOccurrences(of: "/", with: "-")
                     .replacingOccurrences(of: "#", with: "-")
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("prradar-avatar-\(safe).png")
        guard (try? data.write(to: file)) != nil else { return nil }
        return try? UNNotificationAttachment(identifier: "avatar", url: file)
    }

    /// Fallback path: works unbundled and when authorization was refused,
    /// at the cost of not being clickable.
    private func postViaOsascript(title: String, body: String) {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
        }
        let script = "display notification \"\(escape(body))\" with title \"\(escape(title))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == Action.snooze {
            if let ping = info["ping"] as? String { onSnooze?(ping) }
            completionHandler()
            return
        }
        if let string = info["url"] as? String, let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
        completionHandler()
    }

    /// Show the banner even while PR Radar is the frontmost app.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
