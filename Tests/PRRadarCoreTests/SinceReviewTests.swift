import XCTest
@testable import PRRadarCore

/// What a re-requested pull request says about what has changed since you last
/// read it.
final class SinceReviewTests: XCTestCase {

    let me = "RogelioAD"
    let myTeams = [TeamRef(org: "acme", slug: "web-team")]

    let reviewedAt = Date(timeIntervalSince1970: 1_000_000)

    func date(_ offset: TimeInterval) -> Date {
        reviewedAt.addingTimeInterval(offset)
    }

    // MARK: - Counting

    func testCountsOnlyCommitsNewerThanTheReview() {
        let since = SinceReview.make(
            reviewedAt: reviewedAt, reviewedOid: "aaa", headOid: "bbb",
            commitDates: [date(-500), date(-100), date(100), date(200), date(300)],
            total: 5)
        XCTAssertEqual(since.commits, 3)
        XCTAssertFalse(since.isAtLeast)
        XCTAssertEqual(since.label, "3 commits since your review")
    }

    func testOneCommitIsSingular() {
        let since = SinceReview.make(reviewedAt: reviewedAt, reviewedOid: "a", headOid: "b",
                                     commitDates: [date(-10), date(10)], total: 2)
        XCTAssertEqual(since.label, "1 commit since your review")
    }

    /// A full page is a floor, not a total. Saying `20` when the real number
    /// could be ninety is the quiet kind of wrong.
    func testSaturatedCountSaysSoAndStaysPlural() {
        let dates = (1...20).map { date(TimeInterval($0)) }
        let since = SinceReview.make(reviewedAt: reviewedAt, reviewedOid: "a",
                                     headOid: "b", commitDates: dates, total: 95)
        XCTAssertTrue(since.isAtLeast)
        XCTAssertEqual(since.label, "20+ commits since your review")
    }

    /// A page that is the whole history is exact, however full it looks.
    func testFullPageThatIsTheWholeHistoryIsNotSaturated() {
        let dates = (1...3).map { date(TimeInterval($0)) }
        let since = SinceReview.make(reviewedAt: reviewedAt, reviewedOid: "a",
                                     headOid: "b", commitDates: dates, total: 3)
        XCTAssertFalse(since.isAtLeast)
        XCTAssertEqual(since.label, "3 commits since your review")
    }

    // MARK: - Nothing new, and the force-push case

    /// Being re-pinged with nothing pushed behind it is a real thing — an
    /// author wanting a second look, or an approval dismissed — and "the diff
    /// is the one you already read" is the most useful sentence available.
    func testNothingNewIsSaidOutLoud() {
        let since = SinceReview.make(reviewedAt: reviewedAt, reviewedOid: "same",
                                     headOid: "same", commitDates: [date(-10)], total: 1)
        XCTAssertFalse(since.hasMoved)
        XCTAssertEqual(since.label, "nothing new since your review")
        XCTAssertEqual(since.health, .good)
    }

    /// A force-push can rewrite committer dates so nothing looks newer than
    /// the review while the head is plainly a different commit. The oids are
    /// what settle it.
    func testHeadThatMovedWithNoNewerDatesStillCounts() {
        let since = SinceReview.make(reviewedAt: reviewedAt, reviewedOid: "aaa",
                                     headOid: "bbb", commitDates: [date(-10)], total: 1)
        XCTAssertTrue(since.hasMoved)
        XCTAssertEqual(since.label, "head moved since your review")
        XCTAssertEqual(since.health, .attention)
    }

    /// With no oids to compare and no newer commits, there is nothing to
    /// claim — and the quiet answer is the honest one.
    func testNoOidsAndNoCommitsReadsAsNothingNew() {
        let since = SinceReview.make(reviewedAt: reviewedAt, reviewedOid: nil,
                                     headOid: nil, commitDates: [], total: 0)
        XCTAssertFalse(since.hasMoved)
    }

    // MARK: - The link

    func testIncrementalDiffNamesBothCommits() throws {
        let pr = URL(string: "https://github.com/acme/repo/pull/7")!
        let since = SinceReview(reviewedAt: reviewedAt, reviewedOid: "aaa",
                                headOid: "bbb", commits: 2, isAtLeast: false)
        XCTAssertEqual(try XCTUnwrap(since.incrementalDiff(of: pr)).absoluteString,
                       "https://github.com/acme/repo/pull/7/files/aaa..bbb")
    }

    /// The range form falls back to the whole diff when an end is missing,
    /// which would hand back the nine hundred lines this exists to avoid while
    /// looking like it had worked. No anchor, no link.
    func testNoLinkWithoutBothCommits() {
        let pr = URL(string: "https://github.com/acme/repo/pull/7")!
        XCTAssertNil(SinceReview(reviewedAt: reviewedAt, reviewedOid: nil, headOid: "b",
                                 commits: 1, isAtLeast: false).incrementalDiff(of: pr))
        XCTAssertNil(SinceReview(reviewedAt: reviewedAt, reviewedOid: "a", headOid: nil,
                                 commits: 1, isAtLeast: false).incrementalDiff(of: pr))
    }

