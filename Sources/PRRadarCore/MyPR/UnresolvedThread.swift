import Foundation

/// A review thread on your own pull request that nobody has resolved.
///
/// The count was on the row from the beginning — `3 open` — and a count is
/// exactly as much use as knowing there is post: it tells you something is
/// waiting without telling you whether it matters. Opening GitHub to find out
/// that two of the three were "nit: typo" is the trip this saves.
public struct UnresolvedThread: Equatable, Sendable, Identifiable, Codable {

    /// One comment in the thread, pared to what a 440pt — or 880pt — drawer can
    /// show: who said it and what they said.
    public struct Comment: Equatable, Sendable, Codable {
        public let author: String
        public let body: String

        public init(author: String, body: String) {
            self.author = author
            self.body = body
        }
    }

    /// GitHub's node id, which is stable across refreshes — so a thread that is
    /// open stays open when the poll lands, rather than closing under the
    /// pointer every sixty seconds.
    public let id: String
    public let path: String?
    public let line: Int?
    /// The code it was written against has changed since. GitHub hides these
    /// behind a disclosure and so does the row: still unresolved, still
    /// counted, but much more likely to be stale than unanswered.
    public let isOutdated: Bool
    public let comments: [Comment]
    /// The code the thread was left on, from GitHub's own `diffHunk`.
    ///
    /// nil when the hunk was not sent or could not be read — a thread on a file
    /// rather than a line, most often. The comments are still worth showing
    /// without it, so it is optional rather than a reason to drop the thread.
    public let excerpt: DiffExcerpt?
    /// Comments beyond the ones fetched. Said out loud rather than quietly
    /// dropped — a thread cut off mid-argument reads as settled.
    public let moreComments: Int

    public init(id: String, path: String?, line: Int?, isOutdated: Bool,
                comments: [Comment], moreComments: Int,
                excerpt: DiffExcerpt? = nil) {
        self.id = id
        self.path = path
        self.line = line
        self.isOutdated = isOutdated
        self.comments = comments
        self.moreComments = moreComments
        self.excerpt = excerpt
    }

    /// Where it sits, for the row to say so plainly. Matches `PreparedFinding`'s
    /// so a thread and a finding are captioned the same way.
    public var location: String? {
        guard let path else { return nil }
        let short = path.split(separator: "/").last.map(String.init) ?? path
        return line.map { "\(short):\($0)" } ?? short
    }

    /// How long one comment may be before it is cut.
    ///
    /// Generous enough for a real review comment and mean enough that a pasted
    /// stack trace cannot push everything else off the drawer. The cut is at a
    /// word so it does not end mid-token.
    static let bodyLimit = 320

    /// Tidies one comment's body for a row: no leading blank lines, no trailing
    /// whitespace, and nothing longer than `bodyLimit`.
    public static func trimmed(_ body: String) -> String {
        let clean = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > bodyLimit else { return clean }
        let cut = clean.prefix(bodyLimit)
        let atWord = cut.lastIndex(of: " ").map { String(cut[..<$0]) } ?? String(cut)
        return atWord.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
}
