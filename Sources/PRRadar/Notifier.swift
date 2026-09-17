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
    }

    private enum Action {
        static let open = "open"
    }

    func prepare() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.review,
                actions: [UNNotificationAction(identifier: Action.open,
                                               title: "Open PR",
                                               options: [.foreground])],
                intentIdentifiers: []),
            UNNotificationCategory(
                identifier: Category.update,
                actions: [UNNotificationAction(identifier: Action.open,
                                               title: "Open Release",
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
        content.userInfo = ["url": item.url.absoluteString]
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
        if let string = response.notification.request.content.userInfo["url"] as? String,
           let url = URL(string: string) {
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
