import Foundation

/// Which lines of a pull request can carry an inline comment.
///
/// GitHub rejects a review thread anchored to a line that is not part of the
/// diff, and it rejects the *whole* review when one thread is wrong — so a
/// single finding pointing at an untouched line would cost every other finding
/// too. This is the check that stops that happening, and it is pure so the
/// rules about it can be argued with in tests rather than against the API.
///
/// Only the RIGHT side is modelled: added and context lines, numbered in the
/// head blob. That is the side a review of "what this PR does" belongs on, and
/// it is the side whose numbers the checked-out worktree agrees with.
public struct DiffMap: Equatable, Sendable {

    /// Commentable line numbers per path, and the hunks they came from, so a
    /// near-miss can be snapped without wandering into an unrelated change.
    public struct Hunk: Equatable, Sendable {
        public let start: Int
        public let end: Int
        /// Lines present on the right side — added and context alike.
        public let lines: Set<Int>
        public func contains(_ line: Int) -> Bool { line >= start && line <= end }
    }

    public private(set) var hunks: [String: [Hunk]] = [:]

    public init(hunks: [String: [Hunk]] = [:]) { self.hunks = hunks }

    public var paths: Set<String> { Set(hunks.keys) }

    public func isCommentable(path: String, line: Int) -> Bool {
        hunks[path]?.contains { $0.lines.contains(line) } ?? false
    }

    /// The nearest commentable line **within the same hunk**, or nil.
    ///
    /// Bounded, and refusing to cross a hunk boundary, because the point of
    /// snapping is to rescue an off-by-a-line anchor — not to reattach a
    /// finding to an unrelated change forty lines away, where it would read as
    /// a confident comment about the wrong code.
    public func snap(path: String, line: Int, within: Int = 3) -> Int? {
        guard let hunks = hunks[path] else { return nil }
        guard let hunk = hunks.first(where: { $0.contains(line) })
            ?? hunks.first(where: { abs($0.start - line) <= within || abs($0.end - line) <= within })
        else { return nil }

        if hunk.lines.contains(line) { return line }
        return hunk.lines
            .filter { abs($0 - line) <= within }
            .min { abs($0 - line) < abs($1 - line) }
    }

    /// Parses `git diff` / `gh pr diff` output.
    ///
    /// Tolerant by design: an unrecognised header is skipped rather than
    /// failing the map, because the cost of one unparsed file is findings that
    /// fall back to the summary body, and the cost of throwing is no review.
    public static func parse(unifiedDiff text: String) -> DiffMap {
        var hunks: [String: [Hunk]] = [:]
        var path: String?
        var right = 0
        var start = 0
        var lines: Set<Int> = []

        func closeHunk() {
            guard let path, !lines.isEmpty else { lines = []; return }
            hunks[path, default: []].append(
                Hunk(start: start, end: lines.max() ?? start, lines: lines))
            lines = []
        }

        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)

            if line.hasPrefix("diff --git ") {
                closeHunk()
                path = nil
                continue
            }
            // `+++ b/path` is the new name, which is the one a RIGHT-side
            // comment is addressed to — so a rename anchors to where the file
            // ends up, not where it started.
            if line.hasPrefix("+++ ") {
                closeHunk()
                let target = String(line.dropFirst(4))
                path = target == "/dev/null" ? nil : strippingPrefix(target)
                continue
            }
            if line.hasPrefix("@@") {
                closeHunk()
                guard let parsed = newStart(ofHunkHeader: line) else { continue }
                right = parsed
                start = parsed
                continue
            }
            guard path != nil else { continue }

            if line.hasPrefix("+") {
                lines.insert(right)
                right += 1
            } else if line.hasPrefix("-") {
                continue                       // left side only; not commentable
            } else if line.hasPrefix(" ") || line.isEmpty {
                lines.insert(right)            // context is commentable too
                right += 1
            }
            // "\\ No newline at end of file" and anything else: ignored.
        }
        closeHunk()

        return DiffMap(hunks: hunks)
    }

    /// `@@ -12,7 +34,9 @@` → 34.
    static func newStart(ofHunkHeader header: String) -> Int? {
        guard let plus = header.firstIndex(of: "+") else { return nil }
        let rest = header[header.index(after: plus)...]
        let digits = rest.prefix { $0.isNumber }
        return Int(digits)
    }

    /// Drops the `a/` or `b/` git puts in front of a path.
    static func strippingPrefix(_ path: String) -> String {
        for prefix in ["a/", "b/"] where path.hasPrefix(prefix) {
            return String(path.dropFirst(prefix.count))
        }
        return path
    }
}
