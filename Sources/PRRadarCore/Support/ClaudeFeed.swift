import Foundation

/// What Claude Code is doing on this Mac, read off its own transcripts.
///
/// The away screen's second half. The first says what *PR Radar* is reviewing,
/// which it knows because it started it; this says what **you** have running,
/// which it can only find out by looking — so everything here is observation of
/// somebody else's files, and is written to fail quietly when they change.
///
/// **Read-only, and tail-only.** Claude Code appends one JSON object per line to
/// `~/.claude/projects/<slug>/<session>.jsonl`. Nothing here writes, locks or
/// truncates; a line that will not parse is skipped rather than reported,
/// because a feed that breaks when a field is renamed is worse than one that
/// quietly shows less. The last stretch of each file is enough for every
/// question asked below, and reading whole transcripts — some are tens of
/// megabytes — to render a status line would be absurd.
///
/// **It cannot see inside a session.** A subagent is not an operating-system
/// process, so none of this comes from the process table. What it reads is the
/// pairing Claude Code already writes down: a `Task` tool call has an id, its
/// result carries the same id, and a call with no result yet is an agent still
/// running. That is exact while the format holds, and silent when it does not.
public enum ClaudeFeed {

    // MARK: - What a session is doing

    public enum State: Equatable, Sendable {
        /// Mid-turn. `tool` is what it is running, nil while it is thinking.
        case working(tool: String?)
        /// The turn ended. It is your move.
        case waiting
        /// Mid-turn, but the transcript has not moved in a long time. Usually a
        /// session that was interrupted or whose terminal went away.
        case stalled

        /// Said the way you would say it, because this is read from a doorway.
        public var summary: String {
            switch self {
            case .working(let tool): return tool.map { "running \($0)" } ?? "thinking"
            case .waiting: return "waiting for you"
            case .stalled: return "stalled"
            }
        }

        /// Whether this counts as the Mac being busy. `waiting` does not: a
        /// session holding the turn is not work in progress, and counting it
        /// would light the screen up for six terminals that are all idle.
        public var isBusy: Bool {
            switch self {
            case .working, .stalled: return true
            case .waiting: return false
            }
        }
    }

    public struct Agent: Equatable, Sendable {
        /// The `subagent_type`: `Explore`, `general-purpose`, a named one.
        public let kind: String
        /// The call's own one-line `description`.
        public let task: String

        public init(kind: String, task: String) {
            self.kind = kind
            self.task = task
        }
    }

    public struct Session: Equatable, Sendable {
        /// The working directory's last component — `pr-radar`, `sticky-rsvp`.
        /// The whole path is a mouthful and the leaf is what you call it.
        public let project: String
        public let branch: String?
        public let state: State
        public let idleFor: TimeInterval
        public let agents: [Agent]
        /// A review PR Radar started in a throwaway worktree, rather than
        /// something you are running. Kept rather than dropped so the caller
        /// can file it under the right heading instead of double-counting it.
        public let isReviewWorktree: Bool

        public init(project: String, branch: String?, state: State,
                    idleFor: TimeInterval, agents: [Agent],
                    isReviewWorktree: Bool) {
            self.project = project
            self.branch = branch
            self.state = state
            self.idleFor = idleFor
            self.agents = agents
            self.isReviewWorktree = isReviewWorktree
        }
    }

    // MARK: - Rules

    /// How long a mid-turn session may sit still before it is called stalled.
    ///
    /// Five minutes, which is generous on purpose. A single tool call can
    /// legitimately run for minutes — a build, a long test suite, a review —
    /// and calling that stalled would make the most interesting line on the
    /// screen the least trustworthy one.
    public static let stalledAfter: TimeInterval = 300

    /// How far back a transcript may have been touched and still be shown.
    ///
    /// Thirty minutes. Past that a session is almost always a terminal somebody
    /// closed, and a live feed listing yesterday's work is not a live feed.
    public static let window: TimeInterval = 1_800

    /// How many sessions are named before the rest become a count.
    public static let maxNamed = 4

    /// The directory name Claude Code gives a working directory.
    ///
    /// Every separator *and* every dot and underscore becomes a dash, which is
    /// why this is a rule with a test rather than one `replacingOccurrences`
    /// written inline: `/Users/rogelio.acosta/Desktop/pr-radar` has all three
    /// and the obvious implementation gets it wrong in a way that silently
    /// finds no sessions at all.
    public static func slug(for path: String) -> String {
        String(path.map { "/._".contains($0) ? "-" : $0 })
    }

