import XCTest
@testable import PRRadarCore

final class ClaudeInvocationTests: XCTestCase {

    let request = AutoReviewRequest(
        skill: "/code-review",
        repo: "acme/repo",
        number: 12,
        url: URL(string: "https://github.com/acme/repo/pull/12")!)

    private func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    // MARK: - The prompt

    /// Load-bearing. Anything else in the prompt and the text stops reading as
    /// a command, so the skill never dispatches and a general-purpose model
    /// answers the question instead — which looks like a bad review rather than
    /// like a missing one.
    func testThePromptIsTheSlashCommandAndItsArgumentAndNothingElse() {
        XCTAssertEqual(ClaudeInvocation.prompt(for: request),
                       "/code-review https://github.com/acme/repo/pull/12")
    }

    func testTheFramingGoesInTheSystemPromptRatherThanThePrompt() {
        let arguments = ClaudeInvocation.arguments(for: request)
        XCTAssertEqual(value(after: "-p", in: arguments),
                       "/code-review https://github.com/acme/repo/pull/12")
        let framing = value(after: "--append-system-prompt", in: arguments)
        XCTAssertEqual(framing, ClaudeInvocation.framing(for: request))
        XCTAssertTrue(framing?.contains("Ask no questions") == true)
    }

    /// The framing has to name the PR, because a skill that would have asked
    /// which one now has to be told.
    func testTheFramingNamesTheTargetPullRequest() {
        let framing = ClaudeInvocation.framing(for: request)
        XCTAssertTrue(framing.contains("acme/repo#12"))
        XCTAssertTrue(framing.contains("https://github.com/acme/repo/pull/12"))
    }

    /// The review is posted under the user's own name, so a finding with
    /// nothing to do about it is a complaint.
    func testTheFramingAsksForARecommendationOnEveryFinding() {
        XCTAssertTrue(ClaudeInvocation.framing(for: request).contains("recommendation"))
        XCTAssertTrue(ClaudeInvocation.framing(for: request).contains("suggestion"))
    }

    /// The PR's own text reaches the model, so the framing has to say what that
    /// text is: data to review, not instructions to follow.
    func testTheFramingTreatsThePullRequestAsUntrusted() {
        XCTAssertTrue(ClaudeInvocation.framing(for: request).contains("untrusted"))
    }

    // MARK: - Tools

    /// Denied outright rather than merely discouraged: a session that cannot
    /// call `Edit` cannot be talked into calling it by something in the diff.
    func testEveryWritingToolIsDisallowed() {
        for tool in ["Edit", "Write", "NotebookEdit"] {
            XCTAssertTrue(ClaudeInvocation.disallowedTools.contains(tool), tool)
        }
    }

    /// There is nobody to answer, so a skill that asks would hang to the
    /// timeout. Denying the tool turns that into a fast, legible failure.
    func testAskingQuestionsIsDisallowedBecauseNobodyIsThere() {
        XCTAssertTrue(ClaudeInvocation.disallowedTools.contains("AskUserQuestion"))
    }

    /// PR Radar posts the review itself, as the user. A skill that posts one
    /// too would double it, and PR Radar would not know the node id of either.
    func testTheSkillCannotPostOrApproveOnItsOwn() {
        for tool in ["Bash(gh pr review:*)", "Bash(gh pr comment:*)", "Bash(gh pr merge:*)"] {
            XCTAssertTrue(ClaudeInvocation.disallowedTools.contains(tool), tool)
        }
    }

    func testTheSkillCanStillReadTheCodeAndThePullRequest() {
        for tool in ["Read", "Grep", "Bash(gh pr diff:*)", "Bash(git diff:*)"] {
            XCTAssertTrue(ClaudeInvocation.allowedTools.contains(tool), tool)
        }
    }

    func testNoToolIsBothAllowedAndDisallowed() {
        let overlap = Set(ClaudeInvocation.allowedTools)
            .intersection(ClaudeInvocation.disallowedTools)
        XCTAssertTrue(overlap.isEmpty, "\(overlap)")
    }

    // MARK: - The schema

    func testTheSchemaIsValidJSONAndNamesAllThreeTiers() throws {
        let object = try JSONSerialization.jsonObject(
            with: Data(ClaudeInvocation.schema.utf8)) as? [String: Any]
        XCTAssertNotNil(object)
        for tier in FindingTier.allCases {
            XCTAssertTrue(ClaudeInvocation.schema.contains("\"\(tier.rawValue)\""), tier.rawValue)
        }
    }

    func testTheSchemaRequiresARecommendation() {
        XCTAssertTrue(ClaudeInvocation.schema.contains(
            #""required":["tier","summary","recommendation"]"#))
    }

    // MARK: - Optional flags

    func testTheModelAndBudgetAreOmittedWhenUnset() {
        let arguments = ClaudeInvocation.arguments(for: request)
        XCTAssertFalse(arguments.contains("--model"))
        XCTAssertFalse(arguments.contains("--max-budget-usd"))
    }

    func testTheModelAndBudgetArePassedWhenSet() {
        let configured = AutoReviewRequest(
            skill: "/code-review", repo: "acme/repo", number: 12,
            url: request.url, model: "sonnet", budgetUSD: 1.5)
        let arguments = ClaudeInvocation.arguments(for: configured)
        XCTAssertEqual(value(after: "--model", in: arguments), "sonnet")
        XCTAssertEqual(value(after: "--max-budget-usd", in: arguments), "1.50")
    }

    /// Zero is "no ceiling", which somebody has to choose. Passing it through
    /// would cap every review at nothing and read as the feature being broken.
    func testAZeroBudgetMeansNoCeilingRatherThanNoSpend() {
        let free = AutoReviewRequest(skill: "/code-review", repo: "acme/repo",
                                     number: 12, url: request.url, budgetUSD: 0)
        XCTAssertFalse(ClaudeInvocation.arguments(for: free).contains("--max-budget-usd"))
    }

    // MARK: - Shape of the command line

    func testTheOutputIsAskedForAsSchemaValidatedJSON() {
        let arguments = ClaudeInvocation.arguments(for: request)
        XCTAssertEqual(value(after: "--output-format", in: arguments), "json")
        XCTAssertEqual(value(after: "--json-schema", in: arguments), ClaudeInvocation.schema)
    }

    /// A review is a throwaway: nothing should resume it, and nothing should
    /// block it on a permission prompt no one can answer.
    func testTheSessionNeitherPersistsNorPrompts() {
        let arguments = ClaudeInvocation.arguments(for: request)
        XCTAssertTrue(arguments.contains("--no-session-persistence"))
        XCTAssertEqual(value(after: "--permission-mode", in: arguments), "dontAsk")
    }

    /// Each argument is its own argv element, which is the property that makes
    /// shell metacharacters meaningless here — there is no shell to read them.
    func testTheSkillAndItsURLTravelAsSingleArgvElements() {
        let odd = AutoReviewRequest(
            skill: "/code-review; rm -rf /", repo: "acme/repo", number: 1,
            url: request.url)
        let arguments = ClaudeInvocation.arguments(for: odd)
        XCTAssertEqual(arguments.filter { $0.contains("rm -rf") }.count, 1)
    }
}
