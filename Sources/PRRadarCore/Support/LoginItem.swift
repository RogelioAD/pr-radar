import Foundation

/// Registers the app to start at login via a LaunchAgent.
///
/// `SMAppService.mainApp.register()` is the modern API but expects a properly
/// signed bundle and is unreliable for the ad-hoc-signed local build this
/// project produces, so a plain LaunchAgent plist is used instead.
public enum LoginItem {
    public static let label = "com.rogelioacosta.prradar"

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