    public static func state(lastType: String?,
                             lastTool: String?,
                             idleFor: TimeInterval,
                             stalledAfter: TimeInterval = ClaudeFeed.stalledAfter) -> State {
        // An assistant turn that ended with no tool call is the turn ending:
        // the model said its piece and it is your move. Every other shape is
        // mid-turn — an assistant message calling a tool, or a user message
        // carrying the result back.
        guard let lastType else { return .waiting }
        let working: Bool
        switch lastType {
        case "assistant": working = lastTool != nil
        case "user": working = true
        default: working = false
        }
        guard working else { return .waiting }
        return idleFor >= stalledAfter ? .stalled : .working(tool: lastTool)
    }

    /// Sessions in the order they should be read.
    ///
    /// Busy first, then by what moved most recently. The question this screen
    /// answers is *is my work still going*, so anything that is going outranks
    /// everything that is not, however recently the idle one spoke.
    public static func ordered(_ sessions: [Session]) -> [Session] {
        sessions.enumerated().sorted { a, b in
            let (x, y) = (a.element, b.element)
            if x.state.isBusy != y.state.isBusy { return x.state.isBusy }
            if x.idleFor != y.idleFor { return x.idleFor < y.idleFor }
            // Stable past that, so a redraw does not reshuffle two sessions
            // that are equally idle.
            return a.offset < b.offset
        }.map(\.element)
    }

    // MARK: - What the screen shows

    /// The Claude half of the away screen, assembled.
    public struct Digest: Equatable, Sendable {
        public let headline: String
        public let lines: [String]
        public let isWorking: Bool
    }

    /// A branch name past this is cut. Long ones are generated and the
    /// informative part is at the front.
    static let maxBranch = 24

    /// How many agent lines are listed before the rest become a count.
    ///
    /// Ten, which is the point where a list stops being a glance and starts
    /// being a page. Past it the honest thing is a number: you cannot read
    /// twenty descriptions from a doorway, and the question that far down the
    /// screen has stopped being *which agent* and gone back to *how many*.
    public static let maxAgents = 10

    /// An agent's description past this is cut.
    ///
    /// Not cosmetic. A line that wraps is a line of unpredictable height, and
    /// every line below it moves when it does — which is the whole thing this
    /// screen is laid out to avoid. One line per agent, always.
    static let maxTask = 34

    /// Sessions turned into the lines you read from a doorway.
    ///
    /// Review worktrees are dropped here rather than filtered by the caller:
    /// they are PR Radar's own reviews, they are already named under PR
    /// Radar's heading with their pull request numbers, and listing them again
    /// as anonymous temp directories would make the busiest moment the most
    /// confusing one.
    ///
    /// Idle sessions collapse into a single count once anything is working.
    /// Six terminals sitting at a prompt are one fact, not six lines, and the
    /// lines they would take are the ones the working sessions need.
    public static func digest(_ sessions: [Session]) -> Digest {
        let mine = ordered(sessions.filter { !$0.isReviewWorktree })
        let busy = mine.filter { $0.state.isBusy }
        let idle = mine.count - busy.count

        // Counted across every session, including ones too far down to be
        // named, so the overflow line is true about the machine rather than
        // about the part of it that fitted.
        let totalAgents = mine.reduce(0) { $0 + $1.agents.count }
        var shownAgents = 0

        var lines: [String] = []
        for session in busy.prefix(maxNamed) {
            lines.append(label(session))
            // Indented and marked, because an agent belongs to the session
            // above it and a flat list would read as more sessions.
            for agent in session.agents {
                guard shownAgents < maxAgents else { break }
                lines.append("    \u{21B3} \(agent.kind) \u{00B7} \(clip(agent.task, to: maxTask))")
                shownAgents += 1
            }
        }
        if busy.count > maxNamed { lines.append("+\(busy.count - maxNamed) more working") }
        if totalAgents > shownAgents {
            let rest = totalAgents - shownAgents
            lines.append("+\(rest) more agent\(rest == 1 ? "" : "s")")
        }
        if idle > 0 && !busy.isEmpty { lines.append("\(idle) waiting for you") }
        if busy.isEmpty {
            // Nothing is working, so the idle ones are all there is to say and
            // they get named rather than counted.
            for session in mine.prefix(maxNamed) { lines.append(label(session)) }
            if mine.count > maxNamed { lines.append("+\(mine.count - maxNamed) more") }
        }

        let headline: String
        if !busy.isEmpty {
            headline = "\(busy.count) session\(busy.count == 1 ? "" : "s") working"
        } else if !mine.isEmpty {
            headline = "\(mine.count) waiting for you"
        } else {
            headline = "Nothing running"
        }

        return Digest(headline: headline, lines: lines, isWorking: !busy.isEmpty)
    }

