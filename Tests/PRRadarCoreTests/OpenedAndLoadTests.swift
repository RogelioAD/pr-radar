import XCTest
@testable import PRRadarCore

/// Having started something, and who is sitting on your work.
final class OpenedAndLoadTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3_600) }

    // MARK: - Opened

    func testRecordsAnOpen() {
        var opened = Opened()
        opened.open("k", at: ago(2))
        XCTAssertTrue(opened.wasOpened("k"))
        XCTAssertEqual(opened.openedAt("k"), ago(2))
        XCTAssertEqual(opened.label(for: "k", now: now), "opened 2h ago")
    }

    /// Opening it a fourth time is not a fresh start. The interesting number
    /// is how long this has been going on, and keeping the latest would reset
    /// the clock exactly when it has most to say.
    func testKeepsTheEarliestOpen() {
        var opened = Opened()
        opened.open("k", at: ago(30))
        opened.open("k", at: ago(1))
        XCTAssertEqual(opened.openedAt("k"), ago(30))
    }

    func testAnUnopenedRowSaysNothing() {
        let opened = Opened()
        XCTAssertNil(opened.label(for: "k", now: now))
        XCTAssertNil(opened.help(for: "k", now: now))
        XCTAssertFalse(opened.wasOpened("k"))
    }

    /// An afternoon of having something open is ordinary. Four days of it is
    /// the point — so one day, not the three the waiting clocks use.
    func testGoesAmberAfterADay() {
        var opened = Opened()
        opened.open("fresh", at: ago(5))
        opened.open("stale", at: ago(30))
        XCTAssertEqual(opened.health(for: "fresh", now: now), .neutral)
        XCTAssertEqual(opened.health(for: "stale", now: now), .attention)
    }

    func testForgettingClearsIt() {
        var opened = Opened()
        opened.open("k", at: now)
        opened.forget("k")
        XCTAssertFalse(opened.wasOpened("k"))
    }

    /// No expiry here, where the snooze has one. A snooze is a promise about a
    /// time and goes stale on its own; "you opened this" stays true until the
    /// pull request is dealt with — which is what takes it out of the fetch.
    func testPruneOnlyDropsWhatTheFetchLost() {
        var opened = Opened()
        opened.open("gone", at: ago(500))
        opened.open("here", at: ago(500))
        opened.prune(known: ["here"])
        XCTAssertFalse(opened.wasOpened("gone"))
        XCTAssertTrue(opened.wasOpened("here"), "age alone never drops one")
    }

    func testAPartialRoundPrunesNothing() {
        var opened = Opened()
        opened.open("k", at: now)
        opened.prune(known: nil)
        XCTAssertTrue(opened.wasOpened("k"))
    }

    func testSurvivesARoundTrip() {
        var opened = Opened()
        opened.open("k", at: now)
        XCTAssertEqual(Opened.decoded(from: opened.encoded()), opened)
        XCTAssertTrue(Opened.decoded(from: nil).isEmpty)
        XCTAssertTrue(Opened.decoded(from: Data("rubbish".utf8)).isEmpty)
    }

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
