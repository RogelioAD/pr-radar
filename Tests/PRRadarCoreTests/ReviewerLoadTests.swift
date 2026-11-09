import XCTest
@testable import PRRadarCore

/// Who is sitting on your work, which repos the drawer is narrowed to, and
/// the commands the branch chips hand you.
final class ReviewerLoadTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3_600) }

    // MARK: - Reviewer load

    func pr(_ number: Int, awaiting: [String], askedAt: [String: Date]) -> MyPullRequest {
        var item = MyPullRequest(
            repo: "acme/repo", number: number, title: "t",
            url: URL(string: "https://github.com/acme/repo/pull/\(number)")!,
            isDraft: false, createdAt: now, updatedAt: now,
            headRefName: "h\(number)", baseRefName: "main",
            reviewDecision: .none, mergeBlocker: .blocked, approvals: [],
            awaitingReviewers: awaiting, unresolvedThreadCount: 0,
            totalThreadCount: 0, checks: .empty,
            additions: 1, deletions: 0, changedFiles: 1)
        item.requestedAt = askedAt
        return item
    }

    /// A reviewer with exactly one of yours is already completely described by
    /// that row's own chip. Repeating it above the list would be the drawer
    /// saying the same thing twice in two sizes.
    func testOnlyReviewersHoldingMoreThanOne() {
        let loads = ReviewerLoad.build(from: [
            pr(1, awaiting: ["alice"], askedAt: ["alice": ago(10)]),
            pr(2, awaiting: ["alice"], askedAt: ["alice": ago(20)]),
            pr(3, awaiting: ["bob"], askedAt: ["bob": ago(10)]),
        ])
        XCTAssertEqual(loads.map(\.reviewer), ["alice"])
        XCTAssertEqual(loads.first?.count, 2)
    }

    /// The oldest of *that reviewer's* asks, not the row's headline — the row
    /// reports whoever has had it longest, and that is somebody else's clock.
    func testTakesTheReviewersOwnOldestAsk() throws {
        let loads = ReviewerLoad.build(from: [
            pr(1, awaiting: ["alice", "bob"],
               askedAt: ["alice": ago(10), "bob": ago(90)]),
            pr(2, awaiting: ["alice"], askedAt: ["alice": ago(50)]),
        ])
        let alice = try XCTUnwrap(loads.first { $0.reviewer == "alice" })
        XCTAssertEqual(alice.since, ago(50))
    }

    /// Two pull requests sat with somebody for a week is a worse state of
    /// affairs than four they were handed this morning.
    func testSortedByHowLongNotHowMany() {
        let loads = ReviewerLoad.build(from: [
            pr(1, awaiting: ["many"], askedAt: ["many": ago(1)]),
            pr(2, awaiting: ["many"], askedAt: ["many": ago(1)]),
            pr(3, awaiting: ["many"], askedAt: ["many": ago(1)]),
            pr(4, awaiting: ["old"], askedAt: ["old": ago(200)]),
            pr(5, awaiting: ["old"], askedAt: ["old": ago(200)]),
        ])
        XCTAssertEqual(loads.map(\.reviewer), ["old", "many"])
    }

    /// Not knowing is not a small number — the same rule an unmeasured row
    /// follows on the Reviews tab.
    func testUnknownAskTimesSortLast() {
        let loads = ReviewerLoad.build(from: [
            pr(1, awaiting: ["unknown"], askedAt: [:]),
            pr(2, awaiting: ["unknown"], askedAt: [:]),
            pr(3, awaiting: ["known"], askedAt: ["known": ago(5)]),
            pr(4, awaiting: ["known"], askedAt: ["known": ago(5)]),
        ])
        XCTAssertEqual(loads.map(\.reviewer), ["known", "unknown"])
    }

    func testTheLabelCounts() {
        let load = ReviewerLoad(reviewer: "alice", count: 4, since: ago(96))
        XCTAssertEqual(load.label, "alice has 4 of yours")
        XCTAssertEqual(load.ageLabel(now: now), "oldest 4d")
        XCTAssertEqual(load.health(now: now), Staleness.stale.health)
    }

    func testNobodyWaitingIsNoBand() {
        XCTAssertTrue(ReviewerLoad.build(from: [pr(1, awaiting: [], askedAt: [:])]).isEmpty)
    }

    // MARK: - Repo scope, now a set

    struct Row { let repo: String }

    func testAnEmptyScopeIsEveryRepo() {
        let rows = [Row(repo: "a/one"), Row(repo: "a/two")]
        XCTAssertEqual(RepoScope.apply(Set<String>(), to: rows, repoOf: \.repo).count, 2)
    }

    func testSeveralReposAreAllKept() {
        let rows = [Row(repo: "a/one"), Row(repo: "a/two"), Row(repo: "a/three")]
        let kept = RepoScope.apply(["a/one", "a/three"], to: rows, repoOf: \.repo)
        XCTAssertEqual(kept.map(\.repo), ["a/one", "a/three"])
    }

    func testTheLabelNamesOneAndCountsSeveral() {
        XCTAssertEqual(RepoScope.label([]), "All repos")
        XCTAssertEqual(RepoScope.label(["acme/widgets-web"]), "widgets-web")
        XCTAssertEqual(RepoScope.label(["a/one", "a/two"]), "2 repos")
    }

    /// Name by name. With three picked and one finished, the other two are
    /// still exactly what was asked for.
    func testValidationDropsOnlyTheDeadNames() {
        XCTAssertEqual(RepoScope.validated(["a/one", "a/gone", "a/two"],
                                           against: ["a/one", "a/two", "a/three"]),
                       ["a/one", "a/two"])
    }

    // MARK: - The branch commands

    func testRebaseCommand() {
        XCTAssertEqual(BranchCommand.rebase(onto: "main"),
                       "git fetch origin && git rebase origin/main")
    }

    func testResolveCommandGetsYouOntoTheBranchFirst() {
        XCTAssertEqual(
            BranchCommand.resolve(head: "feat/a", base: "feat/sprint/21"),
            "git switch feat/a && git fetch origin && git rebase origin/feat/sprint/21")
    }
}
