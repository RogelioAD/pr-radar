import Foundation

/// The one line of a pull request's description worth putting on a row.
///
/// A title and a diff size decide whether a review is big. The *body* is where
/// people write the things that decide whether to start it at all — "don't
/// review yet", "part 2 of 3", "only the last commit is new" — and it was the
/// one thing the row could not say.
///
/// Not the literal first line. Real descriptions open with a template heading,
/// an HTML comment the author never deleted, or a rule — and a row reading
/// `## Summary` would be worse than a row reading nothing, because it looks
/// like the feature working.
public enum PRSummary {

    /// How much is kept. Enough for a sentence, and bounded so a four-kilobyte
    /// template cannot ride around in memory on thirty rows.
    public static let limit = 280

    /// The first line that actually says something, trimmed and shortened.
    /// nil for a body that is empty, or is nothing but furniture.
    public static func firstLine(of body: String?) -> String? {
        guard let body else { return nil }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var inComment = false

        for (index, raw) in lines.enumerated() {
            var line = raw

            // HTML comments are where pull request templates keep their
            // instructions, and the instructions are never the summary. They
            // run across lines, so this tracks the state rather than testing
            // each line on its own.
            if inComment {
                guard let end = line.range(of: "-->") else { continue }
                inComment = false
                line = String(line[end.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
            while let start = line.range(of: "<!--") {
                guard let end = line.range(of: "-->", range: start.upperBound..<line.endIndex)
                else {
                    line = String(line[..<start.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                    inComment = true
                    break
                }
                line = (String(line[..<start.lowerBound]) + String(line[end.upperBound...]))
                    .trimmingCharacters(in: .whitespaces)
            }

            guard !line.isEmpty, !isFurniture(line) else { continue }
            // A line underlined with `===` or `---` is a heading too — the
            // setext form, which carries its marker on the *next* line. Worth
            // the lookahead: it is the form every template written in a text
            // editor rather than a browser tends to use.
            if index + 1 < lines.count, isUnderline(lines[index + 1]) { continue }
            return String(cleaned(line).prefix(limit))
        }
        return nil
    }

    /// Markup that is noise once the line is a single row of text.
    ///
    /// Only the markers that wrap a whole line. The inside of a sentence is
    /// left exactly as it was written — stripping emphasis from the middle of
    /// one is how `a **hard** no` becomes `a hard no`, which is a different
    /// sentence told in a flatter voice.
    static func cleaned(_ line: String) -> String {
        var text = line
        // Block quote markers, which a template uses for its own asides.
        while text.hasPrefix(">") {
            text = String(text.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        // A whole line in bold or italics is a heading wearing a disguise.
        for marker in ["**", "__", "*", "_"] where
            text.count > marker.count * 2
            && text.hasPrefix(marker) && text.hasSuffix(marker) {
            let inner = text.dropFirst(marker.count).dropLast(marker.count)
            // Only when there is no second pair inside, so `**a** and **b**`
            // is left alone rather than collapsed to `a** and **b`.
            if !inner.contains(marker) {
                text = String(inner).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return text
    }

    /// `===` or `---` under a line, which makes that line a heading.
    static func isUnderline(_ line: String) -> Bool {
        guard line.count >= 2 else { return false }
        return line.allSatisfy { $0 == "=" } || line.allSatisfy { $0 == "-" }
    }

    /// Lines that are structure rather than content.
    ///
    /// Headings, horizontal rules, and the bare markers a template leaves
    /// behind. A heading is the commonest by a distance: half the descriptions
    /// in a repo with a template start `## Summary`, and that is the template
    /// talking, not the author.
    static func isFurniture(_ line: String) -> Bool {
        if line.hasPrefix("#") { return true }
        // `---`, `***`, `___`, `===` and longer. The equals rule is not about
        // horizontal rules, which cannot be written that way — it is there
        // because a setext underline is skipped by the *line above* it, which
        // leaves the underline itself still to be stepped over.
        if line.count >= 2,
           line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" || $0 == "=" }) {
            return true
        }
        // An empty list item or an unfilled checkbox: `-`, `* `, `- [ ]`.
        let stripped = line
            .replacingOccurrences(of: "[ ]", with: "")
            .replacingOccurrences(of: "[x]", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-*+ \t"))
        return stripped.isEmpty
    }
}
