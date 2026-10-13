import Foundation

/// Why a resolve run produced nothing usable.
///
/// Mostly the review failures with different wording, plus one case that has no
/// review equivalent and is the reason this is its own type: `landedUnreported`.
public enum ResolveFailure: Error, Equatable, Sendable {
    case notInstalled
    case blocked(ResolveBlock)
    case timedOut(seconds: Int)
    case exited(code: Int32, stderr: String)
    case unparseable(String)
    /// The run pushed commits and then produced no readable table.
    ///
    /// Its own case, and never merged into `unparseable`, because the two call
    /// for opposite reactions. An unreadable run that changed nothing can
    /// simply be run again. This one has put code on the user's branch that
    /// nobody has read a word about, and the only useful thing to say is
    /// *go and look*, with the commits named.
    case landedUnreported(shas: [String])

    /// A row-sized message.
    public var message: String {
        switch self {
        case .notInstalled:
            return "Claude Code was not found"
        case .blocked(let block):
            return block.reason
        case .timedOut(let seconds):
            return "gave up after \(seconds / 60)m"
        case .exited(let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "exited with code \(code)"
                : AutoReviewRecord.truncated(detail)
        case .unparseable(let sample):
            return "could not be read — " + AutoReviewRecord.truncated(sample, limit: 160)
        case .landedUnreported(let shas):
            return "pushed \(shas.count) commit\(shas.count == 1 ? "" : "s") "
                 + "and then failed — go and look"
        }
    }
}

/// Turns what the CLI printed into a disposition table, or into a reason there
/// is not one.
///
/// Inherits `AutoReviewParser`'s cardinal rule — **a run that finished but
/// produced nothing readable is a failure, never an empty table** — and adds
/// one of its own, which matters more here: a run that *pushed* and produced
/// nothing readable is not merely a failure. Code is on the branch. Reporting
/// that as "could not be read" invites a retry, and a retry would layer a
/// second set of fixes on a first set nobody has seen.
public enum ResolveParser {

    struct Envelope: Decodable {
        let isError: Bool?
        let result: String?
        let structuredOutput: ResolveTable?

        enum CodingKeys: String, CodingKey {
            case isError = "is_error"
            case result
            case structuredOutput = "structured_output"
        }
    }

    public static func parse(exitCode: Int32,
                             stdout: String,
                             stderr: String,
                             timedOut: Bool,
                             timeoutSeconds: Int,
                             pushedShas: [String] = []) -> Result<ResolveTable, ResolveFailure> {
        func fail(_ failure: ResolveFailure) -> Result<ResolveTable, ResolveFailure> {
            // Whatever went wrong, if commits landed then that is the headline.
            // The detail is kept in the log; the row has to say the thing the
            // user has to act on.
            .failure(pushedShas.isEmpty ? failure : .landedUnreported(shas: pushedShas))
        }

        if timedOut { return fail(.timedOut(seconds: timeoutSeconds)) }

        let decoder = JSONDecoder()
        let envelope = try? decoder.decode(Envelope.self, from: Data(stdout.utf8))

        guard exitCode == 0 else {
            let detail = stderr.isEmpty ? (envelope?.result ?? stdout) : stderr
            return fail(.exited(code: exitCode, stderr: detail))
        }

        if envelope?.isError == true {
            return fail(.exited(code: 0, stderr: envelope?.result ?? stderr))
        }

        // 1. The schema-validated object.
        if let table = envelope?.structuredOutput {
            return .success(table)
        }
        // 2. The result string, when it is itself the JSON.
        if let result = envelope?.result,
           let table = try? decoder.decode(ResolveTable.self, from: Data(result.utf8)) {
            return .success(table)
        }
        // 3. JSON wrapped in prose. One attempt, because a model that explained
        //    its answer has still done the work.
        if let result = envelope?.result,
           let embedded = AutoReviewParser.firstJSONObject(in: result),
           let table = try? decoder.decode(ResolveTable.self, from: Data(embedded.utf8)) {
            return .success(table)
        }

        let sample = envelope?.result ?? stdout
        return fail(.unparseable(sample.isEmpty ? "the CLI printed nothing" : sample))
    }
}
