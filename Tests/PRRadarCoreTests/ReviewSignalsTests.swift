import XCTest
@testable import PRRadarCore

/// The triage signals the Reviews tab reads: how big, how broken, and who else
/// is on the hook.
final class ReviewSignalsTests: XCTestCase {

    let me = "RogelioAD"
    let myTeams = [TeamRef(org: "acme", slug: "web-team")]

    // MARK: - Payloads

    func decode(_ json: String) throws -> [String: SearchResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: SearchResult].self, from: Data(json.utf8))
    }

    /// One PR, always pinged at me, with whichever signal fields are asked for.
    /// `size` nil leaves all three out, which is the shape an older payload or
    /// a declined expansion has.
    func payload(size: (Int, Int, Int)? = (100, 20, 4),
                 rollup: String? = "SUCCESS",
                 requests: [(String, String)] = [("User", "RogelioAD")],
                 reviews: [(String, String)] = []) -> String {
        let sizeJSON = size.map { #""additions":\#($0.0),"deletions":\#($0.1),"changedFiles":\#($0.2),"# } ?? ""
        let rollupJSON = rollup.map { #""statusCheckRollup":{"state":"\#($0)"}"# } ?? "\"statusCheckRollup\":null"
        let reqJSON = requests.map { t, i in
            t == "User"
                ? #"{"requestedReviewer":{"__typename":"User","login":"\#(i)"}}"#
                : #"{"requestedReviewer":{"__typename":"Team","slug":"\#(i)"}}"#
        }.joined(separator: ",")
        let revJSON = reviews.map { login, state in
            #"{"author":{"login":"\#(login)"},"state":"\#(state)"}"#
        }.joined(separator: ",")

        return """
        {"direct":{"nodes":[{
          "id":"PR_1","number":1,"title":"a pull request",
          "url":"https://github.com/acme/repo/pull/1","isDraft":false,
          "author":{"login":"someone","avatarUrl":null},
          "repository":{"nameWithOwner":"acme/repo"},
          \(sizeJSON)
          "head":{"nodes":[{"commit":{"oid":"abc123",\(rollupJSON)}}]},
          "latestReviews":{"nodes":[\(revJSON)]},
          "reviewRequests":{"totalCount":\(requests.count),"nodes":[\(reqJSON)]},
          "requests":{"nodes":[{"createdAt":"2025-01-01T00:00:00Z",
            "requestedReviewer":{"__typename":"User","login":"RogelioAD"}}]},
          "myReviews":{"nodes":[]},
          "myComments":{"nodes":[]}
        }]}}
        """
    }

    func build(_ json: String) throws -> ReviewItem {
        let inbox = ReviewInbox(viewerLogin: me, teams: myTeams)
        let items = inbox.build(from: try decode(json))
        return try XCTUnwrap(items.first)
    }

    // MARK: - Size

    func testCarriesTheDiffSize() throws {
        let item = try build(payload(size: (120, 40, 6)))
        let signals = try XCTUnwrap(item.signals)
        XCTAssertEqual(signals.additions, 120)
        XCTAssertEqual(signals.deletions, 40)
        XCTAssertEqual(signals.changedFiles, 6)
        XCTAssertEqual(signals.lines, 160)
        XCTAssertEqual(signals.sizeLabel, "+120 −40 · 6f")
    }

    /// A payload with no sizes in it leaves the whole struct nil rather than
    /// zeroing it — a row saying `+0 −0 · 0f` about something nobody measured
    /// is the same lie as a failed branch compare rendered as "up to date".
    func testMissingSizeLeavesNoSignalsAtAll() throws {
        let item = try build(payload(size: nil))
        XCTAssertNil(item.signals)
    }

    func testWeightRisesWithSize() {
        func weight(_ lines: Int, files: Int = 1) -> Health {
            ReviewSignals(additions: lines, deletions: 0, changedFiles: files,
                          checks: nil, otherReviewers: 0, approvals: 0).weight
        }
        XCTAssertEqual(weight(40), .neutral)
        XCTAssertEqual(weight(400), .running)
        XCTAssertEqual(weight(1_400), .attention)
        // Files alone can carry it: a one-line change to forty files is a
        // sitting whatever the line count says.
        XCTAssertEqual(weight(40, files: 40), .attention)
    }

    // MARK: - Checks

    func testReadsTheRollupVerdict() throws {
        XCTAssertEqual(try build(payload(rollup: "SUCCESS")).signals?.checks, .success)
        XCTAssertEqual(try build(payload(rollup: "FAILURE")).signals?.checks, .failure)
        XCTAssertEqual(try build(payload(rollup: "PENDING")).signals?.checks, .pending)
    }

    /// No rollup is not a passing rollup. A repository with no CI and one whose
    /// CI has not started are both "nothing to say", and neither is green.
    func testNoRollupIsNotGreen() throws {
        let signals = try XCTUnwrap(try build(payload(rollup: nil)).signals)
        XCTAssertNil(signals.checks)
    }

    func testOnlyRealFailuresCountAsFailing() {
        XCTAssertTrue(RollupVerdict.failure.isFailing)
        XCTAssertTrue(RollupVerdict.error.isFailing)
        XCTAssertFalse(RollupVerdict.pending.isFailing)
        // A check that was promised and never arrived says nothing about the
        // diff, so it is not a reason to skip the review.
        XCTAssertFalse(RollupVerdict.expected.isFailing)
        XCTAssertFalse(RollupVerdict.success.isFailing)
    }

    // MARK: - Who else is on the hook

    func testCountsOtherReviewersButNotMe() throws {
        let item = try build(payload(requests: [("User", me),
                                                ("User", "alice"),
                                                ("User", "bob")]))
        XCTAssertEqual(item.signals?.otherReviewers, 2)
    }

    func testMyOwnTeamIsNotAnotherReviewer() throws {
        let item = try build(payload(requests: [("Team", "web-team")]))
        XCTAssertEqual(item.signals?.otherReviewers, 0)
    }

    func testAnotherTeamIsAnotherReviewer() throws {
        let item = try build(payload(requests: [("Team", "web-team"),
                                                ("Team", "infra-team")]))
        XCTAssertEqual(item.signals?.otherReviewers, 1)
    }

    /// A user whose login happens to match one of my team slugs is not my
    /// team. `__typename` decides it, never the string.
    func testAUserNamedLikeMyTeamStillCounts() throws {
        let item = try build(payload(requests: [("User", "web-team")]))
        XCTAssertEqual(item.signals?.otherReviewers, 1)
    }

    // MARK: - Approvals

    func testCountsLiveApprovalsOnly() throws {
        let item = try build(payload(reviews: [("alice", "APPROVED"),
                                               ("bob", "DISMISSED"),
                                               ("carol", "COMMENTED"),
                                               ("dave", "CHANGES_REQUESTED")]))
        XCTAssertEqual(item.signals?.approvals, 1)
    }

    /// My own approval is not news to me, and a row telling me somebody has
    /// approved this when the somebody is me would be the list answering
    /// itself.
    func testMyOwnApprovalIsNotCounted() throws {
        let item = try build(payload(reviews: [(me, "APPROVED")]))
        XCTAssertEqual(item.signals?.approvals, 0)
    }

    // MARK: - Sorting

    func item(lines: Int?, pingedAt: Date, number: Int) -> ReviewItem {
        ReviewItem(repo: "acme/repo", number: number, title: "t",
                   url: URL(string: "https://example.com")!, isDraft: false,
                   authorLogin: "someone", authorAvatarURL: nil, pingedAt: pingedAt,
                   signals: lines.map {
                       ReviewSignals(additions: $0, deletions: 0, changedFiles: 1,
                                     checks: nil, otherReviewers: 0, approvals: 0)
                   })
    }

    func testSmallestFirstOrdersBySize() {
        let now = Date()
        let items = [item(lines: 900, pingedAt: now, number: 1),
                     item(lines: 20, pingedAt: now, number: 2),
                     item(lines: 300, pingedAt: now, number: 3)]
        XCTAssertEqual(ReviewSortOrder.smallestFirst.apply(to: items).map(\.number),
                       [2, 3, 1])
    }

    /// An unmeasured row has no size, and sorting it as zero would float it to
    /// the very top claiming to be the quickest thing in the list.
    func testUnknownSizesSortLast() {
        let now = Date()
        let items = [item(lines: nil, pingedAt: now, number: 1),
                     item(lines: 900, pingedAt: now, number: 2),
                     item(lines: 20, pingedAt: now, number: 3)]
        XCTAssertEqual(ReviewSortOrder.smallestFirst.apply(to: items).map(\.number),
                       [3, 2, 1])
    }

    func testEqualSizesBreakTieOnAge() {
        let old = Date(timeIntervalSince1970: 1_000)
        let new = Date(timeIntervalSince1970: 2_000)
        let items = [item(lines: 50, pingedAt: new, number: 1),
                     item(lines: 50, pingedAt: old, number: 2)]
        XCTAssertEqual(ReviewSortOrder.smallestFirst.apply(to: items).map(\.number),
                       [2, 1])
    }

    // MARK: - Filtering

    func item(checks: RollupVerdict?, approvals: Int, number: Int) -> ReviewItem {
        ReviewItem(repo: "acme/repo", number: number, title: "t",
                   url: URL(string: "https://example.com")!, isDraft: false,
                   authorLogin: "someone", authorAvatarURL: nil, pingedAt: Date(),
                   signals: ReviewSignals(additions: 1, deletions: 0, changedFiles: 1,
                                          checks: checks, otherReviewers: 0,
                                          approvals: approvals))
    }

    func testChecksFilterDropsFailingOnes() {
        let items = [item(checks: .failure, approvals: 0, number: 1),
                     item(checks: .success, approvals: 0, number: 2),
                     item(checks: .pending, approvals: 0, number: 3)]
        XCTAssertEqual(ReviewFilter.checksNotFailing.apply(to: items).map(\.number),
                       [2, 3])
    }

    func testApprovalFilterDropsApprovedOnes() {
        let items = [item(checks: nil, approvals: 2, number: 1),
                     item(checks: nil, approvals: 0, number: 2)]
        XCTAssertEqual(ReviewFilter.notYetApproved.apply(to: items).map(\.number), [2])
    }

    /// A row whose signals never arrived matches everything. Hiding it would
    /// be failing it for a test it was never given, and this list's whole job
    /// is to be the complete account of what is waiting on you.
    func testUnmeasuredRowsSurviveEveryFilter() {
        let unmeasured = item(lines: nil, pingedAt: Date(), number: 9)
        for filter in ReviewFilter.allCases {
            XCTAssertEqual(filter.apply(to: [unmeasured]).map(\.number), [9],
                           "\(filter) hid an unmeasured row")
        }
    }

    /// The control is only offered when one of its options could hide
    /// something — the rule the pancake button already follows.
    func testFilterIsOnlyUsefulWhenItWouldDoSomething() {
        XCTAssertFalse(ReviewFilter.isUseful(on: [item(checks: .success, approvals: 0, number: 1)]))
        XCTAssertFalse(ReviewFilter.isUseful(on: [item(lines: nil, pingedAt: Date(), number: 1)]))
        XCTAssertTrue(ReviewFilter.isUseful(on: [item(checks: .failure, approvals: 0, number: 1)]))
        XCTAssertTrue(ReviewFilter.isUseful(on: [item(checks: .success, approvals: 1, number: 1)]))
    }

    // MARK: - Persistence

    /// A record encoded before signals existed decodes with none, rather than
    /// failing to decode at all and taking its row with it.
    func testOlderRecordsDecodeWithoutSignals() throws {
        let json = """
        {"repo":"acme/repo","number":1,"title":"t",
         "url":"https://github.com/acme/repo/pull/1","isDraft":false,
         "authorLogin":"someone","pingedAt":0,"account":""}
        """
        let item = try JSONDecoder().decode(ReviewItem.self, from: Data(json.utf8))
        XCTAssertNil(item.signals)
        XCTAssertEqual(item.number, 1)
    }
}
