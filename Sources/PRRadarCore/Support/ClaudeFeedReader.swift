import Foundation

/// Finds the live Claude Code sessions on this Mac and reads each one's tail.
///
/// Separated from `ClaudeFeed` so the rules stay pure and this stays dumb: it
/// knows where the files are and how little of them to read, and every decision
/// about what any of it *means* is next door.
///
/// **Cheap on purpose, because it runs behind a screen that is meant to be
/// left alone.** There are a hundred project directories on this machine and
/// some transcripts are tens of megabytes. So: stat first, read only what moved
/// recently, and read only the end of that. The cost of a refresh is a
/// directory listing plus a few hundred kilobytes, not a hundred megabytes.
public enum ClaudeFeedReader {

    /// How much of each transcript's end is read.
    ///
    /// 256KB holds far more than the handful of lines the state is decided
    /// from, and enough history that a `Task` launched earlier in the same turn
    /// is still in view — which is what keeps a long-running agent from
    /// vanishing off the list while it is still running. A `Task` launched
    /// before that much text is not reported, and that is the one piece of
    /// under-reporting here worth knowing about.
    public static let tailBytes = 262_144

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }

    /// Every session whose transcript has moved inside the window.
    ///
    /// Recency stands in for *alive* rather than consulting the process table.
    /// A session is identified by its working directory, a `claude` process is
    /// not easily mapped back to one without a `lsof` per process, and the
    /// question being asked — has this moved lately — is answered exactly by
    /// the thing recency measures. A terminal someone closed stops writing and
    /// falls off by itself.
    public static func sessions(root: URL = ClaudeFeedReader.defaultRoot,
                                now: Date = Date(),
                                window: TimeInterval = ClaudeFeed.window) -> [ClaudeFeed.Session] {
        let manager = FileManager.default
        guard let projects = try? manager.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var found: [ClaudeFeed.Session] = []

        for project in projects {
            guard let files = try? manager.contentsOfDirectory(
                at: project, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]) else { continue }

            // One session per project: the newest transcript. Two terminals in
            // the same directory would otherwise both be listed under the same
            // name, which reads as duplication rather than as information.
            let newest = files
                .filter { $0.pathExtension == "jsonl" }
                .compactMap { url -> (URL, Date)? in
                    guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate else { return nil }
                    return (url, date)
                }
                .max { $0.1 < $1.1 }

            guard let (url, modified) = newest else { continue }
            let idle = now.timeIntervalSince(modified)
            guard idle >= 0, idle <= window else { continue }
            guard let tail = tail(of: url) else { continue }
            guard let session = ClaudeFeed.session(fromTail: tail, idleFor: idle) else { continue }
            found.append(session)
        }

        return ClaudeFeed.ordered(found)
    }

    /// The last `tailBytes` of a file, as text.
    ///
    /// Reads rather than memory-maps, and never holds the handle: these are
    /// files another process is actively appending to, and the one obligation
    /// this feature has towards Claude Code is to stay entirely out of its way.
    static func tail(of url: URL, limit: Int = ClaudeFeedReader.tailBytes) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        let offset = size > UInt64(limit) ? size - UInt64(limit) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.readToEnd() else { return nil }
        // Lossy on purpose: a tail can begin inside a multi-byte character,
        // and one mangled leading glyph on a line that is dropped anyway is
        // not a reason to report nothing.
        return String(decoding: data, as: UTF8.self)
    }
}
