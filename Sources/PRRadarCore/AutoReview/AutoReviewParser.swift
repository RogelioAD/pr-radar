import Foundation

/// Why a review did not produce findings.
///
/// A closed set rather than a string, because the row treats these differently:
/// a timeout is worth retrying and an unparseable answer usually is not.
public enum AutoReviewFailure: Error, Equatable, Sendable {
    case notInstalled
    /// No checkout of this repository under the configured folder. Its own case
    /// rather than a general failure, because it is the one of these the user
    /// can fix in ten seconds and the row should say so in those words.
    case noClone(String)
    case timedOut(seconds: Int)
    case exited(code: Int32, stderr: String)
    case unparseable(String)

    /// What the row says. Short, because it is rendered on one line beside a
    /// Retry button, with the full text in the tooltip.
    public var message: String {
        switch self {
        case .notInstalled:
            return "Claude Code was not found"
        case .noClone(let repo):
            return "No local checkout of \(repo)"
        case .timedOut(let seconds):
            return "The review timed out after \(seconds / 60)m"
        case .exited(let code, let stderr):
            let detail = AutoReviewRecord.truncated(stderr)
            return detail.isEmpty
                ? "The review exited with code \(code) and said nothing"
                : "The review failed: \(detail)"
        case .unparseable(let detail):
            return "Could not read the review's result: \(AutoReviewRecord.truncated(detail, limit: 120))"
        }
    }
}

/// Turns what the CLI printed into findings, or into a reason there are none.
///
/// **The one rule that must not bend: a run that finished but produced nothing
/// readable is a failure, never zero findings.** Posting "no issues found"
/// because a parse fell through is the worst thing this feature could do — it
/// is an automated clean bill of health, under the user's own name, backed by
/// nothing at all.
public enum AutoReviewParser {

    /// The envelope `--output-format json` prints.
    ///
    /// Only the fields that matter here. `structuredOutput` is the schema-
    /// validated object and is the normal path; everything below it in
    /// `parse` is a fallback for a CLI that did not fill it in.
    struct Envelope: Decodable {
        let isError: Bool?
        let subtype: String?
        let result: String?
        let structuredOutput: AutoReviewFindings?

        enum CodingKeys: String, CodingKey {
            case isError = "is_error"
            case subtype
            case result
            case structuredOutput = "structured_output"
        }
    }

    public static func parse(exitCode: Int32,
                             stdout: String,
                             stderr: String,
                             timedOut: Bool,
                             timeoutSeconds: Int) -> Result<AutoReviewFindings, AutoReviewFailure> {
        if timedOut { return .failure(.timedOut(seconds: timeoutSeconds)) }
        guard exitCode == 0 else {
            // A CLI that fails on its own terms reports on *stdout*, as its
            // own JSON, and leaves stderr empty. Taking only stderr turned
            // every one of those into "exited with code 1" and nothing else —
            // which is the least useful thing a failed review can say, and
            // exactly the case someone needs the detail for.
            return .failure(.exited(code: exitCode,
                                    stderr: stderr.isEmpty ? reported(in: stdout) : stderr))
        }

        let decoder = JSONDecoder()
        let envelope = try? decoder.decode(Envelope.self, from: Data(stdout.utf8))

        // A session that reported its own failure is a failure, whatever else
        // it managed to print.
        if envelope?.isError == true {
            return .failure(.exited(code: 0, stderr: envelope?.result ?? stderr))
        }

        // 1. The schema-validated object, which is the normal path.
        if let findings = envelope?.structuredOutput {
            return .success(findings)
        }

        // 2. The result string, if it is itself the JSON.
        if let result = envelope?.result,
           let findings = try? decoder.decode(AutoReviewFindings.self, from: Data(result.utf8)) {
            return .success(findings)
        }

        // 3. JSON embedded in prose. Worth one attempt, because a model that
        //    wrapped its answer in a sentence has still done the work.
        if let result = envelope?.result,
           let embedded = firstJSONObject(in: result),
           let findings = try? decoder.decode(AutoReviewFindings.self, from: Data(embedded.utf8)) {
            return .success(findings)
        }

        // 4. Nothing readable. Not "no findings".
        let sample = envelope?.result ?? stdout
        return .failure(.unparseable(sample.isEmpty ? "the CLI printed nothing" : sample))
    }

    /// What a CLI said about its own failure, dug out of whatever it printed.
    ///
    /// The envelope's `result` if there is one, else the raw text. Either way
    /// it beats reporting only an exit code.
    static func reported(in stdout: String) -> String {
        guard !stdout.isEmpty else { return "" }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(stdout.utf8)),
           let result = envelope.result, !result.isEmpty {
            return result
        }
        return stdout
    }

    /// The first balanced `{…}` in a string, ignoring braces inside strings and
    /// the escapes inside those.
    static func firstJSONObject(in text: String) -> String? {
        var depth = 0
        var start: String.Index?
        var inString = false
        var escaped = false

        for index in text.indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{":
                if depth == 0 { start = index }
                depth += 1
            case "}":
                guard depth > 0 else { break }
                depth -= 1
                if depth == 0, let start {
                    return String(text[start...index])
                }
            default: break
            }
        }
        return nil
    }
}

// An unknown tier costs one finding rather than the whole payload: a skill
// inventing a fourth category should not throw away the three it got right.
extension AutoReviewFindings {
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.verdict = try container.decodeIfPresent(String.self, forKey: .verdict)
        var kept: [Finding] = []
        var list = try container.nestedUnkeyedContainer(forKey: .findings)
        while !list.isAtEnd {
            // Decoding into a throwaway first keeps the cursor moving even when
            // one element is unusable — a failed decode inside an unkeyed
            // container does not advance it, and the loop would never end.
            if let finding = try? list.decode(Finding.self) {
                kept.append(finding)
            } else {
                _ = try? list.decode(AnyDecodable.self)
            }
        }
        self.findings = kept
    }

    enum CodingKeys: String, CodingKey { case verdict, findings }
}

/// Swallows one element of unknown shape, so a bad entry can be stepped over.
struct AnyDecodable: Decodable {
    init(from decoder: Decoder) throws {
        _ = try? decoder.singleValueContainer()
    }
}
