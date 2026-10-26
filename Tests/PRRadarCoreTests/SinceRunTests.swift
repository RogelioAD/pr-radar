import XCTest
@testable import PRRadarCore

/// What a row says about how far PR Radar's own reading has fallen behind.
final class SinceRunTests: XCTestCase {

    let me = "RogelioAD"
    let myTeams = [TeamRef(org: "acme", slug: "web-team")]

    let ranAt = Date(timeIntervalSince1970: 1_000_000)

    func date(_ offset: TimeInterval) -> Date { ranAt.addingTimeInterval(offset) }

    // MARK: - Counting

    func testCountsOnlyCommitsNewerThanTheRun() {
        let since = SinceRun.make(ranAt: ranAt,
                                  commitDates: [date(-500), date(-100), date(100), date(200)],
                                  total: 4)
        XCTAssertEqual(since.commits, 2)
        XCTAssertFalse(since.isAtLeast)
        XCTAssertEqual(since.label, "2 commits since PR Radar's review")
    }

    func testOneCommitIsSingular() {
        let since = SinceRun.make(ranAt: ranAt, commitDates: [date(-10), date(10)], total: 2)
        XCTAssertEqual(since.label, "1 commit since PR Radar's review")
    }

    /// A full page is a floor, not a total — the same rule `SinceReview` keeps,
    /// because it is the same page.
    func testSaturatedCountSaysSoAndStaysPlural() {
        let dates = (1...20).map { date(TimeInterval($0)) }
        let since = SinceRun.make(ranAt: ranAt, commitDates: dates, total: 95)
        XCTAssertTrue(since.isAtLeast)
        XCTAssertEqual(since.label, "20+ commits since PR Radar's review")
    }

    func testFullPageThatIsTheWholeHistoryIsNotSaturated() {
        let dates = (1...3).map { date(TimeInterval($0)) }
        let since = SinceRun.make(ranAt: ranAt, commitDates: dates, total: 3)
        XCTAssertFalse(since.isAtLeast)
        XCTAssertEqual(since.label, "3 commits since PR Radar's review")
    }

    /// Nothing pushed since the run means the findings below are still about
    /// the head, and the row says that by saying nothing. `hasMoved` is what
    /// the view asks.
    func testNothingNewHasNotMoved() {
        XCTAssertFalse(SinceRun.make(ranAt: ranAt, commitDates: [date(-10)], total: 1).hasMoved)
        XCTAssertTrue(SinceRun.make(ranAt: ranAt, commitDates: [date(10)], total: 1).hasMoved)
    }

    // MARK: - The last run, out of the log

    private func record(_ status: AutoReviewStatus, finishedAt: Date?) -> AutoReviewRecord {
        var record = AutoReviewRecord(status: status)
        record.finishedAt = finishedAt
        return record
    }

    /// Keyed by pull request, not by ping: a re-request starts a fresh record,
    /// and the ping-keyed answer for a row that was just pinged again would be
    /// "never" when PR Radar read it on Tuesday.
    func testLastRunIsTheNewestAcrossEveryPingOfTheSamePullRequest() {
        var log = AutoReviewLog()
        log["acme/repo#1@2026-09-15T11:00:00Z"] = record(.posted, finishedAt: date(100))
        log["acme/repo#1@2026-09-18T09:00:00Z"] = record(.posted, finishedAt: date(900))
        log["acme/repo#2@2026-09-15T11:00:00Z"] = record(.posted, finishedAt: date(300))

        XCTAssertEqual(log.lastRuns, ["acme/repo#1": date(900), "acme/repo#2": date(300)])
    }

    /// A review waiting to be posted has still been read, and is still the
    /// thing the chip is dating from.
    func testAReadyOrDismissedRunStillCounts() {
        var log = AutoReviewLog()
        log["acme/repo#1@2026-09-15T11:00:00Z"] = record(.ready, finishedAt: date(10))
        log["acme/repo#2@2026-09-15T11:00:00Z"] = record(.dismissed, finishedAt: date(20))
        XCTAssertEqual(log.lastRuns.count, 2)
    }