    static func label(_ session: Session) -> String {
        var name = session.project
        if let branch = session.branch, !branch.isEmpty, branch != "HEAD" {
            name += " (\(clip(branch, to: maxBranch)))"
        }
        return "\(name) \u{00B7} \(session.state.summary)"
    }

    /// Cut to a width, with an ellipsis standing in for what was cut.
    ///
    /// The front is kept because that is where the informative part of both a
    /// generated branch name and a one-line task description lives.
    static func clip(_ text: String, to width: Int) -> String {
        guard text.count > width else { return text }
        return text.prefix(width - 1) + "\u{2026}"
    }

    // MARK: - Reading one transcript

    /// Everything the feed needs from the tail of one session file.
    ///
    /// Takes text rather than a path so the parsing can be tested without
    /// standing up a directory of fixtures — and so the one genuinely fragile
    /// part of this feature, its dependence on somebody else's file format, is
    /// the part with tests around it.
    ///
    /// `tail` is expected to begin mid-line. The first line is dropped for that
    /// reason; a half object is not an error, it is where the read started.
    public static func session(fromTail tail: String,
                               cwd fallbackCwd: String? = nil,
                               idleFor: TimeInterval) -> Session? {
        var lines = tail.split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        if lines.count > 1 { lines.removeFirst() }

        var cwd = fallbackCwd
        var branch: String?
        var lastType: String?
        var lastTool: String?
        var launched: [(id: String, agent: Agent)] = []
        var finished = Set<String>()
        var sawAny = false

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let entry = object as? [String: Any] else { continue }

            // A sidechain line is the *agent's* own transcript. It is not the
            // session's turn and must not decide the session's state — an
            // agent's last word would otherwise read as the session going
            // quiet while it is in fact waiting on that very agent.
            if entry["isSidechain"] as? Bool == true { continue }
            sawAny = true

            cwd = entry["cwd"] as? String ?? cwd
            branch = entry["gitBranch"] as? String ?? branch

            // Only a turn in the conversation decides whose move it is.
            //
            // The transcript also carries bookkeeping between turns —
            // `attachment` lines, `system` lines, snapshots — and letting one
            // of those set the state is a bug with a nasty shape: a session
            // genuinely mid-tool reads as *waiting for you* whenever the read
            // lands after an attachment rather than after the tool call. It is
            // intermittent by nature, it always errs toward saying nothing is
            // happening, and on a screen whose entire job is answering "is my
            // work still running" that is the worst direction to be wrong in.
            let type = entry["type"] as? String
            guard type == "assistant" || type == "user" else { continue }
            lastType = type

            let content = (entry["message"] as? [String: Any])?["content"]
            guard let blocks = content as? [[String: Any]] else {
                // A plain-string content block is an ordinary message with no
                // tool call in it, which still ends the turn.
                if type == "assistant" { lastTool = nil }
                continue
            }

            var toolInThisMessage: String?
            for block in blocks {
                switch block["type"] as? String {
                case "tool_use":
                    let name = block["name"] as? String
                    toolInThisMessage = name ?? toolInThisMessage
                    guard name == "Task" || name == "Agent",
                          let id = block["id"] as? String else { continue }
                    let input = block["input"] as? [String: Any] ?? [:]
                    launched.append((id, Agent(
                        kind: input["subagent_type"] as? String ?? "agent",
                        task: input["description"] as? String ?? "working")))
                case "tool_result":
                    if let id = block["tool_use_id"] as? String { finished.insert(id) }
                default:
                    continue
                }
            }
            if type == "assistant" { lastTool = toolInThisMessage }
        }

        guard sawAny, let cwd else { return nil }

        return Session(
            project: (cwd as NSString).lastPathComponent,
            branch: branch,
            state: state(lastType: lastType, lastTool: lastTool, idleFor: idleFor),
            idleFor: idleFor,
            // Launch order, which is the order they were explained to you.
            agents: launched.filter { !finished.contains($0.id) }.map(\.agent),
            isReviewWorktree: Workspace.isWorktree(path: cwd))
    }
}
