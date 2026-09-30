import XCTest
@testable import PRRadarCore

/// The banner's whole job is to be seen once and then stop, so what is pinned
/// here is when it appears and — more importantly — when it does not.
final class SeasonalNoticeTests: XCTestCase {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int = 15) -> Date {
        var parts = DateComponents()
        parts.year = year; parts.month = month; parts.day = dayOfMonth
        return calendar.date(from: parts)!
    }

    // MARK: - Which season it is

    func testOctoberIsASeasonAndTheRestOfTheYearIsNot() {
        for month in 1...12 {
            let season = SeasonalNotice.season(on: day(2026, month), calendar: calendar)
            XCTAssertEqual(season, month == 10 ? "2026-10" : nil, "month \(month)")
        }
    }

    /// Keyed by year as well as month, or a dismissal in 2026 would silence
    /// the banner for good.
    func testTheKeyCarriesTheYear() {
        XCTAssertEqual(SeasonalNotice.season(on: day(2026, 10), calendar: calendar), "2026-10")
        XCTAssertEqual(SeasonalNotice.season(on: day(2027, 10), calendar: calendar), "2027-10")
    }

    /// The whole of October, not just the middle of it.
    func testTheSeasonCoversTheFirstAndLastOfTheMonth() {
        XCTAssertNotNil(SeasonalNotice.season(on: day(2026, 10, 1), calendar: calendar))
        XCTAssertNotNil(SeasonalNotice.season(on: day(2026, 10, 31), calendar: calendar))
        XCTAssertNil(SeasonalNotice.season(on: day(2026, 9, 30), calendar: calendar))
        XCTAssertNil(SeasonalNotice.season(on: day(2026, 11, 1), calendar: calendar))
    }

    /// Derived from what the cast declares, so the day somebody adds a
    /// December character the December banner already works.
    func testTheSeasonIsReadOffTheCastRatherThanHardcoded() {
        let months = Set(MascotID.allCases.compactMap { id -> Int? in
            guard case .month(let month) = id.season else { return nil }
            return month
        })
        for month in 1...12 {
            let season = SeasonalNotice.season(on: day(2026, month), calendar: calendar)
            XCTAssertEqual(season != nil, months.contains(month), "month \(month)")
        }
    }

    // MARK: - Whether to show it

    func testItShowsOnceAndThenStops() {
        let october = day(2026, 10)
        XCTAssertTrue(SeasonalNotice.shouldShow(on: october, calendar: calendar,
                                                acknowledged: nil))
        XCTAssertFalse(SeasonalNotice.shouldShow(on: october, calendar: calendar,
                                                 acknowledged: "2026-10"))
    }

    /// The regression this guards: a boolean "seen" flag would leave it
    /// dismissed for ever, and the arrival of a cast is news every year.
    func testNextYearIsNewsAgain() {
        XCTAssertTrue(SeasonalNotice.shouldShow(on: day(2027, 10), calendar: calendar,
                                                acknowledged: "2026-10"))
    }

    func testItNeverShowsOutsideTheSeason() {
        for month in 1...12 where month != 10 {
            XCTAssertFalse(SeasonalNotice.shouldShow(on: day(2026, month), calendar: calendar,
                                                     acknowledged: nil),
                           "month \(month)")
        }
    }

    /// An acknowledgement written by a build that knew about a season this one
    /// does not must not wedge the banner shut for a season it does know.
    func testAStaleAcknowledgementDoesNotSuppressADifferentSeason() {
        XCTAssertTrue(SeasonalNotice.shouldShow(on: day(2026, 10), calendar: calendar,
                                                acknowledged: "2026-12"))
    }

    // MARK: - What it says

    func testTheVisitorsAreTheSeasonalCastInTheCastsOwnOrder() {
        let october = SeasonalNotice.visitors(on: day(2026, 10), calendar: calendar)
        XCTAssertEqual(october, [.boo, .flit, .gourd, .rattle])
        XCTAssertEqual(october, MascotID.allCases.filter(october.contains))
        XCTAssertTrue(SeasonalNotice.visitors(on: day(2026, 7), calendar: calendar).isEmpty)
    }

    /// Whoever the banner names has to be somebody the picker will actually
    /// offer that day, or it is advertising a character you cannot choose.
    func testEveryVisitorNamedIsOnDutyThatDay() {
        let october = day(2026, 10)
        let roster = MascotID.onDuty(on: october, calendar: calendar, keepSeasonal: false)
        for id in SeasonalNotice.visitors(on: october, calendar: calendar) {
            XCTAssertTrue(roster.contains(id), "\(id) is announced but not on duty")
        }
    }

    func testNamesReadAsASentence() {
        XCTAssertEqual(SeasonalNotice.names([.boo, .flit, .gourd, .rattle]),
                       "Boo, Flit, Gourd and Rattle")
        XCTAssertEqual(SeasonalNotice.names([.boo, .flit]), "Boo and Flit")
        XCTAssertEqual(SeasonalNotice.names([.boo]), "Boo")
        XCTAssertEqual(SeasonalNotice.names([]), "")
    }
}
