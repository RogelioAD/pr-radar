import XCTest
@testable import PRRadarCore

final class ClaudeFeedTests: XCTestCase {

    // MARK: - Finding the files at all

    /// The one that is wrong in the obvious implementation. Dots and
    /// underscores become dashes too, and a slug that only replaced separators
    /// would find no sessions at all on a Mac whose user name has a dot in it
    /// — which is exactly the machine this was written on.
    func testSlugReplacesDotsAndUnderscoresAsWellAsSeparators() {
        XCTAssertEqual(ClaudeFeed.slug(for: "/Users/rogelio.acosta/Desktop/pr-radar"),
                       "-Users-rogelio-acosta-Desktop-pr-radar")
        XCTAssertEqual(ClaudeFeed.slug(for: "/private/var/folders/rh/xgskttw51_v3n/T/pr-radar-884"),
                       "-private-var-folders-rh-xgskttw51-v3n-T-pr-radar-884")
    }

    // MARK: - Is it working, or is it my move?

    /// An assistant turn that ended with no tool call is the turn ending.
    func testAssistantWithNoToolIsYourMove() {
        XCTAssertEqual(ClaudeFeed.state(lastType: "assistant", lastTool: nil, idleFor: 1),
                       .waiting)
    }

    func testAssistantRunningAToolIsWorking() {
        XCTAssertEqual(ClaudeFeed.state(lastType: "assistant", lastTool: "Bash", idleFor: 1),
                       .working(tool: "Bash"))
    }

    /// A tool result just came back, so the model is about to speak. Mid-turn,
    /// and reported as thinking rather than as a tool nobody is running.
    func testToolResultIsThinking() {
        XCTAssertEqual(ClaudeFeed.state(lastType: "user", lastTool: nil, idleFor: 1),
                       .working(tool: nil))
        XCTAssertEqual(ClaudeFeed.state(lastType: "user", lastTool: nil, idleFor: 1).summary,
                       "thinking")
    }

    /// Generous on purpose: a build or a test suite is legitimately a tool call
    /// that runs for minutes, and calling that stalled would make the most
    /// interesting line on the screen the least trustworthy one.
    func testWorkIsOnlyStalledAfterAGenerousSilence() {
        XCTAssertEqual(
            ClaudeFeed.state(lastType: "assistant", lastTool: "Bash",
                             idleFor: ClaudeFeed.stalledAfter - 1),
            .working(tool: "Bash"))
        XCTAssertEqual(
            ClaudeFeed.state(lastType: "assistant", lastTool: "Bash",
                             idleFor: ClaudeFeed.stalledAfter),
            .stalled)
    }

    /// A session waiting on you is not stalled however long it waits. It is
    /// doing exactly what it should.
    func testWaitingNeverBecomesStalled() {
        XCTAssertEqual(ClaudeFeed.state(lastType: "assistant", lastTool: nil, idleFor: 86_400),
                       .waiting)
    }

    func testOnlyWorkCountsAsBusy() {
        XCTAssertTrue(ClaudeFeed.State.working(tool: "Read").isBusy)
        XCTAssertTrue(ClaudeFeed.State.stalled.isBusy)
        XCTAssertFalse(ClaudeFeed.State.waiting.isBusy)
    }

    // MARK: - Reading a transcript tail

