import XCTest
@testable import PRRadarCore

/// The clock on your own pull requests, pointed at the people you are waiting
/// for.
final class AwaitingReviewTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func ago(_ days: Double) -> Date {
        now.addingTimeInterval(-days * 86_400)
    }

    // MARK: - Which ask is reported

    /// The question the chip answers is how long this has been waiting on
    /// somebody, and the answer is the longest anybody has had it.
    func testReportsTheLongestOutstandingAsk() throws {
        let awaiting = try XCTUnwrap(AwaitingReview.make(
            reviewers: ["alice", "bob"],
            askedAt: ["alice": ago(1), "bob": ago(4)]))
        XCTAssertEqual(awaiting.longest, "bob")
        XCTAssertEqual(awaiting.since, ago(4))
    }

    func testNobodyWaitingIsNothingToSay() {
        XCTAssertNil(AwaitingReview.make(reviewers: [], askedAt: ["alice": ago(1)]))
    }

    /// A reviewer who has already reviewed is out of `reviewRequests`, so
    /// their ask must not go on ageing the row.
    func testOnlyOutstandingReviewersCount() throws {
        let awaiting = try XCTUnwrap(AwaitingReview.make(
            reviewers: ["alice"],
            askedAt: ["alice": ago(1), "bob": ago(9)]))
        XCTAssertEqual(awaiting.since, ago(1))
        XCTAssertEqual(awaiting.reviewers, ["alice"])
    }

    // MARK: - What it says

    func testNamesOnePersonAndCountsSeveral() {
        let one = AwaitingReview(reviewers: ["alice"], since: ago(4), longest: "alice")
        XCTAssertEqual(one.label(now: now), "waiting 4d · alice")

        let several = AwaitingReview(reviewers: ["alice", "bob", "carol"],
                                     since: ago(4), longest: "bob")
        XCTAssertEqual(several.label(now: now), "waiting 4d · 3 reviewers")
    }

    /// A request older than the page the query reads leaves no timestamp. The
    /// row still says who it is waiting on and simply does not claim a
    /// duration — the shape `needs rebase` takes when the count is missing.
    func testUnknownAskTimeNamesWhoWithoutClaimingHowLong() {
        let awaiting = AwaitingReview(reviewers: ["alice"], since: nil, longest: nil)
        XCTAssertEqual(awaiting.label(now: now), "waiting on alice")
        XCTAssertEqual(awaiting.health(now: now), .neutral,
                       "an unread duration must not be painted as fresh")
    }

    // MARK: - The ladder

    /// The same three steps the Reviews tab ages a request by, so the two tabs
    /// cannot come to mean different things by the same colour.
    func testUsesTheSameStalenessLadder() {
        func health(_ days: Double) -> Health {
            AwaitingReview(reviewers: ["a"], since: ago(days), longest: "a")
                .health(now: now)
        }
        XCTAssertEqual(health(0.5), Staleness.fresh.health)
        XCTAssertEqual(health(2), Staleness.aging.health)
        XCTAssertEqual(health(5), Staleness.stale.health)
    }

    // MARK: - Reading the timeline

    func timeline(_ events: [(type: String, who: String, at: String)]) -> TimelineConn {
        let nodes = events.map { e in
            let reviewer = e.type == "Team"
                ? #"{"__typename":"Team","slug":"\#(e.who)"}"#
                : #"{"__typename":"User","login":"\#(e.who)"}"#
            return #"{"createdAt":"\#(e.at)","requestedReviewer":\#(reviewer)}"#
        }.joined(separator: ",")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(TimelineConn.self,
                                   from: Data(#"{"nodes":[\#(nodes)]}"#.utf8))
    }

    func iso(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    /// Being re-requested restarts that person's clock, exactly as a
    /// re-request restarts yours on the other tab.
    func testARerequestRestartsThatPersonsClock() {
        let asked = MyPRInbox.requestedAt(in: timeline([
            (type: "User", who: "alice", at: "2026-10-01T00:00:00Z"),
            (type: "User", who: "alice", at: "2026-10-18T00:00:00Z"),
        ]))
        XCTAssertEqual(asked["alice"], iso("2026-10-18T00:00:00Z"))
    }

    /// Teams key by slug and users by login, because that is how
    /// `awaitingReviewers` keys them — if the two disagreed the lookup would
    /// silently miss and the row would quietly stop claiming a duration.
    func testTeamsKeyBySlugAndUsersByLogin() {
        let asked = MyPRInbox.requestedAt(in: timeline([
            (type: "User", who: "alice", at: "2026-10-01T00:00:00Z"),
            (type: "Team", who: "web-team", at: "2026-10-02T00:00:00Z"),
        ]))
        XCTAssertEqual(asked.keys.sorted(), ["alice", "web-team"])
    }

    func testNoTimelineIsAnEmptyMap() {
        XCTAssertTrue(MyPRInbox.requestedAt(in: nil).isEmpty)
    }

    // MARK: - End to end through the inbox

    func testTheRowLearnsWhenItsReviewersWereAsked() throws {
        let json = """
        {"issueCount":1,"nodes":[{
          "id":"PR_1","number":1,"title":"t",
          "url":"https://github.com/acme/repo/pull/1","isDraft":false,
          "createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z",
          "headRefName":"head","baseRefName":"main",
          "repository":{"nameWithOwner":"acme/repo"},
          "reviewRequests":{"nodes":[
            {"requestedReviewer":{"__typename":"User","login":"alice"}},
            {"requestedReviewer":{"__typename":"User","login":"bob"}}]},
          "requests":{"nodes":[
            {"createdAt":"2026-10-15T00:00:00Z",
             "requestedReviewer":{"__typename":"User","login":"alice"}},
            {"createdAt":"2026-10-10T00:00:00Z",
             "requestedReviewer":{"__typename":"User","login":"bob"}},
            {"createdAt":"2026-10-02T00:00:00Z",
             "requestedReviewer":{"__typename":"User","login":"carol"}}]},
          "reviewThreads":{"totalCount":0,"nodes":[]}
        }]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(MyPRSearchResult.self, from: Data(json.utf8))
        let item = try XCTUnwrap(MyPRInbox().build(from: result).first)

        let awaiting = try XCTUnwrap(item.awaiting)
        XCTAssertEqual(awaiting.reviewers, ["alice", "bob"])
        // bob was asked earliest of the two still outstanding; carol has
        // already reviewed and is not in the live set at all.
        XCTAssertEqual(awaiting.longest, "bob")
        XCTAssertEqual(awaiting.since, iso("2026-10-10T00:00:00Z"))
    }

    /// A payload with no request events — an older one, or a pull request
    /// nobody has been asked about — leaves the row with nothing to claim
    /// rather than failing to build.
    func testAPayloadWithoutRequestEventsStillBuilds() throws {
        let json = """
        {"issueCount":1,"nodes":[{
          "id":"PR_1","number":1,"title":"t",
          "url":"https://github.com/acme/repo/pull/1","isDraft":false,
          "createdAt":"2026-10-01T00:00:00Z","updatedAt":"2026-10-01T00:00:00Z",
          "headRefName":"head","baseRefName":"main",
          "repository":{"nameWithOwner":"acme/repo"},
          "reviewRequests":{"nodes":[
            {"requestedReviewer":{"__typename":"User","login":"alice"}}]},
          "reviewThreads":{"totalCount":0,"nodes":[]}
        }]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(MyPRSearchResult.self, from: Data(json.utf8))
        let item = try XCTUnwrap(MyPRInbox().build(from: result).first)

        let awaiting = try XCTUnwrap(item.awaiting)
        XCTAssertEqual(awaiting.label(now: now), "waiting on alice")
        XCTAssertNil(awaiting.since)
    }
}
