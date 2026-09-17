import Foundation

/// Registers the app to start at login via a LaunchAgent.
///
/// `SMAppService.mainApp.register()` is the modern API but expects a properly
/// signed bundle and is unreliable for the ad-hoc-signed local build this
/// project produces, so a plain LaunchAgent plist is used instead.
public enum LoginItem {
    /// Must match the app's own bundle identifier: `launchctl` treats the
    /// label as the service name, and a label that names nothing installed
    /// loads an agent macOS will never associate with the running app.
    public static let label = BundleID.current

    public static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    public static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    public static func enable(appPath: String) throws {
        let executable = "\(appPath)/Contents/MacOS/PRRadar"
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable],
            "RunAtLoad": true,
            "KeepAlive": false,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: plist, format: .xml, options: 0)
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL)
    }

    public static func disable() throws {
        if isEnabled { try FileManager.default.removeItem(at: plistURL) }
    }
}
