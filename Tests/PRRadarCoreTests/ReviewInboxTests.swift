import XCTest
@testable import PRRadarCore

final class ReviewInboxTests: XCTestCase {

    let me = "RogelioAD"
    let myTeams = [TeamRef(org: "acme", slug: "web-team"),
                   TeamRef(org: "acme", slug: "mobile-team")]

    func decode(_ json: String) throws -> [String: SearchResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: SearchResult].self, from: Data(json.utf8))
    }

    /// Builds a single-PR search payload.
    func payload(number: Int = 1,
                 author: String = "someone",
                 draft: Bool = false,
                 requests: [(String, String, String)] = [],   // (typename, identity, date)
                 reviews: [(String, String)] = [],            // (login, date)
                 comments: [(String, String)] = []) -> String {
        func reviewerJSON(_ typename: String, _ identity: String) -> String {
            typename == "User"
                ? #"{"__typename":"User","login":"\#(identity)"}"#
                : #"{"__typename":"Team","slug":"\#(identity)"}"#
        }
        let reqNodes = requests.map { t, i, d in
            #"{"createdAt":"\#(d)","requestedReviewer":\#(reviewerJSON(t, i))}"#
        }.joined(separator: ",")
        let revNodes = reviews.map { l, d in
            #"{"createdAt":"\#(d)","state":"COMMENTED","author":{"login":"\#(l)"}}"#
        }.joined(separator: ",")
        let comNodes = comments.map { l, d in
            #"{"createdAt":"\#(d)","author":{"login":"\#(l)"}}"#
        }.joined(separator: ",")

        return """
        {"direct":{"nodes":[{
          "number":\(number),
          "title":"a pull request",
          "url":"https://github.com/acme/repo/pull/\(number)",
          "isDraft":\(draft),
          "author":{"login":"\(author)","avatarUrl":"https://avatars.githubusercontent.com/u/1"},
          "repository":{"nameWithOwner":"acme/repo"},
          "requests":{"nodes":[\(reqNodes)]},
          "myReviews":{"nodes":[\(revNodes)]},
          "myComments":{"nodes":[\(comNodes)]}
        }]}}
        """
    }

    func inbox(includeDrafts: Bool = true) -> ReviewInbox {
        ReviewInbox(viewerLogin: me, teams: myTeams, includeDrafts: includeDrafts)
    }

    // MARK: - The core rule

    func testPingedWithNoActivityShows() throws {
        let data = try decode(payload(requests: [("User", me, "2026-09-15T11:01:40Z")]))
        XCTAssertEqual(inbox().build(from: data).count, 1)
    }

    func testCommentAfterPingHides() throws {
        let data = try decode(payload(
            requests: [("User", me, "2026-09-15T11:00:00Z")],
            comments: [(me, "2026-09-15T12:00:00Z")]))
        XCTAssertTrue(inbox().build(from: data).isEmpty)
    }

    func testCommentReviewAfterPingHides() throws {
        let data = try decode(payload(
            requests: [("User", me, "2026-09-15T11:00:00Z")],
            reviews: [(me, "2026-09-15T12:00:00Z")]))
        XCTAssertTrue(inbox().build(from: data).isEmpty)
    }

    /// The real shape of PR #102: I reviewed, then was re-requested afterwards.
    /// A naive "have I ever commented?" check gets this wrong.
    func testReRequestAfterMyReviewShowsAgain() throws {
        let data = try decode(payload(
            number: 102,
            author: "erin",
            requests: [("User", me, "2026-09-14T20:59:13Z"),
                       ("User", me, "2026-09-15T13:37:09Z")],
            reviews: [(me, "2026-09-14T20:59:31Z")]))
        let items = inbox().build(from: data)
        XCTAssertEqual(items.count, 1)
        // Age must anchor to the newest ping, not the first one.
        XCTAssertEqual(items[0].pingedAt,
                       ISO8601DateFormatter().date(from: "2026-09-15T13:37:09Z"))
    }

    func testOtherPeoplesActivityDoesNotDismiss() throws {
        let data = try decode(payload(
            requests: [("User", me, "2026-09-15T11:00:00Z")],
            reviews: [("github-actions", "2026-09-15T12:00:00Z"),
                      ("frank", "2026-09-15T13:00:00Z")],
            comments: [("erin", "2026-09-15T14:00:00Z")]))
        XCTAssertEqual(inbox().build(from: data).count, 1)
    }

    // MARK: - Reviewer union discrimination

    func testTeamPingForMyTeamShows() throws {
        let data = try decode(payload(requests: [("Team", "mobile-team", "2026-09-15T11:00:00Z")]))
        XCTAssertEqual(inbox().build(from: data).count, 1)
    }

    func testTeamPingForTeamImNotInIsIgnored() throws {
        let data = try decode(payload(requests: [("Team", "platform-team", "2026-09-15T11:00:00Z")]))
        XCTAssertTrue(inbox().build(from: data).isEmpty)
    }

    /// `alice` is a real User, not a Team. A user login must never be
    /// matched against the team slug set, and vice versa.
    func testUserPingForSomeoneElseIsIgnored() throws {
        let data = try decode(payload(requests: [("User", "alice", "2026-09-15T11:00:00Z")]))
        XCTAssertTrue(inbox().build(from: data).isEmpty)
    }

    func testUserWhoseLoginMatchesATeamSlugIsNotATeamPing() throws {
        let data = try decode(payload(requests: [("User", "web-team", "2026-09-15T11:00:00Z")]))
        XCTAssertTrue(inbox().build(from: data).isEmpty)
    }

    func testPRWithNoPingForMeIsExcluded() throws {
        let data = try decode(payload(requests: []))
        XCTAssertTrue(inbox().build(from: data).isEmpty)
    }

    // MARK: - Dedupe, ordering, drafts

    func testDedupesAcrossSearchScopes() throws {
        // Same PR returned by the direct search and a team search.
        let one = payload(number: 500, requests: [("User", me, "2026-09-15T11:00:00Z")])
        let renamed = one.replacingOccurrences(of: "\"direct\"", with: "\"t0\"")
        let merged = "{" + one.dropFirst().dropLast() + "," + renamed.dropFirst().dropLast() + "}"
        let data = try decode(merged)
        XCTAssertEqual(data.count, 2, "fixture should contain two search scopes")
        XCTAssertEqual(inbox().build(from: data).count, 1, "but only one unique PR")
    }

    func testSortsOldestPingFirst() throws {
        let a = payload(number: 1, requests: [("User", me, "2026-09-15T11:00:00Z")])
        let b = payload(number: 2, requests: [("User", me, "2026-09-03T19:32:15Z")])
            .replacingOccurrences(of: "\"direct\"", with: "\"t0\"")
        let merged = "{" + a.dropFirst().dropLast() + "," + b.dropFirst().dropLast() + "}"
        let items = inbox().build(from: try decode(merged))
        XCTAssertEqual(items.map(\.number), [2, 1], "most overdue must sort first")
    }

    func testDraftsExcludedWhenConfigured() throws {
        let data = try decode(payload(draft: true, requests: [("User", me, "2026-09-15T11:00:00Z")]))
        XCTAssertEqual(inbox(includeDrafts: true).build(from: data).count, 1)
        XCTAssertTrue(inbox(includeDrafts: false).build(from: data).isEmpty)
    }

    // MARK: - Derived values

    func testStalenessThresholds() {
        let now = ISO8601DateFormatter().date(from: "2026-09-16T12:00:00Z")!
        func age(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        XCTAssertEqual(Staleness.of(age(2), now: now), .fresh)
        XCTAssertEqual(Staleness.of(age(30), now: now), .aging)
        XCTAssertEqual(Staleness.of(age(24 * 13), now: now), .stale)
    }

    func testTimeAgoShortForms() {
        let now = Date()
        XCTAssertEqual(TimeAgo.short(since: now.addingTimeInterval(-30), now: now), "now")
        XCTAssertEqual(TimeAgo.short(since: now.addingTimeInterval(-14 * 60), now: now), "14m")
        XCTAssertEqual(TimeAgo.short(since: now.addingTimeInterval(-3 * 3600), now: now), "3h")
        XCTAssertEqual(TimeAgo.short(since: now.addingTimeInterval(-13 * 86400), now: now), "13d")
    }

    func testPingKeyChangesOnReRequest() {
        func item(ping: String) -> ReviewItem {
            ReviewItem(repo: "o/r", number: 1, title: "t",
                       url: URL(string: "https://example.com")!, isDraft: false,
                       authorLogin: "a", authorAvatarURL: nil,
                       pingedAt: ISO8601DateFormatter().date(from: ping)!)
        }
        XCTAssertNotEqual(item(ping: "2026-09-14T20:59:13Z").pingKey,
                          item(ping: "2026-09-15T13:37:09Z").pingKey,
                          "a re-request must produce a new key so it notifies again")
    }
}

extension Staleness: Equatable {}