    /// A run that produced no findings is not a review to measure from, and
    /// one that never started is not a run at all.
    func testFailedSkippedAndUnfinishedRunsAreNotReviews() {
        var log = AutoReviewLog()
        log["acme/repo#1@2026-09-15T11:00:00Z"] = record(.failed, finishedAt: date(10))
        log["acme/repo#2@2026-09-15T11:00:00Z"] = record(.skipped, finishedAt: date(10))
        log["acme/repo#3@2026-09-15T11:00:00Z"] = record(.running, finishedAt: nil)
        log["acme/repo#4@2026-09-15T11:00:00Z"] = record(.posted, finishedAt: nil)
        XCTAssertEqual(log.lastRuns, [:])
    }

    func testPullRequestIsReadOffThePingKey() {
        XCTAssertEqual(AutoReviewLog.pullRequest(ofPingKey: "acme/repo#1@2026-09-15T11:00:00Z"),
                       "acme/repo#1")
        XCTAssertNil(AutoReviewLog.pullRequest(ofPingKey: "@2026-09-15T11:00:00Z"))
    }

    // MARK: - Derivation from a payload

    func payload(commits: [String] = [], total: Int? = nil) -> String {
        let commitJSON = commits.map { #"{"commit":{"committedDate":"\#($0)"}}"# }
            .joined(separator: ",")
        return """
        {"direct":{"nodes":[{
          "id":"PR_1","number":1,"title":"t",
          "url":"https://github.com/acme/repo/pull/1","isDraft":false,
          "author":{"login":"someone","avatarUrl":null},
          "repository":{"nameWithOwner":"acme/repo"},
          "head":{"nodes":[{"commit":{"oid":"head1"}}]},
          "recent":{"totalCount":\(total ?? commits.count),"nodes":[\(commitJSON)]},
          "requests":{"nodes":[{"createdAt":"2026-09-09T02:00:00Z",
            "requestedReviewer":{"__typename":"User","login":"RogelioAD"}}]},
          "myReviews":{"nodes":[]},
          "myComments":{"nodes":[]}
        }]}}
        """
    }

    func build(_ json: String, runs: [String: Date] = [:]) throws -> ReviewItem? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let searches = try decoder.decode([String: SearchResult].self, from: Data(json.utf8))
        return ReviewInbox(viewerLogin: me, teams: myTeams, runs: runs)
            .build(from: searches).first
    }

    func iso(_ string: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)!
    }

    /// No run, nothing to say — which is every pull request until PR Radar has
    /// read one.
    func testNoRunMeansNothingToSay() throws {
        let item = try build(payload(commits: ["2026-09-10T10:00:00Z"]))
        XCTAssertNil(item?.sinceRun)
    }

    func testCountsThePushesThatLandedAfterTheRun() throws {
        let item = try build(payload(commits: ["2026-09-09T10:00:00Z",
                                               "2026-09-11T10:00:00Z",
                                               "2026-09-12T10:00:00Z"]),
                             runs: ["acme/repo#1": iso("2026-09-10T00:00:00Z")])
        XCTAssertEqual(item?.sinceRun?.commits, 2)
        XCTAssertEqual(item?.sinceRun?.ranAt, iso("2026-09-10T00:00:00Z"))
    }

    /// A run on a different pull request says nothing about this one.
    func testARunOnAnotherPullRequestIsNotThisOne() throws {
        let item = try build(payload(commits: ["2026-09-12T10:00:00Z"]),
                             runs: ["acme/repo#2": iso("2026-09-10T00:00:00Z")])
        XCTAssertNil(item?.sinceRun)
    }

    /// The field is new, so every record already on disk decodes without it.
    func testAnItemWithoutARunStillDecodes() throws {
        let json = """
        {"repo":"acme/repo","number":1,"title":"t",
         "url":"https://github.com/acme/repo/pull/1","isDraft":false,
         "authorLogin":"someone","pingedAt":0,"account":""}
        """
        let item = try JSONDecoder().decode(ReviewItem.self, from: Data(json.utf8))
        XCTAssertNil(item.sinceRun)
    }
}
