import XCTest
@testable import PRRadarCore

/// The settings room's rules: which surface it measures itself as, what the
/// drawer counts when it is open, and what it will accept into the one setting
/// that is typed rather than picked.
final class SettingsRoomTests: XCTestCase {

    // MARK: - Rooms and surfaces

    /// Every room maps to a surface of its own. Two rooms sharing one would
    /// have them share a stored drawer height and a row-height namespace, so a
    /// drag in one would resize the other.
    func testEachRoomHasItsOwnSurface() {
        let surfaces = DrawerRoom.allCases.map(\.surface)
        XCTAssertEqual(Set(surfaces).count, DrawerRoom.allCases.count)
    }

    /// Rooms are surfaces, but not every surface is a room: the two tabs are
    /// reached from the tab strip and have no room to be toggled into.
    func testRoomSurfacesAreNotTabs() {
        for room in DrawerRoom.allCases {
            XCTAssertNotEqual(room.surface, .reviews)
            XCTAssertNotEqual(room.surface, .mine)
        }
    }

    func testSettingsIsASurface() {
        XCTAssertTrue(DrawerSurface.allCases.contains(.settings))
        XCTAssertEqual(DrawerRoom.settings.surface, .settings)
        XCTAssertEqual(DrawerRoom.trophies.surface, .trophies)
    }

    /// The raw values are persisted — in the stored room, in the drawer-height
    /// key and in every row-height key — so changing one silently discards
    /// whatever the user had dragged to.
    func testStoredNamesAreStable() {
        XCTAssertEqual(DrawerRoom.settings.rawValue, "settings")
        XCTAssertEqual(DrawerRoom.trophies.rawValue, "trophies")
        XCTAssertEqual(DrawerSurface.settings.rawValue, "settings")
    }

    /// A room dropped from a later build has to read as no room rather than
    /// trapping, because that value is already sitting in somebody's defaults.
    func testUnknownRoomNameIsNotARoom() {
        XCTAssertNil(DrawerRoom(rawValue: "leads"))
        XCTAssertNil(DrawerRoom(rawValue: ""))
    }

    // MARK: - Self-sizing

    /// A form has a bottom; a list does not. Only the form sizes itself.
    func testOnlySettingsFitsItsContent() {
        XCTAssertTrue(DrawerSurface.settings.fitsContent)
        for surface in [DrawerSurface.reviews, .mine, .trophies] {
            XCTAssertFalse(surface.fitsContent, surface.rawValue)
        }
    }

    /// The shelf stays draggable — it is a grid with more of itself to show,
    /// so a height somebody dragged to is a real instruction there.
    func testTheTrophyRoomIsStillResizable() {
        XCTAssertFalse(DrawerRoom.trophies.surface.fitsContent)
        XCTAssertTrue(DrawerRoom.settings.surface.fitsContent)
    }

    // MARK: - Sections

    /// The drawer snaps its height to whole sections, counting them through
    /// `allCases` while the view draws them from the same list. A duplicate id
    /// would collapse two measurements into one and leave the room a section
    /// short of its own contents.
    func testSectionIDsAreUnique() {
        let ids = SettingsSection.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, SettingsSection.allCases.count)
    }

    func testSectionsAreNamedAndIllustrated() {
        for section in SettingsSection.allCases {
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertFalse(section.symbol.isEmpty)
        }
    }

    /// Row heights are namespaced per surface, so a section's measurement and a
    /// review row's cannot collide even if they were somehow named the same.
    func testSectionHeightsAreNamespaced() {
        let key = RowHeightKeys.key(surface: .settings, id: SettingsSection.general.id)
        XCTAssertEqual(key, "settings:general")
        XCTAssertNotEqual(key, RowHeightKeys.key(surface: .reviews, id: "general"))
    }

    /// Pruning one surface's stale measurements leaves the other surfaces'
    /// alone — the settings room's heights must survive a refresh that drops
    /// every review row.
    func testPruningReviewsKeepsSettings() {
        let heights: [String: CGFloat] = [
            "settings:general": 80,
            "reviews:owner/repo#1": 90,
        ]
        let pruned = RowHeightKeys.pruned(heights, surface: .reviews, liveIDs: [])
        XCTAssertEqual(pruned["settings:general"], 80)
        XCTAssertNil(pruned["reviews:owner/repo#1"])
    }

    // MARK: - Release source

    func testPlainOwnerRepoIsKept() {
        XCTAssertEqual(ReleaseSource.normalized("RogelioAD/pr-radar"), "RogelioAD/pr-radar")
        XCTAssertEqual(ReleaseSource.normalized("  RogelioAD/pr-radar  "),
                       "RogelioAD/pr-radar")
    }

    /// What someone actually has on the clipboard is the browser URL, not the
    /// two words the API wants.
    func testPastedURLsAreAccepted() {
        for raw in ["https://github.com/RogelioAD/pr-radar",
                    "http://github.com/RogelioAD/pr-radar",
                    "github.com/RogelioAD/pr-radar",
                    "https://github.com/RogelioAD/pr-radar.git",
                    "https://github.com/RogelioAD/pr-radar/"] {
            XCTAssertEqual(ReleaseSource.normalized(raw), "RogelioAD/pr-radar", raw)
        }
    }

    /// Half a repository is the dangerous input: it forms a URL that 404s on
    /// every poll, which is indistinguishable from "nothing published yet" and
    /// so would turn the update notice off without ever reporting a fault.
    func testHalfTypedNamesAreRejected() {
        XCTAssertNil(ReleaseSource.normalized("RogelioAD"))
        XCTAssertNil(ReleaseSource.normalized("RogelioAD/"))
        XCTAssertNil(ReleaseSource.normalized("/pr-radar"))
        XCTAssertNil(ReleaseSource.normalized("/"))
        XCTAssertNil(ReleaseSource.normalized(""))
        XCTAssertNil(ReleaseSource.normalized("   "))
    }

    /// A longer path is rejected rather than truncated to its first two
    /// segments: silently watching `owner/repo` because someone pasted a link
    /// to an issue is a guess, and a wrong one is unreportable.
    func testLongerPathsAreRejected() {
        XCTAssertNil(ReleaseSource.normalized("RogelioAD/pr-radar/releases"))
        XCTAssertNil(ReleaseSource.normalized("https://github.com/a/b/issues/4"))
    }

    func testIllegalCharactersAreRejected() {
        XCTAssertNil(ReleaseSource.normalized("Rogelio AD/pr-radar"))
        XCTAssertNil(ReleaseSource.normalized("owner/pr radar"))
        XCTAssertNil(ReleaseSource.normalized("owner/repo?tab=readme"))
        XCTAssertNil(ReleaseSource.normalized("owner/repo#1"))
    }

    /// The characters GitHub does allow in a name have to survive, or the field
    /// would reject repositories that genuinely exist.
    func testLegalPunctuationSurvives() {
        XCTAssertEqual(ReleaseSource.normalized("my-org/dot.net_thing"),
                       "my-org/dot.net_thing")
    }
}

