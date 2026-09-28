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
    ///
    /// Reviews and comments carry a node id because that is what a pin names.
    /// It defaults to one derived from the position so the existing tests, which
    /// do not care, did not have to learn about it.
    func payload(number: Int = 1,
                 author: String = "someone",
                 draft: Bool = false,
                 nodeID: String = "PR_node1",
                 requests: [(String, String, String)] = [],   // (typename, identity, date)
                 reviews: [(String, String)] = [],            // (login, date)
                 comments: [(String, String)] = [],
                 reviewIDs: [String] = [],
                 commentIDs: [String] = []) -> String {
        func reviewerJSON(_ typename: String, _ identity: String) -> String {
            typename == "User"
                ? #"{"__typename":"User","login":"\#(identity)"}"#
                : #"{"__typename":"Team","slug":"\#(identity)"}"#
        }
        func id(_ given: [String], _ index: Int, _ prefix: String) -> String {
            index < given.count ? given[index] : "\(prefix)\(index)"
        }
        let reqNodes = requests.map { t, i, d in
            #"{"createdAt":"\#(d)","requestedReviewer":\#(reviewerJSON(t, i))}"#
        }.joined(separator: ",")
        let revNodes = reviews.enumerated().map { index, entry in
            let (l, d) = entry
            return #"{"id":"\#(id(reviewIDs, index, "REV_"))","createdAt":"\#(d)","state":"COMMENTED","author":{"login":"\#(l)"}}"#
        }.joined(separator: ",")
        let comNodes = comments.enumerated().map { index, entry in
            let (l, d) = entry
            return #"{"id":"\#(id(commentIDs, index, "IC_"))","createdAt":"\#(d)","author":{"login":"\#(l)"}}"#
        }.joined(separator: ",")

        return """
        {"direct":{"nodes":[{
          "id":"\(nodeID)",
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

    func inbox(includeDrafts: Bool = true,
               pins: [String: String] = [:]) -> ReviewInbox {
        ReviewInbox(viewerLogin: me, teams: myTeams,
                    includeDrafts: includeDrafts, pins: pins)
    }

    /// The key a pin is filed under, for the single-PR payload above.
    func key(number: Int = 1, pingedAt: String) -> String {
        let formatter = ISO8601DateFormatter()
        return ReviewItem.pingKey(repo: "acme/repo", number: number,
                                  pingedAt: formatter.date(from: pingedAt)!)
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

// MARK: - Pins

/// A pin names one review — the one PR Radar posted on my behalf — and says it
/// does not count as me having dealt with the PR. Everything else about the rule
/// is unchanged, which is what these tests are really checking.
extension ReviewInboxTests {

    private var ping: String { "2026-09-15T11:00:00Z" }

    /// The whole feature. Without this the automated comment dismisses the very
    /// PR it was meant to draw attention to.
    func testAPinnedReviewDoesNotCountAsMeHavingDealtWithIt() throws {
        let data = try decode(payload(
            requests: [("User", me, ping)],
            reviews: [(me, "2026-09-15T12:00:00Z")],
            reviewIDs: ["REV_pr_radar"]))
        let pins = [key(pingedAt: ping): "REV_pr_radar"]
        XCTAssertEqual(inbox(pins: pins).build(from: data).count, 1)
    }

    /// The existing rule must not be weakened in the process: an ordinary review
    /// of mine, with no pin naming it, still hides the row.
    func testAnUnpinnedReviewStillHidesTheRow() throws {
        let data = try decode(payload(
            requests: [("User", me, ping)],
            reviews: [(me, "2026-09-15T12:00:00Z")],
            reviewIDs: ["REV_pr_radar"]))
        XCTAssertTrue(inbox().build(from: data).isEmpty)
    }

    /// Having read the findings I comment myself, on github.com. That is a
    /// different node, it is not pinned, and it means I have dealt with the PR —
    /// so the row goes, without PR Radar being told anything.
    func testMyOwnLaterCommentStillHidesAPinnedRow() throws {
        let data = try decode(payload(
            requests: [("User", me, ping)],
            reviews: [(me, "2026-09-15T12:00:00Z")],
            comments: [(me, "2026-09-15T13:00:00Z")],
            reviewIDs: ["REV_pr_radar"],
            commentIDs: ["IC_mine"]))
        let pins = [key(pingedAt: ping): "REV_pr_radar"]
        XCTAssertTrue(inbox(pins: pins).build(from: data).isEmpty)
    }

    /// A re-request is a new ping, so it is a new key, so the old pin does not
    /// answer it. The PR comes back looking un-reviewed — which is correct: it
    /// is asking again, and it should be reviewed again.
    func testAPinForAnOlderPingDoesNotHoldANewerOne() throws {
        let newPing = "2026-09-16T09:00:00Z"
        let data = try decode(payload(
            requests: [("User", me, ping), ("User", me, newPing)],
            reviews: [(me, "2026-09-15T12:00:00Z")],
            reviewIDs: ["REV_pr_radar"]))
        let pins = [key(pingedAt: ping): "REV_pr_radar"]
        let items = inbox(pins: pins).build(from: data)
        XCTAssertEqual(items.count, 1)
        // Anchored to the newest ping, so the row's age is honest.
        XCTAssertEqual(items.first?.pingKey, key(pingedAt: newPing))
    }

    /// A pin only ever relaxes a filter over nodes the payload already carried.
    /// A merged or approved PR stops coming back from the search, and there is
    /// nothing for the pin to act on — it cannot conjure a row.
    func testAPinCannotResurrectAPRTheSearchNoLongerReturns() throws {
        let data = try decode(#"{"direct":{"nodes":[]}}"#)
        let pins = [key(pingedAt: ping): "REV_pr_radar"]
        XCTAssertTrue(inbox(pins: pins).build(from: data).isEmpty)
    }

    /// Drafts are excluded before any of this is consulted. A pin is about
    /// whether I have responded, not about whether the PR is asking yet.
    func testAPinDoesNotOverrideTheDraftFilter() throws {
        let data = try decode(payload(
            draft: true,
            requests: [("User", me, ping)],
            reviews: [(me, "2026-09-15T12:00:00Z")],
            reviewIDs: ["REV_pr_radar"]))
        let pins = [key(pingedAt: ping): "REV_pr_radar"]
        XCTAssertTrue(inbox(includeDrafts: false, pins: pins).build(from: data).isEmpty)
    }

    /// A pin naming a node that is not in the payload is inert, not a crash and
    /// not a row that hangs around forever.
    func testAPinNamingAnAbsentNodeChangesNothing() throws {
        let data = try decode(payload(
            requests: [("User", me, ping)],
            reviews: [(me, "2026-09-15T12:00:00Z")],
            reviewIDs: ["REV_pr_radar"]))
        let pins = [key(pingedAt: ping): "REV_something_else"]
        XCTAssertTrue(inbox(pins: pins).build(from: data).isEmpty)
    }

    /// Mutations need the PR's node id, so the inbox has to carry it through.
    func testTheNodeIDIsCarriedOntoTheItem() throws {
        let data = try decode(payload(nodeID: "PR_abc",
                                      requests: [("User", me, ping)]))
        XCTAssertEqual(inbox().build(from: data).first?.nodeID, "PR_abc")
    }

    /// An older payload without one still builds a row — it just cannot be
    /// acted on, which the UI says rather than hiding the PR.
    func testAMissingNodeIDIsNotAFailureToBuild() throws {
        let json = try decode(payload(requests: [("User", me, ping)])
            .replacingOccurrences(of: #""id":"PR_node1","#, with: ""))
        let items = inbox().build(from: json)
        XCTAssertEqual(items.count, 1)
        XCTAssertNil(items.first?.nodeID)
    }

    /// The key is written in one place and read in another, so the static and
    /// the property must not be allowed to drift apart.
    func testTheStaticKeyAndThePropertyAgree() {
        let when = Date(timeIntervalSince1970: 1_789_000_000)
        let item = ReviewItem(repo: "acme/repo", number: 7,
                              title: "t", url: URL(string: "https://x")!,
                              isDraft: false, authorLogin: "a",
                              authorAvatarURL: nil, pingedAt: when)
        XCTAssertEqual(item.pingKey,
                       ReviewItem.pingKey(repo: "acme/repo", number: 7, pingedAt: when))
    }
}
