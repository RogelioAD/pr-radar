import XCTest
@testable import PRRadarCore

final class ReviewSessionTests: XCTestCase {

    let epoch = Date(timeIntervalSince1970: 1_789_000_000)

    private func subject(_ number: Int, node: String = "PR_1", account: String = "a") -> ReviewItem {
        ReviewItem(repo: "acme/repo", number: number, title: "t",
                   url: URL(string: "https://github.com/acme/repo/pull/\(number)")!,
                   isDraft: false, authorLogin: "someone", authorAvatarURL: nil,
                   pingedAt: epoch, account: account, nodeID: node)
    }

    private func session(_ number: Int, reviewed: String? = "aaa",
                         key: String? = "k", node: String = "PR_1",
                         lastRunAt: Date? = nil) -> ReviewSession {
        ReviewSession(sessionID: "s-\(number)", subject: subject(number, node: node),
                      reviewedOid: reviewed, lastRunAt: lastRunAt, recordKey: key)
    }

    private func log(_ status: AutoReviewStatus, key: String = "k") -> AutoReviewLog {
        var log = AutoReviewLog()
        log[key] = AutoReviewRecord(status: status)
        return log
    }

    // MARK: - When a re-review is due

    func testAPushAfterAPostedReviewIsDue() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1)

        XCTAssertEqual(sessions.rereviewsDue(heads: ["acme/repo#1": "bbb"], log: log(.posted)),
                       ["acme/repo#1"])
    }

    /// Approving does not stop it: a push after the decision is still new work.
    func testAPushAfterYouDecidedIsStillDue() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1)

        XCTAssertEqual(sessions.rereviewsDue(heads: ["acme/repo#1": "bbb"], log: log(.dismissed)),
                       ["acme/repo#1"])
    }

    func testAnUnmovedHeadIsNotDue() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1)

        XCTAssertTrue(sessions.rereviewsDue(heads: ["acme/repo#1": "aaa"], log: log(.posted)).isEmpty)
    }

    /// Not knowing the head is not a push.
    func testAnUnseenPullRequestIsNotDue() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1)

        XCTAssertTrue(sessions.rereviewsDue(heads: [:], log: log(.posted)).isEmpty)
    }

    func testWorkAlreadyOnItsWayIsNotStartedTwice() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1)

        for status in [AutoReviewStatus.queued, .running, .failed, .skipped] {
            XCTAssertTrue(sessions.rereviewsDue(heads: ["acme/repo#1": "bbb"], log: log(status)).isEmpty,
                          "\(status) should not be restarted")
        }
    }

    /// The record may have been pruned while the session lived on.
    func testAPrunedRecordDoesNotStopARereview() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1)

        XCTAssertEqual(sessions.rereviewsDue(heads: ["acme/repo#1": "bbb"], log: AutoReviewLog()),
                       ["acme/repo#1"])
    }

    func testASessionThatNeverFinishedARunIsNotDue() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1, reviewed: nil)

        XCTAssertTrue(sessions.rereviewsDue(heads: ["acme/repo#1": "bbb"], log: log(.posted)).isEmpty)
    }

    // MARK: - Resolving

    func testLabelsMapToTheThreadsTheyWereGivenFor() {
        var one = session(1)
        one.openThreads = [
            PostedThread(id: "T_a", path: "a.swift", line: 1, summary: "x"),
            PostedThread(id: "T_b", path: "b.swift", line: 2, summary: "y"),
        ]

        XCTAssertEqual(one.threadIDs(forLabels: ["t2", " T1 "]), ["T_a", "T_b"])
    }

    /// Only threads PR Radar opened can be closed by a re-review.
    func testAnUnknownLabelResolvesNothing() {
        var one = session(1)
        one.openThreads = [PostedThread(id: "T_a", path: "a.swift", line: 1, summary: "x")]

        XCTAssertTrue(one.threadIDs(forLabels: ["T9", "PRRT_other"]).isEmpty)
    }

    // MARK: - Lifetime

    func testAClosedPullRequestsSessionIsDropped() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1, node: "PR_1")
        sessions["acme/repo#2"] = session(2, node: "PR_2")

        sessions.retire(closed: ["PR_2"])

        XCTAssertEqual(Array(sessions.sessions.keys), ["acme/repo#1"])
    }

    func testTrimmingDropsTheLeastRecentlyRun() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1, lastRunAt: epoch)
        sessions["acme/repo#2"] = session(2, lastRunAt: epoch.addingTimeInterval(60))
        sessions["acme/repo#3"] = session(3, lastRunAt: epoch.addingTimeInterval(120))

        sessions.trim(limit: 2)

        XCTAssertEqual(sessions.sessions.keys.sorted(), ["acme/repo#2", "acme/repo#3"])
    }

    func testNodeIDsAreAskedForPerAccount() {
        var sessions = ReviewSessions()
        sessions["acme/repo#1"] = session(1, node: "PR_1")
        var other = session(2, node: "PR_2")
        other.subject = subject(2, node: "PR_2", account: "b")
        sessions["acme/repo#2"] = other

        XCTAssertEqual(sessions.nodeIDs(account: "a"), ["PR_1"])
    }

    // MARK: - Storage

    func testARoundTripKeepsEverything() {
        var sessions = ReviewSessions()
        var one = session(1, lastRunAt: epoch)
        one.openThreads = [PostedThread(id: "T_a", path: "a.swift", line: 1, summary: "x")]
        sessions["acme/repo#1"] = one

        XCTAssertEqual(ReviewSessions.decoded(from: sessions.encoded()), sessions)
    }

    func testGarbageIsNoSessions() {
        XCTAssertEqual(ReviewSessions.decoded(from: Data("nope".utf8)), ReviewSessions())
    }
}