    func testNoLinkWhenNothingMoved() {
        let pr = URL(string: "https://github.com/acme/repo/pull/7")!
        XCTAssertNil(SinceReview(reviewedAt: reviewedAt, reviewedOid: "same",
                                 headOid: "same", commits: 0,
                                 isAtLeast: false).incrementalDiff(of: pr))
    }

    // MARK: - Derivation from a payload

    func payload(reviews: [(login: String, id: String, at: String, oid: String?)],
                 commits: [String] = [],
                 total: Int? = nil,
                 headOid: String = "head1",
                 pingAt: String = "2001-09-09T02:00:00Z") -> String {
        let revJSON = reviews.map { r in
            let commit = r.oid.map { #"{"oid":"\#($0)"}"# } ?? "null"
            return #"{"id":"\#(r.id)","createdAt":"\#(r.at)","state":"COMMENTED","#
                 + #""author":{"login":"\#(r.login)"},"commit":\#(commit)}"#
        }.joined(separator: ",")
        let commitJSON = commits.map { #"{"commit":{"committedDate":"\#($0)"}}"# }
            .joined(separator: ",")
        return """
        {"direct":{"nodes":[{
          "id":"PR_1","number":1,"title":"t",
          "url":"https://github.com/acme/repo/pull/1","isDraft":false,
          "author":{"login":"someone","avatarUrl":null},
          "repository":{"nameWithOwner":"acme/repo"},
          "head":{"nodes":[{"commit":{"oid":"\(headOid)"}}]},
          "recent":{"totalCount":\(total ?? commits.count),"nodes":[\(commitJSON)]},
          "requests":{"nodes":[{"createdAt":"\(pingAt)",
            "requestedReviewer":{"__typename":"User","login":"RogelioAD"}}]},
          "myReviews":{"nodes":[\(revJSON)]},
          "myComments":{"nodes":[]}
        }]}}
        """
    }

    func build(_ json: String, pins: [String: String] = [:]) throws -> ReviewItem? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let searches = try decoder.decode([String: SearchResult].self, from: Data(json.utf8))
        return ReviewInbox(viewerLogin: me, teams: myTeams, pins: pins)
            .build(from: searches).first
    }

    /// Most pull requests have never been reviewed by me, and there is nothing
    /// to say about those.
    func testNoReviewOfMineMeansNothingToSay() throws {
        let item = try build(payload(reviews: []))
        XCTAssertNil(item?.sinceReview)
    }

    func testSomebodyElsesReviewIsNotMine() throws {
        let item = try build(payload(reviews: [("alice", "REV_1",
                                                "2001-09-09T01:00:00Z", "aaa")]))
        XCTAssertNil(item?.sinceReview)
    }

    func testReadsTheCommitMyReviewWasMadeAgainst() throws {
        let item = try build(payload(
            reviews: [(me, "REV_1", "2001-09-09T01:00:00Z", "aaa")],
            commits: ["2001-09-09T00:00:00Z", "2001-09-09T01:30:00Z"],
            headOid: "bbb"))
        let since = try XCTUnwrap(item?.sinceReview)
        XCTAssertEqual(since.reviewedOid, "aaa")
        XCTAssertEqual(since.headOid, "bbb")
        XCTAssertEqual(since.commits, 1)
    }

    /// The newest of my reviews is the one measured from — I may have looked
    /// at it three times.
    func testMeasuresFromMyNewestReview() throws {
        let item = try build(payload(
            reviews: [(me, "REV_1", "2001-09-09T00:10:00Z", "aaa"),
                      (me, "REV_2", "2001-09-09T01:00:00Z", "ccc")],
            commits: ["2001-09-09T00:30:00Z", "2001-09-09T01:30:00Z"],
            headOid: "bbb"))
        let since = try XCTUnwrap(item?.sinceReview)
        XCTAssertEqual(since.reviewedOid, "ccc")
        XCTAssertEqual(since.commits, 1)
    }

    /// A review PR Radar posted is not me having read the code, so it cannot
    /// anchor a diff labelled *since your review* — the same node the inbox
    /// rule already ignores, ignored again here for a different reason.
    func testThePinDoesNotCountAsHavingReviewed() throws {
        let json = payload(reviews: [(me, "REV_PIN", "2001-09-09T01:00:00Z", "aaa")])
        let key = ReviewItem.pingKey(
            repo: "acme/repo", number: 1,
            pingedAt: ISO8601DateFormatter().date(from: "2001-09-09T02:00:00Z")!)
        let item = try build(json, pins: [key: "REV_PIN"])
        XCTAssertNotNil(item, "the pin should keep the row standing")
        XCTAssertNil(item?.sinceReview, "the pin should not anchor a since-review")
    }

    /// GitHub returns no commit on a review whose commit was force-pushed out
    /// of the branch. The count survives that; the link does not.
    func testReviewWithNoCommitStillCounts() throws {
        let item = try build(payload(
            reviews: [(me, "REV_1", "2001-09-09T01:00:00Z", nil)],
            commits: ["2001-09-09T01:30:00Z"]))
        let since = try XCTUnwrap(item?.sinceReview)
        XCTAssertEqual(since.commits, 1)
        XCTAssertNil(since.reviewedOid)
        XCTAssertNil(since.incrementalDiff(of: URL(string: "https://x.test/pull/1")!))
    }
}
