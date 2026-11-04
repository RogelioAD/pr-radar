import Foundation

/// What the away screen says while you are not at the desk.
///
/// The reason this screen exists rather than the system lock is that the system
/// lock can tell you nothing. Half the point of walking away from a running
/// review is being able to glance at the Mac from the doorway and see that it
/// is still going — so the content is the feature, and it lives here as a pure
/// function rather than in the view that draws it.
///
/// Decoupled from `AutoReviewLog` on purpose. The caller flattens whatever it
/// knows into `Job`s, which keeps this testable without standing up a log, and
/// keeps the rule honest about what it actually needs: a label and a duration.
public enum AwayScreen {

    public struct Job: Equatable, Sendable {
        /// Short enough to read across a room: `elevation-mobile#418`.
        public let label: String
        public let elapsed: TimeInterval

        public init(label: String, elapsed: TimeInterval) {
            self.label = label
            self.elapsed = elapsed
        }
    }

    public struct Status: Equatable, Sendable {
        public let headline: String
        public let lines: [String]
        /// Whether anything is actually happening. The screen dims its own
        /// status block when nothing is, so a glance from the doorway can tell
        /// *working* from *finished* without reading a word.
        public let isWorking: Bool
    }

    /// How many runs are named before the rest become a count.
    ///
    /// Three. This is read from across a room, by someone who wants one bit of
    /// information — is it still going — and a list long enough to need
    /// scanning has stopped answering that. The longest-running three are the
    /// ones worth naming anyway; see the sort below.
    public static let maxNamed = 3

    public static func status(running: [Job], queued: Int) -> Status {
        // Longest first, because the question behind the glance is *when will
        // this be done*, and the oldest run is the one still holding it up.
        // Ties keep their relative order, so a redraw does not reshuffle two
        // runs that started in the same second.
        let ordered = running.enumerated()
            .sorted { ($0.element.elapsed, -Double($0.offset)) > ($1.element.elapsed, -Double($1.offset)) }
            .map(\.element)

        var lines = ordered.prefix(maxNamed).map { "\($0.label) · \(RunTime.clock($0.elapsed))" }
        let unnamed = ordered.count - lines.count
        if unnamed > 0 { lines.append("+\(unnamed) more") }
        // Only once something is already running. On its own, a queue is the
        // headline rather than a footnote, and saying it twice wastes the one
        // line that is read first.
        if queued > 0 && !ordered.isEmpty { lines.append("\(queued) queued") }

        let headline: String
        if ordered.isEmpty && queued == 0 {
            headline = "Nothing running"
        } else if ordered.isEmpty {
            headline = "\(queued) waiting to start"
        } else {
            headline = "Reviewing \(ordered.count) pull request\(ordered.count == 1 ? "" : "s")"
        }

        return Status(headline: headline,
                      lines: lines,
                      isWorking: !ordered.isEmpty || queued > 0)
    }
}
