import Foundation

/// One inline comment, ready to be sent as a draft review thread.
public struct ReviewThread: Codable, Equatable, Sendable {
    public let path: String
    /// The last line of the range, which is the line GitHub anchors to.
    public let line: Int
    /// The first line, when the thread covers more than one. nil for a single
    /// line — GitHub rejects a `startLine` equal to `line`.
    public let startLine: Int?
    public let body: String

    public init(path: String, line: Int, startLine: Int? = nil, body: String) {
        self.path = path
        self.line = line
        self.startLine = startLine
        self.body = body
    }
}

/// What PR Radar actually submits: a summary, and the threads to hang off it.
public struct ComposedReview: Equatable, Sendable {
    public let body: String
    public let threads: [ReviewThread]
    /// Findings that had nowhere to hang, so the body carries them instead.
    public let unanchored: [Finding]

    public init(body: String, threads: [ReviewThread] = [], unanchored: [Finding] = []) {
        self.body = body
        self.threads = threads
        self.unanchored = unanchored
    }
}

/// One finding, with where it would be anchored and whether it is going out.
///
/// The unit the curated mode works in. Deselecting a finding has to change the
/// *summary* as well as drop its inline thread — the body lists them — so what
/// gets persisted between composing and posting cannot be a finished review.
/// It has to be the parts, with the anchoring already worked out, because the
/// diff they were anchored against is long gone by the time anybody ticks a box.
public struct PreparedFinding: Codable, Equatable, Sendable, Identifiable {
    public let finding: Finding
    /// The inline thread this would post as, or nil when it had nowhere to
    /// hang and the summary is its only home.
    public let anchor: ReviewThread?
    public var isSelected: Bool

    public init(finding: Finding, anchor: ReviewThread?, isSelected: Bool) {
        self.finding = finding
        self.anchor = anchor
        self.isSelected = isSelected
    }

    public var id: String { AutoReviewComment.identity(finding) }
    public var tier: FindingTier { finding.tier }
    public var isAnchored: Bool { anchor != nil }

    /// Where it will appear, for the row to say so plainly.
    public var location: String? {
        guard let file = finding.file else { return nil }
        let short = file.split(separator: "/").last.map(String.init) ?? file
        return finding.line.map { "\(short):\($0)" } ?? short
    }
}

extension AutoReviewRecord {
    /// The review this record is holding, ready to send — body *and* threads.
    ///
    /// A rule rather than two lines at the call site, and in Core rather than
    /// in the coordinator, because it is the thing that broke: with automatic
    /// posting off, a review is composed on one launch and sent on a button
    /// press later, and the code that rebuilt it for sending passed
    /// `threads: []`. Every manually-posted review went out as a bare summary,
    /// silently dropping the findings-at-`file:line` the whole feature is for,
    /// and nothing failed — the review posted, it was simply empty of the part
    /// that mattered.
    ///
    /// Reconstructing it in one tested place is what stops that being rewritten
    /// by hand a third time. nil when there is nothing to send.
    public var heldReview: ComposedReview? {
        guard let body, !body.isEmpty else { return nil }
        return ComposedReview(body: body, threads: threads)
    }

    /// How many findings are ticked, and how many there are to tick.
    public var selection: (chosen: Int, total: Int) {
        (prepared.filter(\.isSelected).count, prepared.count)
    }

    /// The prepared findings of one tier, in the order they were found.
    public func findings(in tier: FindingTier) -> [PreparedFinding] {
        prepared.filter { $0.tier == tier }
    }

    /// Whether this review is waiting to be picked over rather than sent.
    public var isAwaitingSelection: Bool { status == .ready && !prepared.isEmpty }
}

/// Turns findings into the review PR Radar posts.
///
/// Pure, and the only place that decides what a colleague ends up reading
/// under the user's name — which is reason enough for it to be somewhere the
/// wording can be argued with in a test.
public enum AutoReviewComment {

    /// Appended when GitHub refused the inline anchors and the summary went out
    /// alone, so the pull request says why the findings are in one block rather
    /// than against the lines they are about.
    ///
    /// Said on the review itself rather than only in the app: the person
    /// reading it is the author, who has no way to see PR Radar's row.
    public static let anchorsDroppedNote = """


    ---

    *GitHub would not anchor these findings to their lines — usually because     the line is outside this pull request's diff — so they are listed above     rather than attached inline.*
    """

    /// GitHub's own limit is 65536; the margin is for the marker and footer.
    static let bodyLimit = 60_000

    public static let markerPrefix = "<!-- pr-radar:auto-review v1"

    public static func marker(pingKey: String) -> String {
        "\(markerPrefix) key=\(pingKey) -->"
    }

    /// Whether a body is one of ours.
    ///
    /// The marker is how a re-run recognises its own work when the record that
    /// held the node id has been pruned. The title line is how a human does.
    public static func isOurs(_ body: String) -> Bool {
        body.contains(markerPrefix)
    }