// MARK: - The automatic-review room

/// Automatic review is a room rather than a section of settings, and the
/// invariants that makes it answerable for are the same ones every other room
/// has to satisfy.
extension SettingsRoomTests {

    func testReviewIsARoomWithASurfaceOfItsOwn() {
        XCTAssertEqual(DrawerRoom.review.surface, .review)
        XCTAssertTrue(DrawerSurface.allCases.contains(.review))
    }

    /// The raw value is persisted — in the stored room, in the drawer-height
    /// key and in every row-height key — so changing it silently discards
    /// whatever the user had dragged to.
    func testTheReviewRoomsStoredNameIsStable() {
        XCTAssertEqual(DrawerRoom.review.rawValue, "review")
        XCTAssertEqual(DrawerSurface.review.rawValue, "review")
    }

    /// A form has a bottom. Every height other than its own either hides a
    /// control or leaves a band of empty material under the last one.
    func testTheReviewRoomFitsItsContentTheWaySettingsDoes() {
        XCTAssertTrue(DrawerSurface.review.fitsContent)
    }

    /// The review room's surface must not collide with the *reviews tab's*.
    /// They are one letter apart and mean entirely different things — one is a
    /// list of pull requests, the other is a form — and sharing a namespace
    /// would have a drag in one resize the other.
    func testTheReviewRoomIsNotTheReviewsTab() {
        XCTAssertNotEqual(DrawerSurface.review, DrawerSurface.reviews)
        XCTAssertNotEqual(DrawerSurface.review.rawValue, DrawerSurface.reviews.rawValue)
        XCTAssertFalse(DrawerSurface.reviews.fitsContent)
    }

    func testReviewSectionIDsAreUnique() {
        let ids = ReviewSection.allCases.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    /// The drawer snaps to whole groups, so a section the view draws without an
    /// entry here would let the height settle mid-group.
    func testEveryReviewSectionIsNamedAndIllustrated() {
        for section in ReviewSection.allCases {
            XCTAssertFalse(section.title.isEmpty, section.rawValue)
            XCTAssertFalse(section.symbol.isEmpty, section.rawValue)
        }
    }

    /// Settings gave these controls up when the room took them. Leaving a
    /// second copy behind would be two places to change one setting.
    func testSettingsNoLongerCarriesAReviewSection() {
        XCTAssertFalse(SettingsSection.allCases.map(\.rawValue).contains("review"))
    }
}

// MARK: - The two review modes

extension SettingsRoomTests {

    func testEveryModeIsNamedAndExplainedAndIllustrated() {
        for mode in AutoReviewMode.allCases {
            XCTAssertFalse(mode.title.isEmpty, mode.rawValue)
            XCTAssertFalse(mode.detail.isEmpty, mode.rawValue)
            XCTAssertFalse(mode.symbol.isEmpty, mode.rawValue)
        }
    }

    /// Exactly one mode posts on its own. If both did, or neither, the picker
    /// would be describing a distinction the code does not make.
    func testOnlyAutomaticPostsWithoutAsking() {
        XCTAssertTrue(AutoReviewMode.automatic.postsWithoutAsking)
        XCTAssertFalse(AutoReviewMode.curated.postsWithoutAsking)
        XCTAssertEqual(AutoReviewMode.allCases.filter(\.postsWithoutAsking).count, 1)
    }

    /// The raw values are persisted, so changing one silently resets somebody's
    /// choice — to the more consequential of the two, at that.
    func testStoredModeNamesAreStable() {
        XCTAssertEqual(AutoReviewMode.automatic.rawValue, "automatic")
        XCTAssertEqual(AutoReviewMode.curated.rawValue, "curated")
    }

    /// A build that cannot understand the stored mode must not resolve that
    /// doubt by posting to somebody's pull request.
    func testAnUnknownModeIsNotAMode() {
        XCTAssertNil(AutoReviewMode(rawValue: "yolo"))
        XCTAssertNil(AutoReviewMode(rawValue: ""))
    }
}
