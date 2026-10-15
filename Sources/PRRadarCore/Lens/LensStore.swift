import Foundation
import CryptoKit

/// Plain-English readings of text the app did not write, kept beside that text
/// rather than in it.
///
/// **The whole design is in that sentence.** A finding's `summary` and a thread
/// comment's `body` are what GitHub gets: `AutoReviewComment.threadBody` and
/// `summaryLine` compose the posted review out of `Finding` at post time, from
/// the fields the skill filled in. Nothing is stored pre-composed. So a reading
/// kept *outside* `Finding` cannot reach a pull request by any path — not
/// because the posting code is careful, but because it never sees this type.
/// A translation stored *in* `Finding.summary` would have been one forgotten
/// line away from posting a paraphrase of somebody's review under their name.
///
/// Keyed by a hash of the source text, not by a finding id or a comment id, for
/// three reasons that all turned out to be the same one — *the text is the
/// thing*:
///
/// - A comment's GitHub node id is optional (`UnresolvedThread.Comment.id`),
///   so half the My PRs side has no id to key on.
/// - A finding's identity is `tier|file|line|summary`, which already contains
///   the text; hashing the text directly drops the three fields that can shift
///   without the sentence changing.
/// - Edited text *should* miss. Somebody who rewrites a review comment has
///   written something else, and serving the old reading would be the one
///   failure this feature cannot afford: confidently plain, and wrong.
public struct LensStore: Codable, Equatable, Sendable {

    /// Readings by source-text key. Private so nothing can write one under a
    /// key that is not its text's.
    private var readings: [String: String]

    public init(readings: [String: String] = [:]) {
        self.readings = readings
    }

    /// The key a piece of source text caches under.
    ///
    /// Normalised first, so the same sentence wrapped differently is one entry
    /// rather than two. Truncated to 16 hex characters: this keys a cache in a
    /// plist, not a signature, and 64 bits of SHA-256 over a corpus of a few
    /// thousand comments will not collide.
    public static func key(for source: String) -> String {
        let normalised = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let digest = SHA256.hash(data: Data(normalised.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    public func reading(for source: String) -> String? {
        readings[Self.key(for: source)]
    }

    public func hasReading(for source: String) -> Bool {
        reading(for: source) != nil
    }

    /// Files a reading under its source's own key.
    ///
    /// Takes the source rather than a key so a caller cannot file a reading
    /// under the wrong text — the one bug that would show somebody a plain
    /// sentence about a different finding, with nothing on screen to say so.
    public mutating func store(_ reading: String, for source: String) {
        let trimmed = reading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        readings[Self.key(for: source)] = trimmed
    }

    public var count: Int { readings.count }

    public var isEmpty: Bool { readings.isEmpty }

    /// Which of these have never been read, so a run asks for only those.
    public func missing(from sources: [String]) -> [String] {
        var seen = Set<String>()
        return sources.filter { source in
            let key = Self.key(for: source)
            guard readings[key] == nil, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    /// Drops everything no longer on screen, then caps what is left.
    ///
    /// Pruned by what is live rather than by age, because a reading does not go
    /// stale — the text it was made from is immutable, and a changed text keys
    /// elsewhere. The only reason to drop one is that nothing will ask for it
    /// again, and "not in the current fetch" is the closest the app gets to
    /// knowing that.
    ///
    /// The cap is a backstop for the case pruning cannot see: a reading made
    /// for a pull request that closed between launches. Entries are dropped in
    /// dictionary order, which is arbitrary — acceptable because the cost of
    /// dropping a live one is a re-translation, not a wrong answer.
    public mutating func prune(keeping live: [String], limit: Int = 2_000) {
        let liveKeys = Set(live.map(Self.key(for:)))
        readings = readings.filter { liveKeys.contains($0.key) }
        guard readings.count > limit else { return }
        readings = Dictionary(uniqueKeysWithValues:
            readings.prefix(limit).map { ($0.key, $0.value) })
    }

    // MARK: - Persistence

    public static func decoded(from data: Data?) -> LensStore {
        guard let data,
              let store = try? JSONDecoder().decode(LensStore.self, from: data)
        else { return LensStore() }
        return store
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
