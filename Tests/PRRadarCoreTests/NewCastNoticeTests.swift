import XCTest
@testable import PRRadarCore

/// The banner's whole job is to be seen once and then stop.
final class NewCastNoticeTests: XCTestCase {

    func testItAnnouncesTheNewestBuiltInCohort() {
        XCTAssertEqual(NewCastNotice.cohort, .october2026)
        XCTAssertEqual(NewCastNotice.visitors, [.boo, .flit, .gourd, .rattle])
    }

    /// Never the custom shelf. A fork's own characters are not news to the
    /// fork that wrote them, and announcing them would put a banner in front
    /// of somebody every time they added one.
    func testItNeverAnnouncesTheCustomShelf() {
        XCTAssertNotEqual(NewCastNotice.cohort, .custom)
        XCTAssertFalse(NewCastNotice.visitors.contains { Mascot.named($0).cohort == .custom })
    }

    func testItShowsOnceAndThenStops() {
        XCTAssertTrue(NewCastNotice.shouldShow(acknowledged: nil))
        XCTAssertFalse(NewCastNotice.shouldShow(acknowledged: NewCastNotice.acknowledgement))
    }

    /// The regression this guards: a boolean "seen" flag would stay dismissed
    /// for ever, and the next cohort is news again.
    func testAnOlderAcknowledgementDoesNotSilenceANewerCohort() {
        XCTAssertTrue(NewCastNotice.shouldShow(acknowledged: MascotCohort.og.rawValue))
        XCTAssertTrue(NewCastNotice.shouldShow(acknowledged: MascotCohort.space.rawValue))
    }

    /// Whoever it names has to be somebody the picker will actually offer.
    func testEveryCharacterNamedIsOneTheAppShips() {
        for id in NewCastNotice.visitors {
            XCTAssertTrue(Mascot.all.contains { $0.id == id }, "\(id) is announced but absent")
        }
    }

    /// The heading is the shelf's own title, so the banner and the room it
    /// points at cannot disagree about what the group is called.
    func testTheHeadlineIsTheShelfsOwnTitle() {
        XCTAssertEqual(NewCastNotice.headline, MascotCohort.october2026.title)
    }

    func testNamesReadAsASentence() {
        XCTAssertEqual(NewCastNotice.names([.boo, .flit, .gourd, .rattle]),
                       "Boo, Flit, Gourd and Rattle")
        XCTAssertEqual(NewCastNotice.names([.boo, .flit]), "Boo and Flit")
        XCTAssertEqual(NewCastNotice.names([.boo]), "Boo")
        XCTAssertEqual(NewCastNotice.names([]), "")
    }
}
