import XCTest
@testable import PRRadarCore

/// Decoding a payload GitHub actually sent.
///
/// Every other test here builds its own JSON, which can only ever assert the
/// shape it was written against. This one is a real response to the real
/// document — captured once, with logins, titles and commit ids replaced —
/// so a field the server spells differently, nests differently, or stops
/// sending is caught here rather than on somebody's drawer.
///
/// It is deliberately thin on exact numbers. What it is for is that the
/// fragment and the decoders still describe the same thing.
final class LivePayloadTests: XCTestCase {

    func payload() throws -> [String: SearchResult] {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: "Fixtures/reviews-payload",
                              withExtension: "json"),
            "the captured payload is missing from the test bundle")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: SearchResult].self,
                                  from: Data(contentsOf: url))
    }

    func testTheRealPayloadDecodes() throws {
        let searches = try payload()
        let nodes = try XCTUnwrap(searches["direct"]).nodes
        XCTAssertFalse(nodes.isEmpty)
    }

    /// Every field the triage band reads, present and populated on a real
    /// pull request.
    func testTriageSignalsSurviveTheRealShape() throws {
        let nodes = try XCTUnwrap(try payload()["direct"]).nodes
        let node = try XCTUnwrap(nodes.first)

        XCTAssertNotNil(node.additions)
        XCTAssertNotNil(node.deletions)
        XCTAssertNotNil(node.changedFiles)
        XCTAssertEqual(node.head?.nodes.first?.commit?.statusCheckRollup?.state,
                       "SUCCESS")
        XCTAssertNotNil(node.latestReviews)
        XCTAssertNotNil(node.reviewRequests)

        let inbox = ReviewInbox(viewerLogin: "viewer", teams: [])
        let signals = try XCTUnwrap(inbox.signals(from: node))
        XCTAssertGreaterThan(signals.lines, 0)
        XCTAssertEqual(signals.checks, .success)
    }

    /// The aliased second `commits` connection, and the commit a review was
    /// made against — the two things the since-review chip is built from, and
    /// the two most likely to be lost to a fragment edit.
    func testSinceReviewSurvivesTheRealShape() throws {
        let nodes = try XCTUnwrap(try payload()["direct"]).nodes
        let node = try XCTUnwrap(nodes.first)

        XCTAssertNotNil(node.recent?.totalCount, "the `recent` alias is gone")
        XCTAssertFalse(node.recent?.nodes.isEmpty ?? true)
        XCTAssertNotNil(node.recent?.nodes.first?.commit?.committedDate,
                        "committedDate is what the count is measured against")

        // The fixture is `reviewed-by:@me`, so every node carries reviews, and
        // at least one of them names the commit it was made against.
        let reviews = try XCTUnwrap(node.myReviews).nodes
        XCTAssertFalse(reviews.isEmpty)
        XCTAssertTrue(reviews.contains { $0.commit?.oid != nil },
                      "`commit { oid }` is what anchors the incremental diff")
    }

    /// And the derivation end to end: the viewer reviewed these, so measuring
    /// from their own review has to produce a record.
    func testTheInboxBuildsASinceReviewFromIt() throws {
        let nodes = try XCTUnwrap(try payload()["direct"]).nodes
        let inbox = ReviewInbox(viewerLogin: "viewer", teams: [])

        let built = nodes.compactMap { inbox.sinceReview(in: $0) }
        XCTAssertFalse(built.isEmpty,
                       "the viewer reviewed every pull request in this payload")
        for since in built {
            XCTAssertNotNil(since.headOid)
            XCTAssertGreaterThanOrEqual(since.commits, 0)
        }
    }

    /// Review-request events are what both tabs' clocks are read from.
    func testRequestEventsSurviveTheRealShape() throws {
        let nodes = try XCTUnwrap(try payload()["direct"]).nodes
        let withRequests = nodes.first { !($0.requests?.nodes.isEmpty ?? true) }
        let node = try XCTUnwrap(withRequests, "no request events in the payload")

        let event = try XCTUnwrap(node.requests?.nodes.first)
        XCTAssertNotNil(event.createdAt)
        XCTAssertNotNil(event.requestedReviewer?.typename)

        // And the My PRs side reads the same event out of the same shape.
        let asked = MyPRInbox.requestedAt(in: node.requests)
        XCTAssertFalse(asked.isEmpty)
    }
}
