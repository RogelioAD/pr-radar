import Foundation

/// What came back from one lens run, before it is filed against its sources.
public struct LensReadings: Codable, Equatable, Sendable {
    public struct Reading: Codable, Equatable, Sendable {
        public let id: String
        public let plain: String

        public init(id: String, plain: String) {
            self.id = id
            self.plain = plain
        }
    }

    public let readings: [Reading]

    public init(readings: [Reading]) {
        self.readings = readings
    }
}

/// Turns what the CLI printed into readings, or into nothing at all.
///
/// **A failure here is silent, and that is the whole difference between this
/// parser and its siblings.** `AutoReviewParser` must distinguish "no findings"
/// from "could not read the answer", because the first is a clean bill of
/// health somebody would post under their own name. Nothing is posted here and
/// nothing is claimed: a lens run that fails leaves the original text on screen,
/// which is where it started and is always correct. So this returns what it
/// could read and says nothing about the rest, rather than carrying a failure
/// up to a row that has nowhere useful to put it.
///
/// The one thing it will not do is guess. An id outside the range sent, or a
/// reading that came back empty, is dropped — a reading filed against the wrong
/// source would be the only way this feature can actively mislead, and dropping
/// one costs a sentence that stays in its original words.
public enum LensParser {

    struct Envelope: Decodable {
        let isError: Bool?
        let result: String?
        let structuredOutput: LensReadings?

        enum CodingKeys: String, CodingKey {
            case isError = "is_error"
            case result
            case structuredOutput = "structured_output"
        }
    }

    /// Readings by the source they belong to, ready to be stored.
    ///
    /// Takes the sources it sent so the index mapping is closed here rather
    /// than at the call site: the parser is the only thing that knows the ids
    /// are indices into that array, and letting a coordinator re-derive it is
    /// how the two drift.
    public static func parse(exitCode: Int32,
                             stdout: String,
                             timedOut: Bool,
                             sources: [String]) -> [(source: String, plain: String)] {
        guard !timedOut, exitCode == 0 else { return [] }

        let decoder = JSONDecoder()
        let envelope = try? decoder.decode(Envelope.self, from: Data(stdout.utf8))
        if envelope?.isError == true { return [] }

        let readings: LensReadings? = {
            if let structured = envelope?.structuredOutput { return structured }
            if let result = envelope?.result,
               let decoded = try? decoder.decode(LensReadings.self, from: Data(result.utf8)) {
                return decoded
            }
            if let result = envelope?.result,
               let embedded = AutoReviewParser.firstJSONObject(in: result),
               let decoded = try? decoder.decode(LensReadings.self, from: Data(embedded.utf8)) {
                return decoded
            }
            return nil
        }()

        guard let readings else { return [] }

        var seen = Set<Int>()
        return readings.readings.compactMap { reading in
            guard let index = Int(reading.id),
                  sources.indices.contains(index),
                  // One reading per source. A second claiming the same index is
                  // dropped rather than overwriting: nothing here can tell
                  // which of the two was meant, and the first is as good a
                  // guess as any while being the only stable one.
                  !seen.contains(index)
            else { return nil }
            let plain = reading.plain.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !plain.isEmpty else { return nil }
            seen.insert(index)
            return (source: sources[index], plain: plain)
        }
    }
}
