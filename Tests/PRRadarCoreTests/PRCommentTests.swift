import XCTest
@testable import PRRadarCore

/// What counts as something somebody just said, and what makes it the same
/// thing on the next poll.
///
/// The rule the whole feature rests on: a comment is announced once. The poll
/// runs every sixty seconds and hands the same payload back every time, so
/// anything that keys on content rather than identity turns one sentence into
/// a banner a minute.
final class PRCommentTests: XCTestCase {

    // MARK: - Fixtures

    private func pr(_ number: Int = 1,
                    repo: String = "acme/app",
                    threads: [UnresolvedThread] = [],
                    approvals: [Approval] = []) -> MyPullRequest {
        MyPullRequest(
            repo: repo, number: number, title: "A pull request",
            url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
            isDraft: false,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0),
            headRefName: "head", baseRefName: "main",
            reviewDecision: .reviewRequired, mergeBlocker: .clean,
            approvals: approvals, awaitingReviewers: [],
            unresolvedThreadCount: threads.count,
            unresolvedThreads: threads,
            totalThreadCount: threads.count,
            checks: .empty, additions: 1, deletions: 1, changedFiles: 1)
    }

    private func thread(_ id: String,
                        comments: [UnresolvedThread.Comment]) -> UnresolvedThread {
        UnresolvedThread(id: id, path: "A.swift", line: 1, isOutdated: false,
                         comments: comments, moreComments: 0)
    }

    private func comment(_ id: String?, author: String = "alice",
                         body: String = "said", at: TimeInterval = 0)
        -> UnresolvedThread.Comment {
        UnresolvedThread.Comment(author: author, body: body, id: id,
                                 createdAt: Date(timeIntervalSince1970: at))
    }

    // MARK: - Identity

    func testAThreadCommentIsKeyedOnItsNodeID() {
        let found = PRComment.harvest(from: [pr(threads: [
            thread("T1", comments: [comment("C1")]),
        ])])
        XCTAssertEqual(found.map(\.id), ["C1"])
    }

    /// A key made of a body is a new key the moment somebody fixes a typo, and
    /// a new key is a second banner for a sentence that was said once.
    func testACommentWithNoIDIsDroppedRatherThanKeyedOnItsText() {
        let found = PRComment.harvest(from: [pr(threads: [
            thread("T1", comments: [comment(nil), comment("C2")]),
        ])])
        XCTAssertEqual(found.map(\.id), ["C2"])
    }

    /// The same payload twice is the same keys twice — which is what lets the
    /// seen-store do its job at all.
    func testTheSamePollTwiceProducesTheSameKeys() {
        let subject = pr(threads: [thread("T1", comments: [comment("C1")])],
                         approvals: [Approval(login: "bob", state: .approved,
                                              isLead: false,
                                              submittedAt: Date(timeIntervalSince1970: 5))])
        XCTAssertEqual(PRComment.harvest(from: [subject]).map(\.id),
                       PRComment.harvest(from: [subject]).map(\.id))
    }

    func testAReviewIsKeyedOnWhoSubmittedItAndWhen() {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let found = PRComment.harvest(from: [pr(approvals: [
            Approval(login: "bob", state: .approved, isLead: true, submittedAt: at),
        ])])
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].id,
                       PRComment.reviewKey(repo: "acme/app", number: 1,
                                           login: "bob", at: at))
        XCTAssertEqual(found[0].kind, .review(.approved))
    }

    /// Without one there is no key that is stable across polls, so the only
    /// safe thing is to say nothing.
    func testAReviewWithNoTimestampIsNotAnnounced() {
        let found = PRComment.harvest(from: [pr(approvals: [
            Approval(login: "bob", state: .approved, isLead: false),
        ])])
        XCTAssertTrue(found.isEmpty)
    }

    // MARK: - Bots

    func testABotIsRecognisedByTheShapeOfItsLogin() {
        XCTAssertTrue(PRComment.isBotLogin("github-actions[bot]"))
        XCTAssertTrue(PRComment.isBotLogin("senorito-developer[bot]"))
        XCTAssertTrue(PRComment.isBotLogin("github-actions"))
        XCTAssertFalse(PRComment.isBotLogin("alice"))
        XCTAssertFalse(PRComment.isBotLogin("robot-alice"))
    }

    func testBotsCanBeLeftOutOfBothKinds() {
        let subject = pr(
            threads: [thread("T1", comments: [
                comment("C1", author: "github-actions[bot]"),
                comment("C2", author: "alice"),
            ])],
            approvals: [
                Approval(login: "sonar[bot]", state: .approved, isLead: false,
                         submittedAt: Date(timeIntervalSince1970: 5)),
                Approval(login: "bob", state: .changesRequested, isLead: false,
                         submittedAt: Date(timeIntervalSince1970: 6)),
            ])

        let withBots = PRComment.harvest(from: [subject])
        XCTAssertEqual(withBots.count, 4)

        let without = PRComment.harvest(from: [subject], includingBots: false)
        XCTAssertEqual(without.map(\.author).sorted(), ["alice", "bob"])
    }

    // MARK: - Order and wording

    /// Oldest first, so a burst reads in the order it happened and the banner —
    /// which names the last one — names the latest thing anybody said.
    func testCommentsComeBackOldestFirst() {
        let found = PRComment.harvest(from: [pr(threads: [
            thread("T1", comments: [comment("C2", at: 200), comment("C1", at: 100)]),
        ])])
        XCTAssertEqual(found.map(\.id), ["C1", "C2"])
    }

    func testTheHeadlineNamesTheVerdictRatherThanCallingItAComment() {
        let at = Date(timeIntervalSince1970: 1)
        let found = PRComment.harvest(from: [pr(approvals: [
            Approval(login: "bob", state: .changesRequested, isLead: false,
                     submittedAt: at),
        ])])
        XCTAssertEqual(found.first?.headline, "bob requested changes on #1")
    }

    func testAThreadCommentSaysWhoCommented() {
        let found = PRComment.harvest(from: [pr(threads: [
            thread("T1", comments: [comment("C1", author: "alice")]),
        ])])
        XCTAssertEqual(found.first?.headline, "alice commented on #1")
    }

    /// Every comment carries its own pull request's url, because that is what
    /// clicking the banner has to open — and a harvest spans several.
    func testEachCommentCarriesItsOwnPullRequest() {
        let found = PRComment.harvest(from: [
            pr(1, threads: [thread("T1", comments: [comment("C1")])]),
            pr(2, repo: "acme/other",
               threads: [thread("T2", comments: [comment("C2")])]),
        ])
        let byID = Dictionary(uniqueKeysWithValues: found.map { ($0.id, $0) })
        XCTAssertEqual(byID["C1"]?.number, 1)
        XCTAssertEqual(byID["C2"]?.repo, "acme/other")
        XCTAssertEqual(byID["C2"]?.url.absoluteString,
                       "https://github.com/acme/other/pull/2")
    }

    func testNothingToSayIsAnEmptyHarvestRatherThanAFailure() {
        XCTAssertTrue(PRComment.harvest(from: []).isEmpty)
        XCTAssertTrue(PRComment.harvest(from: [pr()]).isEmpty)
    }
}
