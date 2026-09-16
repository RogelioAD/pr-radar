import Foundation

/// A release version, compared numerically.
///
/// Parsed rather than string-compared because the obvious shortcuts are wrong:
/// `"1.10.0" < "1.9.0"` lexicographically, and real GitHub tags carry a `v`
/// prefix (`v2.101.0`), so a tag and the bundle's own
/// `CFBundleShortVersionString` never match as plain strings.
public struct AppVersion: Equatable, Comparable, Sendable, CustomStringConvertible {
    /// Numeric components, e.g. `[1, 2, 3]`.
    public let components: [Int]
    /// Pre-release suffix after a `-`, if any. Lower precedence than the
    /// release with the same numbers, per semver.
    public let preRelease: String?

    public init?(_ raw: String) {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // Tags are conventionally prefixed; Info.plist versions are not.
        if text.lowercased().hasPrefix("v") { text.removeFirst() }

        // Build metadata never affects precedence.
        if let plus = text.firstIndex(of: "+") { text = String(text[..<plus]) }

        var suffix: String?
        if let dash = text.firstIndex(of: "-") {
            suffix = String(text[text.index(after: dash)...])
            text = String(text[..<dash])
        }

        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        let numbers = parts.map { Int($0) }
        guard !numbers.isEmpty, !numbers.contains(where: { $0 == nil }) else { return nil }

        components = numbers.compactMap { $0 }
        preRelease = (suffix?.isEmpty ?? true) ? nil : suffix
    }

    public var description: String {
        let core = components.map(String.init).joined(separator: ".")
        return preRelease.map { "\(core)-\($0)" } ?? core
    }

    /// Component-wise comparison, treating a missing component as 0 so "1.2"
    /// and "1.2.0" are the same version. Returns nil when the numbers match.
    private static func compareNumbers(_ lhs: AppVersion,
                                       _ rhs: AppVersion) -> Bool? {
        let width = max(lhs.components.count, rhs.components.count)
        for index in 0..<width {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return nil
    }

    /// Written out rather than synthesised: the derived version would compare
    /// the raw component arrays, making "1.2" unequal to "1.2.0" while `<`
    /// treats them as equal. `==` and `<` disagreeing breaks Comparable's
    /// contract, and with it any sorting or deduplication.
    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        compareNumbers(lhs, rhs) == nil && lhs.preRelease == rhs.preRelease
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if let numeric = compareNumbers(lhs, rhs) { return numeric }
        // Numbers equal: a pre-release precedes the release it leads to.
        switch (lhs.preRelease, rhs.preRelease) {
        case (nil, nil): return false
        case (nil, _?): return false   // release > pre-release
        case (_?, nil): return true    // pre-release < release
        case (let l?, let r?): return l < r
        }
    }
}

/// Whether a newer build is available.
public enum UpdateStatus: Equatable, Sendable {
    case unknown          // not checked yet, or the check failed
    case upToDate
    case available(version: AppVersion, url: URL)

    public var newerVersion: AppVersion? {
        if case .available(let version, _) = self { return version }
        return nil
    }

    public var url: URL? {
        if case .available(_, let url) = self { return url }
        return nil
    }
}

public enum UpdateCheck {
    /// Compares the running build against the latest published release.
    ///
    /// Anything unparseable yields `.unknown` rather than `.upToDate` — a
    /// failed check must not masquerade as "you are current".
    public static func evaluate(current currentRaw: String?,
                                latestTag: String?,
                                releaseURL: String?) -> UpdateStatus {
        guard let currentRaw, let current = AppVersion(currentRaw) else { return .unknown }
        // No releases published at all is a legitimate "nothing newer".
        guard let latestTag else { return .upToDate }
        guard let latest = AppVersion(latestTag) else { return .unknown }
        guard latest > current else { return .upToDate }
        guard let releaseURL, let url = URL(string: releaseURL) else { return .unknown }
        return .available(version: latest, url: url)
    }
}