    public static func pingKey(in body: String) -> String? {
        guard let start = body.range(of: "\(markerPrefix) key="),
              let end = body.range(of: " -->", range: start.upperBound..<body.endIndex)
        else { return nil }
        return String(body[start.upperBound..<end.lowerBound])
    }

    // MARK: - The whole review

    /// Works out, once, where every finding could go and whether it starts
    /// ticked — then hands back the parts rather than a finished review.
    ///
    /// Anchoring happens here because it needs the diff, and the diff is
    /// available exactly once: in the worktree the review just ran in. By the
    /// time somebody is ticking boxes it is gone.
    ///
    /// Nits are prepared like everything else but start unticked. They are
    /// anchored rather than discarded so that opting one in is a tick and not
    /// a re-run — but posting a colleague a list of nits under your own name
    /// stays a deliberate act.
    public static func prepare(_ findings: AutoReviewFindings,
                               diff: DiffMap) -> [PreparedFinding] {
        findings.findings.map { finding in
            PreparedFinding(finding: finding,
                            anchor: thread(for: finding, in: diff),
                            isSelected: finding.tier != .nit)
        }
    }

    public static func compose(_ findings: AutoReviewFindings,
                               skill: String,
                               pingKey: String,
                               diff: DiffMap) -> ComposedReview {
        compose(prepare(findings, diff: diff), skill: skill, pingKey: pingKey)
    }

    /// The review a selection adds up to.
    ///
    /// Recomposed rather than filtered: the summary *lists* the findings, so
    /// unticking one has to remove it from the body as well as drop its inline
    /// thread. Filtering the threads alone would post a summary describing
    /// comments that are not there.
    public static func compose(_ prepared: [PreparedFinding],
                               skill: String,
                               pingKey: String) -> ComposedReview {
        let chosen = prepared.filter(\.isSelected)
        let threads = chosen.compactMap(\.anchor)
        let unanchored = chosen.filter { !$0.isAnchored }.map(\.finding)
        return ComposedReview(
            body: body(chosen.map(\.finding),
                       skill: skill,
                       pingKey: pingKey,
                       unanchored: unanchored,
                       omitted: prepared.filter { !$0.isSelected }.map(\.finding)),
            threads: threads,
            unanchored: unanchored)
    }

    // MARK: - The summary

    /// The comment a reviewer reads first.
    ///
    /// It lists every finding going out even though each is also inline,
    /// because somebody scanning the conversation should not have to open the
    /// Files tab to learn how many there are — and because a finding with
    /// nowhere to hang has no other home.
    public static func body(_ findings: [Finding],
                            skill: String,
                            pingKey: String,
                            unanchored: [Finding] = [],
                            omitted: [Finding] = []) -> String {
        var lines = [marker(pingKey: pingKey)]
        lines.append("**PR Radar** · automatic review · `\(ReviewSkill.name(of: skill))`")
        lines.append("")
        lines.append(tally(findings))
        lines.append("")

        let unanchoredIDs = Set(unanchored.map(identity))
        for tier in FindingTier.allCases {
            let tierFindings = findings.filter { $0.tier == tier }
            guard !tierFindings.isEmpty else { continue }
            lines.append("### \(tier.rawValue.capitalized)")
            for finding in tierFindings {
                lines.append(summaryLine(finding, inlined: !unanchoredIDs.contains(identity(finding))))
            }
            lines.append("")
        }

        // Said rather than left out, and said by tier. A review that quietly
        // dropped half of what it found would be claiming the rest was all
        // there was — and "3 nits" and "3 priority" are very different things
        // to have decided not to mention.
        if let note = omittedNote(omitted) {
            lines.append(note)
            lines.append("")
        }

        lines.append("<sub>Posted automatically by PR Radar. A comment, not a verdict — "
                     + "no approval or change request has been submitted.</sub>")

        return truncated(lines.joined(separator: "\n"))
    }

    /// Never empty, which is what lets it be reused as a REQUEST_CHANGES body —
    /// GitHub rejects that mutation without one.
    public static func reviewBody(_ findings: AutoReviewFindings, skill: String) -> String {
        var lines = ["**PR Radar** · requested changes from an automatic review "
                     + "· `\(ReviewSkill.name(of: skill))`", ""]
        let priority = findings.of(.priority)
        if priority.isEmpty {
            lines.append("No priority findings; see the review comments above.")
        } else {
            for finding in priority { lines.append(summaryLine(finding, inlined: false)) }
        }
        return truncated(lines.joined(separator: "\n"))
    }

    /// What a superseded review's body is rewritten to, so the Files tab does
    /// not fill with suggestions that no longer apply.
    public static func supersededBody(pingKey: String) -> String {
        "\(marker(pingKey: pingKey))\n"
        + "_Superseded by a newer PR Radar review._"
    }

