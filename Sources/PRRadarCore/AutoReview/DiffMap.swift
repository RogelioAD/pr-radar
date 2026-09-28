import Foundation

/// One line of a unified diff, as it will be drawn.
///
/// Codable because it outlives the worktree it was read from. The diff exists
/// exactly once — in the checkout the review ran in, which is deleted the
/// moment the run ends — so a line nobody kept is a line nobody can ever show.
public struct DiffLine: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case added, removed, context
    }

    public let kind: Kind
    /// The right-side number. nil for a removed line, which has none: it is
    /// not in the head blob at all, which is also why it can carry no comment.
    public let number: Int?
    /// The line's text, without the leading `+`, `-` or space.
    public let text: String

    public init(kind: Kind, number: Int?, text: String) {
        self.kind = kind
        self.number = number
        self.text = text
    }
}

/// The code around one finding, the way GitHub shows it above a comment.
public struct DiffExcerpt: Codable, Equatable, Sendable {
    public let path: String
    public let lines: [DiffLine]
    /// The line the comment anchors to, so the view can mark which of these is
    /// the one being talked about.
    public let focus: Int
    /// The first line of the range when the comment covers more than one.
    public let focusStart: Int?

    public init(path: String, lines: [DiffLine], focus: Int, focusStart: Int? = nil) {
        self.path = path
        self.lines = lines
        self.focus = focus
        self.focusStart = focusStart
    }

    /// Whether a line is one the comment is about.
    public func isFocused(_ number: Int?) -> Bool {
        guard let number else { return false }
        return number >= (focusStart ?? focus) && number <= focus
    }
}

extension DiffExcerpt {

    /// Builds an excerpt from GitHub's `diffHunk`, which is a bare unified-diff
    /// fragment: one `@@` header and the lines under it, ending at the line the
    /// comment was left on.
    ///
    /// A parser of its own rather than `DiffMap.parse`, which wants the `+++`
    /// header a real diff carries and skips every line until it sees one. There
    /// is no file header here because there is no file — GitHub has already
    /// told us the path separately.
    ///
    /// The *tail* is kept when it is too long, not the head. The comment is
    /// anchored to the last line of the hunk, and lead-in that pushes the line
    /// being talked about off the bottom is lead-in nobody needed.
    public static func parse(diffHunk: String,
                             path: String,
                             line: Int?,
                             keepingLast keep: Int = 8) -> DiffExcerpt? {
        var right = 0
        var lines: [DiffLine] = []
        // Nothing counts until a header has said where the numbering starts.
        // Without this an empty string parses as one blank context line on line
        // zero — a hunk with nothing in it, drawn as though it were code.
        var numbered = false

        for raw in diffHunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(raw)
            if text.hasPrefix("@@") {
                guard let start = DiffMap.newStart(ofHunkHeader: text) else { continue }
                right = start
                numbered = true
                // A second header means a second hunk, and only the one the
                // comment sits in is wanted.
                lines.removeAll()
                continue
            }
            guard numbered else { continue }
            if text.hasPrefix("+") {
                lines.append(DiffLine(kind: .added, number: right,
                                      text: String(text.dropFirst())))
                right += 1
            } else if text.hasPrefix("-") {
                lines.append(DiffLine(kind: .removed, number: nil,
                                      text: String(text.dropFirst())))
            } else if text.hasPrefix(" ") || text.isEmpty {
                lines.append(DiffLine(kind: .context, number: right,
                                      text: text.isEmpty ? "" : String(text.dropFirst())))
                right += 1
            }
        }

        guard !lines.isEmpty else { return nil }
        let kept = lines.count > keep ? Array(lines.suffix(keep)) : lines
        // The line GitHub named, and the last numbered line as the fallback —
        // which is where a review comment is anchored when nothing says
        // otherwise.
        let focus = line ?? kept.compactMap(\.number).max() ?? 0
        return DiffExcerpt(path: path, lines: kept, focus: focus)
    }
}

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
        /// Every line of the hunk in order, removals included, so a finding can
        /// show the code it is about rather than only assert a number.
        ///
        /// Defaulted to empty: a map built by hand in a test is asking about
        /// anchoring, not about text, and should not have to invent any.
        public let rendered: [DiffLine]

        public init(start: Int, end: Int, lines: Set<Int>, rendered: [DiffLine] = []) {
            self.start = start
            self.end = end
            self.lines = lines
            self.rendered = rendered
        }

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
        var rendered: [DiffLine] = []

        func closeHunk() {
            guard let path, !lines.isEmpty else { lines = []; rendered = []; return }
            hunks[path, default: []].append(
                Hunk(start: start, end: lines.max() ?? start,
                     lines: lines, rendered: rendered))
            lines = []
            rendered = []
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
                rendered.append(DiffLine(kind: .added, number: right,
                                         text: String(line.dropFirst())))
                right += 1
            } else if line.hasPrefix("-") {
                // Left side only, so it carries no comment — but it is kept for
                // showing. A change reads as a change because the line it
                // replaced is above it; dropping removals would turn every edit
                // into an unexplained addition.
                rendered.append(DiffLine(kind: .removed, number: nil,
                                         text: String(line.dropFirst())))
            } else if line.hasPrefix(" ") || line.isEmpty {
                lines.insert(right)            // context is commentable too
                rendered.append(DiffLine(kind: .context, number: right,
                                         text: line.isEmpty ? "" : String(line.dropFirst())))
                right += 1
            }
            // "\\ No newline at end of file" and anything else: ignored.
        }
        closeHunk()

        return DiffMap(hunks: hunks)
    }

    /// The code around a line, the way GitHub shows it above an inline comment.
    ///
    /// A window of `context` lines either side, counted in *rows* rather than
    /// in line numbers, so the removals that explain a change come along with
    /// it — they have no number to be within range of, and a window measured in
    /// numbers would silently drop exactly the lines that make an edit legible.
    ///
    /// nil when the line is not in any hunk. That is the same condition as "not
    /// commentable", so a finding with no excerpt is a finding with no inline
    /// thread either, and the two stay consistent without being coordinated.
    public func excerpt(path: String, line: Int, startLine: Int? = nil,
                        context: Int = 3) -> DiffExcerpt? {
        guard let hunk = hunks[path]?.first(where: { $0.lines.contains(line) }),
              !hunk.rendered.isEmpty,
              let focusIndex = hunk.rendered.firstIndex(where: { $0.number == line })
        else { return nil }

        // From the *first* commented line, so a multi-line finding shows its
        // whole range rather than the tail of it with three lines of lead-in.
        let firstIndex = startLine
            .flatMap { start in hunk.rendered.firstIndex { $0.number == start } }
            ?? focusIndex

        let lower = max(hunk.rendered.startIndex, min(firstIndex, focusIndex) - context)
        let upper = min(hunk.rendered.endIndex, focusIndex + context + 1)

        return DiffExcerpt(path: path,
                           lines: Array(hunk.rendered[lower..<upper]),
                           focus: line,
                           focusStart: startLine)
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
