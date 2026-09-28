import Foundation

/// The review skill the user typed, validated before it can be run.
///
/// Its own type for the reason `ReleaseSource` is: the setting is typed into a
/// text field, and a half-typed value must not reach the thing it configures.
/// A bad skill name here does not 404 quietly — it spawns a session that
/// answers with prose, which is a slower and more expensive way to fail.
public enum ReviewSkill {

    /// The longest a skill command may be. Generous for a name plus arguments,
    /// small enough that the field cannot become a place to write a prompt.
    static let limit = 200

    /// The value if it names a skill command, and nil if it does not.
    ///
    /// Forgiving about what people type: surrounding whitespace, and a missing
    /// leading slash — `code-review` and `/code-review` are the same request.
    /// Strict about the result: a plausible command name, optionally followed
    /// by arguments, and nothing that could be read as a second instruction.
    ///
    /// **On why newlines are rejected.** This string ends up as one element of
    /// `Process.arguments`, which reaches `posix_spawn` as an argv array — there
    /// is no shell, so `;`, `|`, backticks and `$(…)` have no meaning here and
    /// there is nothing to escape them against. The reason to be strict is a
    /// different one: the string becomes *prompt text* that a model reads, and
    /// a newline is how you make the rest of a line look like a new instruction.
    public static func normalized(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count <= limit else { return nil }
        guard !text.unicodeScalars.contains(where: isControl) else { return nil }

        let body = text.hasPrefix("/") ? String(text.dropFirst()) : text
        var parts = body.split(separator: " ", maxSplits: 1,
                               omittingEmptySubsequences: true)
        guard let name = parts.first, isCommandName(name) else { return nil }

        let rest = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespaces)
            : ""
        return rest.isEmpty ? "/\(name)" : "/\(name) \(rest)"
    }

    /// Just the command, without whatever arguments follow it. What the comment
    /// body names when it says which skill produced the findings.
    public static func name(of normalized: String) -> String {
        String(normalized.split(separator: " ", maxSplits: 1).first ?? "")
    }

    /// Skill names are letters, digits, and `-._:~`. The colon is what lets a
    /// plugin-qualified name like `acme:review` through.
    private static func isCommandName(_ part: Substring) -> Bool {
        guard !part.isEmpty, part.count <= 64 else { return false }
        guard let first = part.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._:~"))
        return part.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static func isControl(_ scalar: Unicode.Scalar) -> Bool {
        CharacterSet.controlCharacters.contains(scalar)
    }
}