    // MARK: - One inline thread

    static func thread(for finding: Finding, in diff: DiffMap) -> ReviewThread? {
        guard let path = finding.file, let range = finding.lineRange else { return nil }

        // Anchor the whole range or none of it. A multi-line thread whose start
        // is outside the diff is rejected, and one rejected thread costs the
        // entire review rather than just itself.
        let anchored: ClosedRange<Int>
        if diff.isCommentable(path: path, line: range.lowerBound),
           diff.isCommentable(path: path, line: range.upperBound) {
            anchored = range
        } else if range.count == 1, let snapped = diff.snap(path: path, line: range.lowerBound) {
            anchored = snapped...snapped
        } else {
            return nil
        }

        let moved = anchored != range
        return ReviewThread(
            path: path,
            line: anchored.upperBound,
            startLine: anchored.count > 1 ? anchored.lowerBound : nil,
            body: threadBody(finding, moved: moved, originalLine: range.lowerBound))
    }

    static func threadBody(_ finding: Finding, moved: Bool, originalLine: Int) -> String {
        var lines = ["**\(finding.tier.rawValue.capitalized)** — \(finding.summary)"]
        if let detail = finding.detail, !detail.isEmpty {
            lines.append("")
            lines.append(detail)
        }
        lines.append("")
        lines.append(finding.recommendation)

        if let suggestion = suggestion(for: finding), !moved {
            lines.append("")
            lines.append("```suggestion")
            lines.append(suggestion)
            lines.append("```")
        }
        if moved {
            lines.append("")
            lines.append("_Reported at line \(originalLine), which is not part of this diff; "
                         + "anchored to the nearest changed line._")
        }
        return lines.joined(separator: "\n")
    }

    /// A suggestion, but only when it can be applied cleanly.
    ///
    /// GitHub's Apply button replaces exactly the commented range, so a block
    /// whose line count does not match the range silently deletes or duplicates
    /// code. A wrong Apply button is worse than no Apply button, so the bar is:
    /// the finding names a range, the replacement has that many lines, and it
    /// does not smuggle in a fence of its own.
    static func suggestion(for finding: Finding) -> String? {
        guard let suggestion = finding.suggestion, let range = finding.lineRange else { return nil }
        let trimmed = suggestion.hasSuffix("\n") ? String(suggestion.dropLast()) : suggestion
        guard !trimmed.isEmpty, !trimmed.contains("```") else { return nil }
        guard trimmed.split(separator: "\n", omittingEmptySubsequences: false).count == range.count
        else { return nil }
        return trimmed
    }

    // MARK: - Bits

    /// "3 nits not raised." / "1 mild and 3 nits not raised." — or nothing at
    /// all when everything went out.
    static func omittedNote(_ omitted: [Finding]) -> String? {
        guard !omitted.isEmpty else { return nil }
        let parts = FindingTier.allCases.compactMap { tier -> String? in
            let count = omitted.filter { $0.tier == tier }.count
            guard count > 0 else { return nil }
            return "\(count) \(tier.rawValue)\(count == 1 ? "" : "s")"
        }
        let phrase: String
        switch parts.count {
        case 1: phrase = parts[0]
        case 2: phrase = "\(parts[0]) and \(parts[1])"
        default: phrase = parts.dropLast().joined(separator: ", ") + ", and " + parts[parts.count - 1]
        }
        return "_\(phrase) not raised._"
    }

    static func tally(_ findings: [Finding]) -> String {
        let parts = FindingTier.allCases
            .map { tier in (tier, findings.filter { $0.tier == tier }.count) }
            .filter { $0.1 > 0 }
            .map { "\($0.1) \($0.0.rawValue)" }
        guard !parts.isEmpty else { return "**Nothing to raise.**" }
        return "**\(parts.joined(separator: " · ")).** Each is commented inline below."
    }

    static func summaryLine(_ finding: Finding, inlined: Bool) -> String {
        var location = ""
        if let file = finding.file {
            location = finding.line.map { "`\(file):\($0)`" } ?? "`\(file)`"
            location += " — "
        }
        let note = inlined ? "" : " _(not in the diff; no inline comment)_"
        return "- \(location)\(finding.summary)\(note)"
    }

    /// One finding, for telling them apart without requiring `Hashable` on a
    /// type whose fields are all optional.
    static func identity(_ finding: Finding) -> String {
        "\(finding.tier.rawValue)|\(finding.file ?? "")|\(finding.line ?? -1)|\(finding.summary)"
    }

    static func truncated(_ body: String, limit: Int = bodyLimit) -> String {
        guard body.count > limit else { return body }
        return String(body.prefix(limit)) + "\n\n_Truncated._"
    }
}