    private func line(_ object: [String: Any]) -> String {
        String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private func assistantToolUse(id: String, name: String,
                                  input: [String: Any] = [:]) -> [String: Any] {
        ["type": "assistant", "cwd": "/Users/me/Desktop/proj", "gitBranch": "main",
         "message": ["content": [["type": "tool_use", "id": id, "name": name,
                                  "input": input]]]]
    }

    private func toolResult(id: String) -> [String: Any] {
        ["type": "user", "cwd": "/Users/me/Desktop/proj",
         "message": ["content": [["type": "tool_result", "tool_use_id": id]]]]
    }

    /// The tail starts mid-line by construction, so the first line is dropped.
    /// A half object is where the read began, not a parse failure.
    func testThePartialFirstLineIsDiscarded() {
        let tail = "e\":\"assistant\"}\n" + line(assistantToolUse(id: "1", name: "Bash"))
        let session = ClaudeFeed.session(fromTail: tail, idleFor: 2)
        XCTAssertEqual(session?.state, .working(tool: "Bash"))
    }

    func testProjectAndBranchComeOffTheTranscript() {
        let tail = "x\n" + line(assistantToolUse(id: "1", name: "Bash"))
        let session = ClaudeFeed.session(fromTail: tail, idleFor: 2)
        XCTAssertEqual(session?.project, "proj")
        XCTAssertEqual(session?.branch, "main")
    }

    /// The pairing the whole agent list rests on: a `Task` call whose result
    /// has not arrived is an agent still running.
    func testAnUnfinishedTaskIsARunningAgent() {
        let tail = [
            "x",
            line(assistantToolUse(id: "t1", name: "Task",
                                  input: ["subagent_type": "Explore",
                                          "description": "Map the events feed"])),
        ].joined(separator: "\n")
        let session = ClaudeFeed.session(fromTail: tail, idleFor: 2)
        XCTAssertEqual(session?.agents, [.init(kind: "Explore", task: "Map the events feed")])
    }

    /// **The spelling that actually occurs.** Every other fixture in this file
    /// says `Task`; a sweep of this machine's transcripts found 34 agent calls
    /// and every one of them was named `Agent`. Both are accepted because the
    /// name has changed before and the cost of accepting both is a single `||`
    /// — but the one real transcripts use needs a test of its own, or the
    /// suite is green about a format nothing writes.
    func testTheAgentSpellingIsRecognised() {
        let tail = [
            "x",
            line(assistantToolUse(id: "a1", name: "Agent",
                                  input: ["subagent_type": "Explore",
                                          "description": "Prose drift and spec audit"])),
        ].joined(separator: "\n")
        let session = ClaudeFeed.session(fromTail: tail, idleFor: 2)
        XCTAssertEqual(session?.agents,
                       [.init(kind: "Explore", task: "Prose drift and spec audit")])
        XCTAssertEqual(session?.state, .working(tool: "Agent"))
    }

    func testAFinishedTaskIsNotListed() {
        let tail = [
            "x",
            line(assistantToolUse(id: "t1", name: "Task",
                                  input: ["subagent_type": "Explore", "description": "done"])),
            line(toolResult(id: "t1")),
        ].joined(separator: "\n")
        XCTAssertEqual(ClaudeFeed.session(fromTail: tail, idleFor: 2)?.agents, [])
    }

    func testSeveralAgentsAreListedInLaunchOrder() {
        let tail = [
            "x",
            line(assistantToolUse(id: "a", name: "Task",
                                  input: ["subagent_type": "Explore", "description": "first"])),
            line(assistantToolUse(id: "b", name: "Task",
                                  input: ["subagent_type": "Plan", "description": "second"])),
        ].joined(separator: "\n")
        XCTAssertEqual(ClaudeFeed.session(fromTail: tail, idleFor: 2)?.agents.map(\.task),
                       ["first", "second"])
    }

    /// **The bug this guard exists for, caught in production.** The transcript
    /// carries bookkeeping between turns — `attachment` lines, `system` lines,
    /// snapshots — and a read that lands on one of those must not conclude the
    /// turn is over.
    ///
    /// Nasty shape: intermittent by nature, since it depends only on when the
    /// read happens to land, and it always errs toward *nothing is happening*
    /// — the worst direction to be wrong on a screen whose whole job is
    /// answering "is my work still running".
    func testBookkeepingLinesDoNotEndTheTurn() {
        for noise in ["attachment", "system", "file-history-snapshot"] {
            let tail = [
                "x",
                line(assistantToolUse(id: "1", name: "Bash")),
                line(["type": noise, "cwd": "/Users/me/Desktop/proj"]),
            ].joined(separator: "\n")
            XCTAssertEqual(ClaudeFeed.session(fromTail: tail, idleFor: 2)?.state,
                           .working(tool: "Bash"),
                           "a trailing \(noise) line ended the turn")
        }
    }

    /// And the same for an agent still running: an attachment arriving after
    /// the `Task` call must not drop it off the list.
    func testBookkeepingLinesDoNotDropRunningAgents() {
        let tail = [
            "x",
            line(assistantToolUse(id: "t1", name: "Task",
                                  input: ["subagent_type": "Explore", "description": "looking"])),
            line(["type": "attachment", "cwd": "/Users/me/Desktop/proj"]),
        ].joined(separator: "\n")
        let session = ClaudeFeed.session(fromTail: tail, idleFor: 2)
        XCTAssertEqual(session?.agents.count, 1)
        XCTAssertEqual(session?.state, .working(tool: "Task"))
    }

    /// An agent's own transcript must not decide the session's state.    /// An agent's own transcript must not decide the session's state. Its last
    /// word would otherwise read as the session going quiet, when the session
    /// is in fact waiting on that very agent.
    func testASidechainLineDoesNotEndTheSessionsTurn() {
        var sidechain = assistantToolUse(id: "s", name: "Read")
        sidechain["isSidechain"] = true
        let tail = [
            "x",
            line(assistantToolUse(id: "t1", name: "Task",
                                  input: ["subagent_type": "Explore", "description": "looking"])),
            line(sidechain),
        ].joined(separator: "\n")
        let session = ClaudeFeed.session(fromTail: tail, idleFor: 2)
        XCTAssertEqual(session?.state, .working(tool: "Task"))
        XCTAssertEqual(session?.agents.count, 1)
    }

    /// Somebody else's file format. A renamed field or a malformed line has to
    /// cost a line, never the feature.
    func testUnparseableLinesAreSkippedRatherThanFatal() {
        let tail = ["x", "{not json", "", line(assistantToolUse(id: "1", name: "Bash"))]
            .joined(separator: "\n")
        XCTAssertEqual(ClaudeFeed.session(fromTail: tail, idleFor: 2)?.state,
                       .working(tool: "Bash"))
    }

    func testATailWithNothingUsableIsNoSession() {
        XCTAssertNil(ClaudeFeed.session(fromTail: "x\n{not json\n", idleFor: 2))
        XCTAssertNil(ClaudeFeed.session(fromTail: "", idleFor: 2))
    }

    /// PR Radar's own reviews run in throwaway worktrees. Flagged here so the
    /// digest can file them under the heading that already names them by pull
    /// request, instead of listing them twice.
    func testAReviewWorktreeIsRecognised() {
        var entry = assistantToolUse(id: "1", name: "Bash")
        entry["cwd"] = "/private/var/folders/rh/x/T/pr-radar-884-A9C20935"
        let session = ClaudeFeed.session(fromTail: "x\n" + line(entry), idleFor: 2)
        XCTAssertEqual(session?.isReviewWorktree, true)
    }

    // MARK: - Ordering and the digest

    private func session(_ project: String, _ state: ClaudeFeed.State,
                         idle: TimeInterval = 1, agents: [ClaudeFeed.Agent] = [],
                         review: Bool = false) -> ClaudeFeed.Session {
        .init(project: project, branch: nil, state: state, idleFor: idle,
              agents: agents, isReviewWorktree: review)
    }

    /// Busy outranks idle however recently the idle one spoke. The question
    /// this screen answers is whether work is still going.
    func testBusySessionsSortAboveIdleOnes() {
        let ordered = ClaudeFeed.ordered([
            session("idle", .waiting, idle: 1),
            session("busy", .working(tool: "Bash"), idle: 200),
        ])
        XCTAssertEqual(ordered.map(\.project), ["busy", "idle"])
    }

    func testReviewWorktreesAreNotListedUnderClaude() {
        let digest = ClaudeFeed.digest([
            session("pr-radar-884-abc", .working(tool: "Bash"), review: true),
        ])
        XCTAssertEqual(digest.headline, "Nothing running")
        XCTAssertTrue(digest.lines.isEmpty)
    }

    /// Six terminals at a prompt are one fact, not six lines — and the lines
    /// they would take are the ones the working sessions need.
    func testIdleSessionsCollapseToACountOnceSomethingIsWorking() {
        let digest = ClaudeFeed.digest([
            session("a", .working(tool: "Bash")),
            session("b", .waiting), session("c", .waiting), session("d", .waiting),
        ])
        XCTAssertEqual(digest.headline, "1 session working")
        XCTAssertEqual(digest.lines, ["a · running Bash", "3 waiting for you"])
        XCTAssertTrue(digest.isWorking)
    }

    /// With nothing working the idle ones are all there is to say, so they get
    /// named rather than counted.
    func testIdleSessionsAreNamedWhenNothingIsWorking() {
        let digest = ClaudeFeed.digest([session("a", .waiting), session("b", .waiting)])
        XCTAssertEqual(digest.headline, "2 waiting for you")
        XCTAssertEqual(digest.lines, ["a · waiting for you", "b · waiting for you"])
        XCTAssertFalse(digest.isWorking)
    }

    func testAgentsAreIndentedUnderTheirSession() {
        let digest = ClaudeFeed.digest([
            session("a", .working(tool: "Task"),
                    agents: [.init(kind: "Explore", task: "Map the feed")]),
        ])
        XCTAssertEqual(digest.lines.first, "a · running Task")
        XCTAssertEqual(digest.lines.last, "    ↳ Explore · Map the feed")
    }

    /// Ten agent lines, then a number. Past that a list has stopped being a
    /// glance and become a page, and the question that far down has gone back
    /// to *how many* from *which*.
    func testBeyondTenAgentsTheRestAreCounted() {
        let agents = (1...14).map { ClaudeFeed.Agent(kind: "Explore", task: "task \($0)") }
        let digest = ClaudeFeed.digest([session("a", .working(tool: "Task"), agents: agents)])
        let listed = digest.lines.filter { $0.contains("↳") }
        XCTAssertEqual(listed.count, ClaudeFeed.maxAgents)
        XCTAssertEqual(digest.lines.last, "+4 more agents")
    }

    func testExactlyTenAgentsNeedsNoOverflowLine() {
        let agents = (1...10).map { ClaudeFeed.Agent(kind: "Explore", task: "task \($0)") }
        let digest = ClaudeFeed.digest([session("a", .working(tool: "Task"), agents: agents)])
        XCTAssertEqual(digest.lines.filter { $0.contains("↳") }.count, 10)
        XCTAssertFalse(digest.lines.contains { $0.contains("more agent") })
    }

    func testOneLeftOverAgentIsNotPluralised() {
        let agents = (1...11).map { ClaudeFeed.Agent(kind: "Explore", task: "task \($0)") }
        let digest = ClaudeFeed.digest([session("a", .working(tool: "Task"), agents: agents)])
        XCTAssertEqual(digest.lines.last, "+1 more agent")
    }

    /// The budget spans sessions rather than resetting per session, and the
    /// overflow counts agents on sessions too far down to be named at all —
    /// otherwise the number is true about the part of the screen that fitted
    /// rather than about the machine.
    func testTheAgentBudgetIsSharedAcrossSessions() {
        let six = (1...6).map { ClaudeFeed.Agent(kind: "Explore", task: "t\($0)") }
        let digest = ClaudeFeed.digest([
            session("a", .working(tool: "Task"), agents: six),
            session("b", .working(tool: "Task"), agents: six),
        ])
        XCTAssertEqual(digest.lines.filter { $0.contains("↳") }.count, ClaudeFeed.maxAgents)
        XCTAssertEqual(digest.lines.last, "+2 more agents")
    }

    /// A line that wraps is a line of unpredictable height, and everything
    /// below it moves when it does. One line per agent, always.
    func testALongTaskIsClippedToOneLine() {
        let long = String(repeating: "wordy ", count: 20)
        let digest = ClaudeFeed.digest([
            session("a", .working(tool: "Task"),
                    agents: [.init(kind: "Explore", task: long)]),
        ])
        let line = digest.lines.first { $0.contains("↳") }
        XCTAssertNotNil(line)
        XCTAssertTrue(line!.hasSuffix("…"))
        XCTAssertLessThanOrEqual(line!.count, 6 + "Explore".count + 3 + ClaudeFeed.maxTask)
    }

    func testBeyondFourWorkingSessionsTheRestAreCounted() {
        let many = (1...7).map { session("s\($0)", .working(tool: "Bash")) }
        let digest = ClaudeFeed.digest(many)
        XCTAssertEqual(digest.headline, "7 sessions working")
        XCTAssertEqual(digest.lines.last, "+3 more working")
    }

    func testNothingAtAllSaysSo() {
        let digest = ClaudeFeed.digest([])
        XCTAssertEqual(digest.headline, "Nothing running")
        XCTAssertTrue(digest.lines.isEmpty)
        XCTAssertFalse(digest.isWorking)
    }

    // MARK: - The label

    func testBranchIsShownButTruncatedWhenGenerated() {
        let long = String(repeating: "x", count: 60)
        let labelled = ClaudeFeed.label(
            .init(project: "proj", branch: long, state: .waiting,
                  idleFor: 1, agents: [], isReviewWorktree: false))
        XCTAssertTrue(labelled.contains("…"))
        XCTAssertLessThan(labelled.count, 60)
    }

    /// A detached HEAD is not a branch name worth the width.
    func testDetachedHeadIsNotShownAsABranch() {
        let labelled = ClaudeFeed.label(
            .init(project: "proj", branch: "HEAD", state: .waiting,
                  idleFor: 1, agents: [], isReviewWorktree: false))
        XCTAssertEqual(labelled, "proj · waiting for you")
    }
}
