import XCTest
@testable import PRRadarCore

/// Putting a review request down until later, without lying to anyone about it.
final class SnoozeTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func item(_ number: Int, pingedAt: Date) -> ReviewItem {
        ReviewItem(repo: "acme/repo", number: number, title: "t",
                   url: URL(string: "https://github.com/acme/repo/pull/\(number)")!,
                   isDraft: false, authorLogin: "someone", authorAvatarURL: nil,
                   pingedAt: pingedAt)
    }

    // MARK: - Sleeping and waking

    func testASnoozedKeyIsAsleepUntilItsTime() {
        var snoozes = Snoozes()
        snoozes.snooze("k", until: now.addingTimeInterval(3_600))
        XCTAssertTrue(snoozes.isAsleep("k", now: now))
        XCTAssertFalse(snoozes.isAsleep("k", now: now.addingTimeInterval(3_601)))
    }

    func testAnUnknownKeyIsAwake() {
        XCTAssertFalse(Snoozes().isAsleep("k", now: now))
    }

    func testWakingRemovesIt() {
        var snoozes = Snoozes()
        snoozes.snooze("k", until: now.addingTimeInterval(3_600))
        snoozes.wake("k")
        XCTAssertFalse(snoozes.isAsleep("k", now: now))
        XCTAssertTrue(snoozes.isEmpty)
    }

    func testSplitsAListInTwo() {
        let one = item(1, pingedAt: now), two = item(2, pingedAt: now)
        var snoozes = Snoozes()
        snoozes.snooze(one.pingKey, until: now.addingTimeInterval(60))
        XCTAssertEqual(snoozes.awake([one, two], now: now).map(\.number), [2])
        XCTAssertEqual(snoozes.asleep([one, two], now: now).map(\.number), [1])
    }

    /// The key carries the timestamp of the request it answers, so a
    /// re-request is a new key and the row comes straight back. The same
    /// choice the auto-review pin makes, for the same reason: a key with a
    /// request in it cannot outlive the request.
    func testARerequestWakesItImmediately() {
        let first = item(1, pingedAt: now)
        let rerequested = item(1, pingedAt: now.addingTimeInterval(600))
        var snoozes = Snoozes()
        snoozes.snooze(first.pingKey, until: now.addingTimeInterval(86_400))

        XCTAssertTrue(snoozes.isAsleep(first.pingKey, now: now))
        XCTAssertFalse(snoozes.isAsleep(rerequested.pingKey, now: now))
        XCTAssertEqual(snoozes.awake([rerequested], now: now).count, 1)
    }

    // MARK: - Pruning

    func testPruneDropsExpiredOnes() {
        var snoozes = Snoozes()
        snoozes.snooze("gone", until: now.addingTimeInterval(-1))
        snoozes.snooze("live", until: now.addingTimeInterval(600))
        snoozes.prune(known: ["gone", "live"], now: now)
        XCTAssertFalse(snoozes.isAsleep("gone", now: now))
        XCTAssertTrue(snoozes.isAsleep("live", now: now))
    }

    /// A key the fetch no longer returns belongs to a pull request that has
    /// been reviewed, merged or closed, and will never be asked about again.
    func testPruneDropsKeysTheFetchNoLongerSees() {
        var snoozes = Snoozes()
        snoozes.snooze("merged", until: now.addingTimeInterval(86_400))
        snoozes.snooze("still-there", until: now.addingTimeInterval(86_400))
        snoozes.prune(known: ["still-there"], now: now)
        XCTAssertFalse(snoozes.isAsleep("merged", now: now))
        XCTAssertTrue(snoozes.isAsleep("still-there", now: now))
    }

    /// A round that could not reach every account has not seen everything, and
    /// pruning against a partial list would quietly wake every row belonging
    /// to the account that was unreachable.
    func testPartialRoundOnlyPrunesExpiredOnes() {
        var snoozes = Snoozes()
        snoozes.snooze("unreachable-account", until: now.addingTimeInterval(86_400))
        snoozes.snooze("expired", until: now.addingTimeInterval(-1))
        snoozes.prune(known: nil, now: now)
        XCTAssertTrue(snoozes.isAsleep("unreachable-account", now: now))
        XCTAssertFalse(snoozes.isAsleep("expired", now: now))
    }

    // MARK: - Wake times

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "America/New_York")!
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)!
    }

    func testAnHourIsAnHour() {
        let from = date("2026-10-21T14:30:00-04:00")
        XCTAssertEqual(SnoozeOption.anHour.wake(from: from, calendar: calendar),
                       from.addingTimeInterval(3_600))
    }

    func testTomorrowIsNineTheNextMorning() {
        let wake = SnoozeOption.tomorrow.wake(from: date("2026-10-21T14:30:00-04:00"),
                                              calendar: calendar)
        XCTAssertEqual(calendar.component(.hour, from: wake), 9)
        XCTAssertEqual(calendar.component(.day, from: wake), 22)
    }

    /// Late at night, "tomorrow morning" is still the next calendar day — the
    /// option says tomorrow, and it means it.
    func testTomorrowLateAtNightIsStillTheNextDay() {
        let wake = SnoozeOption.tomorrow.wake(from: date("2026-10-21T23:30:00-04:00"),
                                              calendar: calendar)
        XCTAssertEqual(calendar.component(.day, from: wake), 22)
        XCTAssertEqual(calendar.component(.hour, from: wake), 9)
    }

    func testNextWeekIsTheFollowingMonday() {
        // 2026-10-21 is a Wednesday.
        let wake = SnoozeOption.nextWeek.wake(from: date("2026-10-21T14:30:00-04:00"),
                                              calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: wake), 2, "should be a Monday")
        XCTAssertEqual(calendar.component(.day, from: wake), 26)
        XCTAssertEqual(calendar.component(.hour, from: wake), 9)
    }

    /// Pressed on a Monday it parks the row for the week, not for forty
    /// minutes. The label says Monday because the week is what you are putting
    /// it down until.
    func testNextWeekOnAMondayIsTheMondayAfter() {
        let wake = SnoozeOption.nextWeek.wake(from: date("2026-10-26T08:20:00-04:00"),
                                              calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: wake), 2)
        XCTAssertEqual(calendar.component(.day, from: wake), 2, "the Monday after")
    }

    func testFridayAfternoonLandsOnMonday() {
        let wake = SnoozeOption.nextWeek.wake(from: date("2026-10-23T16:00:00-04:00"),
                                              calendar: calendar)
        XCTAssertEqual(calendar.component(.weekday, from: wake), 2)
        XCTAssertEqual(calendar.component(.day, from: wake), 26)
    }

    // MARK: - Persistence

    func testSurvivesARoundTrip() throws {
        var snoozes = Snoozes()
        snoozes.snooze("k", until: now.addingTimeInterval(600))
        let restored = Snoozes.decoded(from: snoozes.encoded())
        XCTAssertEqual(restored, snoozes)
        XCTAssertTrue(restored.isAsleep("k", now: now))
    }

    /// Nothing stored, and rubbish stored, both read as nothing asleep rather
    /// than as a failure the drawer has to render.
    func testUnreadableStoreIsEmpty() {
        XCTAssertTrue(Snoozes.decoded(from: nil).isEmpty)
        XCTAssertTrue(Snoozes.decoded(from: Data("not json".utf8)).isEmpty)
    }

    // MARK: - The clock, pointed forwards

    func testUntilReadsForwards() {
        XCTAssertEqual(TimeAgo.until(now.addingTimeInterval(30), now: now), "any moment")
        XCTAssertEqual(TimeAgo.until(now.addingTimeInterval(2_400), now: now), "in 40m")
        XCTAssertEqual(TimeAgo.until(now.addingTimeInterval(10_800), now: now), "in 3h")
        XCTAssertEqual(TimeAgo.until(now.addingTimeInterval(180_000), now: now), "in 2d")
    }

    /// `short` clamps a negative interval to zero and reads "now" for
    /// everything still to come, which is why this is its own function.
    func testUntilIsNotTimeAgoBackwards() {
        XCTAssertEqual(TimeAgo.short(since: now.addingTimeInterval(3_600), now: now), "now")
        XCTAssertEqual(TimeAgo.until(now.addingTimeInterval(3_600), now: now), "in 1h")
    }
}
