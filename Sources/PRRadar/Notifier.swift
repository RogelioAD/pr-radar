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

    func prepare() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.authorized = granted
            Log.debug("notification authorization granted=\(granted) "
                      + "error=\(error?.localizedDescription ?? "none")")
        }
    }

    /// Notifies about pings not seen before. The remembered key includes the
    /// ping timestamp, so a re-request correctly notifies again.
    func notifyNewPings(in items: [ReviewItem]) {
        var seen = Prefs.seenPings
        let fresh = items.filter { !seen.contains($0.pingKey) }
        guard !fresh.isEmpty else { return }

        // On a first run, seed the store silently rather than firing a burst
        // of notifications for a backlog the user already knows about.
        let isFirstRun = seen.isEmpty
        for item in items { seen.insert(item.pingKey) }
        Prefs.seenPings = seen
        guard !isFirstRun else { return }

        for item in fresh { post(item) }
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

        let request = UNNotificationRequest(
            identifier: item.pingKey, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
