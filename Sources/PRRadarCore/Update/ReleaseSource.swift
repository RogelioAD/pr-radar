import Foundation

/// Where the update check looks for releases.
///
/// Its own type because the setting is now typed into a text field rather than
/// written with `defaults`, and a half-typed repository must never reach the
/// update check: `owner` on its own is a URL that 404s on every poll, which
/// looks exactly like "no releases published" and so would quietly turn the
/// update notice off for good.
public enum ReleaseSource {

    /// The value if it names a repository, and nil if it does not.
    ///
    /// Deliberately forgiving about what people paste: a full GitHub URL, a
    /// trailing `.git`, surrounding whitespace, a leading or trailing slash.
    /// Deliberately strict about the result — exactly two non-empty segments,
    /// neither of which may contain a character GitHub does not allow in a
    /// name, so a path like `owner/repo/releases` is rejected rather than
    /// truncated into something plausible.
    public static func normalized(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        for prefix in ["https://github.com/", "http://github.com/", "github.com/"] {
            if text.lowercased().hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                break
            }
        }
        if text.lowercased().hasSuffix(".git") { text = String(text.dropLast(4)) }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        guard parts.allSatisfy(isName) else { return nil }
        return parts.joined(separator: "/")
    }

    /// GitHub owners and repositories are letters, digits, and `-._`.
    private static func isName(_ part: Substring) -> Bool {
        guard !part.isEmpty else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._"))
        return part.unicodeScalars.allSatisfy(allowed.contains)
    }
}
