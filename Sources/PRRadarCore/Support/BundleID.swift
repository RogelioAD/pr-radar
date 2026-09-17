import Foundation

/// The bundle identifier this build runs under.
///
/// macOS keys four separate things off it — notification permission, the
/// `defaults` domain, the unified-log subsystem, and the LaunchAgent label — so
/// they only stay in agreement while a single value is behind all of them.
/// `Scripts/bundle.sh` writes `BUNDLE_ID` into `Info.plist` when it assembles
/// the app; this reads it back out. The build variable is the only place the
/// identifier is set.
public enum BundleID {
    /// Used when the process has no identifier of its own, which is how `make
    /// run` starts it: a bare SwiftPM binary has no `Info.plist` at all, and
    /// nothing in that mode registers a LaunchAgent or asks for notification
    /// permission, so this only has to be something stable to log under.
    ///
    /// Under `swift test` the identifier is the test runner's own
    /// (`com.apple.dt.xctest.tool`) rather than this, so anything asserting on
    /// a value derived from it — `LoginItem.plistURL` above all — has to pin
    /// the identifier instead of reading it, or it writes a LaunchAgent named
    /// after Apple's test tool into the home directory of whoever ran the suite.
    public static let fallback = "com.rogelioacosta.prradar"

    public static let current = Bundle.main.bundleIdentifier ?? fallback
}
