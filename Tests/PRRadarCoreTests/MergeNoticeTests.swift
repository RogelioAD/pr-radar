import XCTest
@testable import PRRadarCore

/// The merge banner: what it says, what it is drawn from, and what the server
/// has to send for any of it to happen.
final class MergeNoticeTests: XCTestCase {

    // MARK: - What it says

    /// The person on the quiet line and the pull request on the loud one. The
    /// opposite arrangement is the obvious one and reads worse: "alice" is the
    /// part you take in without meaning to, and "web #412" is the part you
    /// might go and type somewhere.
    func testTheTwoLinesNameThePersonAndThePullRequest() {
        XCTAssertEqual(MergeNotice.headline(author: "alice"), "ALICE MERGED")
        XCTAssertEqual(MergeNotice.title(repo: "acme/web", number: 412), "WEB #412")
    }

    /// The owner is dropped, like everywhere else a repo is shown. Filtering
    /// uses the full name; a banner has 12% of a screen.
    func testTheOwnerIsDropped() {
        XCTAssertEqual(MergeNotice.title(repo: "acme/web", number: 1), "WEB #1")
    }

    /// A pull request whose author has since deleted their account has nobody
    /// to name. The line says what happened rather than naming a ghost.
    func testAMissingAuthorLeavesTheVerbStanding() {
        XCTAssertEqual(MergeNotice.headline(author: ""), "MERGED")
        XCTAssertEqual(MergeNotice.headline(author: "   "), "MERGED")
    }

    /// Length is not a styling question on a fixed-width font: it is the
    /// difference between a nod and a wall.
    func testLongNamesAreCutRatherThanAllowedToStretchTheBanner() {
        let long = MergeNotice.headline(author: "a-very-long-service-account")
        XCTAssertEqual(long.count, MergeNotice.nameLimit + " MERGED".count)

        let repo = MergeNotice.title(repo: "acme/elevation-church-mobile-rust", number: 9)
        XCTAssertTrue(repo.hasPrefix("ELEVATION-CHURCH"), repo)
        XCTAssertTrue(repo.hasSuffix(" #9"), "the number is never what gets cut")
    }

    func testABurstStopsNamingPeople() {
        XCTAssertEqual(MergeNotice.manyTitle(6), "6 PULL REQUESTS")
    }

    /// Every character the banner can produce has a glyph. A missing one draws
    /// as a gap, which is exactly the kind of thing nobody notices until it is
    /// on somebody's screen.
    func testEveryCharacterTheMergeBannerUsesExists() {
        var wanted = MergeNotice.manyHeadline + MergeNotice.manyTitle(4)
        wanted += MergeNotice.headline(author: "octo-cat.bot")
        wanted += MergeNotice.title(repo: "acme/web-app", number: 1234567890)
        for character in wanted.uppercased() {
            XCTAssertNotNil(BannerFont.glyphs[character], "no glyph for '\(character)'")
        }
    }

    // MARK: - The emblem

    /// Eleven cells square, like the star, so both banners put the same weight
    /// of drawing beside the same two lines of type.
    func testTheEmblemMatchesTheStarsFootprint() {
        XCTAssertEqual(MergeNotice.emblem.width, Achievement.emblem.width)
        XCTAssertEqual(MergeNotice.emblem.height, Achievement.emblem.height)
    }

    /// Entirely accent, so the one green is resolved live rather than written
    /// down a second time — and it is the same green the ready-to-merge count
    /// already wears.
    func testTheEmblemIsTintedWithTheSameGreenAsEverythingElseThatMeansClear() {
        let art = MergeNotice.emblem
        XCTAssertTrue(art.litPoints.allSatisfy { art[$0.x, $0.y] == .accent })

        let layout = SpriteLayout.mergeEmblem()
        XCTAssertEqual(layout.layers.count, 1)
        XCTAssertEqual(layout.layers[0].accent, .good)
    }

    /// A merge glyph is a branch joining a trunk. Drawn in one piece, or it
    /// reads as two unrelated marks at 2x.
    func testTheEmblemIsOneConnectedShape() {
        let art = MergeNotice.emblem
        var seen: Set<Point> = []
        var frontier = [art.litPoints[0]]
        while let point = frontier.popLast() {
            guard art[point.x, point.y] != nil, seen.insert(point).inserted else { continue }
            for dy in -1...1 {
                for dx in -1...1 {
                    frontier.append(Point(point.x + dx, point.y + dy))
                }
            }
        }
        XCTAssertEqual(seen.count, art.litPoints.count, "the branch is not joined to the trunk")
    }

    // MARK: - Sizing

    /// The standing line stopped standing when merges arrived: a login is
    /// routinely longer than the title under it. Measuring the achievement's
    /// fixed text while drawing somebody's name is how a window ends up
    /// narrower than the words inside it.
    func testTheBannerIsSizedAroundTheHeadlineItIsActuallyDrawing() {
        let headline = MergeNotice.headline(author: "a-long-login")
        let title = MergeNotice.title(repo: "acme/x", number: 1)
        let sized = Achievement.size(emblem: MergeNotice.emblem, title: title,
                                     headline: headline, scale: 2)
        let assumed = Achievement.size(emblem: MergeNotice.emblem, title: title, scale: 2)
        XCTAssertNotEqual(sized.width, assumed.width)
        XCTAssertGreaterThan(
            sized.width,
            CGFloat(BannerFont.width(of: headline)) * Achievement.headlineScale(2))
    }

    // MARK: - The dismiss mark

    /// The window is exactly the drawing, so a button the arithmetic did not
    /// know about would be drawn past the panel's edge and clipped to nothing
    /// — a banner that cannot be dismissed, which is the one failure this
    /// cannot survive.
    func testABannerWithAMarkIsWiderByExactlyTheMarkAndItsGap() {
        let title = MergeNotice.title(repo: "acme/web", number: 412)
        let headline = MergeNotice.headline(author: "alice")
        func width(dismissible: Bool) -> CGFloat {
            Achievement.size(emblem: MergeNotice.emblem, title: title,
                             headline: headline, dismissible: dismissible,
                             scale: 3).width
        }
        XCTAssertEqual(width(dismissible: true) - width(dismissible: false),
                       (Achievement.gapCells + Achievement.closeCells) * 3,
                       accuracy: 0.001)
    }

    /// Only the width. The mark is shorter than the two lines beside it, so a
    /// banner must not grow a taller window to hold it.
    func testTheMarkDoesNotChangeTheHeight() {
        let plain = Achievement.size(emblem: MergeNotice.emblem, title: "WEB #1",
                                     scale: 3).height
        let dismissible = Achievement.size(emblem: MergeNotice.emblem, title: "WEB #1",
                                           dismissible: true, scale: 3).height
        XCTAssertEqual(plain, dismissible)
        XCTAssertLessThanOrEqual(Achievement.closeCells * 3,
                                 Achievement.textHeight(scale: 3),
                                 "the mark has to fit beside the type, not above it")
    }

    /// The extra width is spent out of the same share of the screen, so a
    /// dismissible banner can only ever be the same size or a step smaller —
    /// never one that overflows.
    func testTheMarkIsPaidForOutOfTheScreenShareRatherThanAddedToIt() {
        for width in stride(from: CGFloat(800), through: 6000, by: 40) {
            let title = MergeNotice.title(repo: "acme/web", number: 412)
            let headline = MergeNotice.headline(author: "alice")
            let plain = Achievement.scale(forScreenWidth: width,
                                          emblem: MergeNotice.emblem,
                                          title: title, headline: headline)
            let dismissible = Achievement.scale(forScreenWidth: width,
                                                emblem: MergeNotice.emblem,
                                                title: title, headline: headline,
                                                dismissible: true)
            XCTAssertLessThanOrEqual(dismissible, plain, "\(width)")
        }
    }

    /// A drawn cross, not the font's letter X — which has a flat top and
    /// bottom and reads as a word of one character. Odd-numbered so the two
    /// strokes meet on a single centre pixel instead of straddling a seam.
    func testTheMarkIsASquareCrossThatMeetsInTheMiddle() {
        let mark = Achievement.closeMark
        XCTAssertEqual(mark.width, Int(Achievement.closeCells))
        XCTAssertEqual(mark.width, mark.height)
        XCTAssertEqual(mark.width % 2, 1, "an even cross has no centre")

        let middle = mark.width / 2
        XCTAssertNotNil(mark[middle, middle], "the strokes do not meet")
        for step in 0..<mark.width {
            XCTAssertNotNil(mark[step, step], "the falling stroke breaks at \(step)")
            XCTAssertNotNil(mark[mark.width - 1 - step, step],
                            "the rising stroke breaks at \(step)")
        }
    }

    /// Quiet. The green says what happened and the white says which pull
    /// request; a way to make the banner go away is furniture, and furniture
    /// drawn in `accent` would be the one thing on the card taking a live
    /// tint from a health it has nothing to do with.
    func testTheMarkIsDrawnInAFixedQuietSlot() {
        let mark = Achievement.closeMark
        XCTAssertTrue(mark.litPoints.allSatisfy { mark[$0.x, $0.y] == .shade })
        XCTAssertFalse(mark.litPoints.contains { mark[$0.x, $0.y] == .accent })
    }

    // MARK: - Decoding

    func payload(_ json: String) throws -> [String: MergesResult] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([String: MergesResult].self, from: Data(json.utf8))
    }

    func testDecodesTheAliasedShapeTheQueryAsksFor() throws {
        let merges = MergeWatch.build(from: try payload("""
        {"m0": {"pullRequests": {"nodes": [
          {"number": 412,
           "url": "https://github.com/acme/web/pull/412",
           "mergedAt": "2026-11-12T10:00:00Z",
           "author": {"login": "alice"},
           "repository": {"nameWithOwner": "acme/web"}}
        ]}}}
        """))
        XCTAssertEqual(merges.count, 1)
        XCTAssertEqual(merges[0].id, "acme/web#412")
        XCTAssertEqual(merges[0].authorLogin, "alice")
        XCTAssertEqual(merges[0].url?.absoluteString,
                       "https://github.com/acme/web/pull/412",
                       "the banner is a way into the pull request, not only a notice")
        XCTAssertEqual(merges[0].mergedAt, Date(timeIntervalSince1970: 1_794_477_600))
    }

    /// The repository comes off the node, never off the alias it arrived
    /// under. Aliases are positional, and a position that slipped would put the
    /// right number against the wrong repository — quietly, and in a banner
    /// nobody can go back and re-read.
    func testTheRepositoryComesOffTheNode() throws {
        let merges = MergeWatch.build(from: try payload("""
        {"m7": {"pullRequests": {"nodes": [
          {"number": 1, "mergedAt": "2026-11-12T10:00:00Z",
           "author": {"login": "a"},
           "repository": {"nameWithOwner": "acme/ios"}}
        ]}}}
        """))
        XCTAssertEqual(merges.first?.repo, "acme/ios")
    }

    /// A repository renamed, made private or simply gone comes back null. The
    /// round shrugs it off rather than losing the other repositories with it.
    func testAMissingRepositoryCostsOnlyItself() throws {
        let merges = MergeWatch.build(from: try payload("""
        {"m0": {"pullRequests": null},
         "m1": {"pullRequests": {"nodes": [
           {"number": 2, "mergedAt": "2026-11-12T10:00:00Z",
            "author": {"login": "a"},
            "repository": {"nameWithOwner": "acme/web"}}
         ]}}}
        """))
        XCTAssertEqual(merges.map(\.number), [2])
    }

    /// A node missing the one field that says *when* drops itself and nothing
    /// else — and a URL the server never sent costs that banner its link
    /// rather than costing the banner.
    func testAnUnusableNodeDropsItselfAndNothingElse() throws {
        let merges = MergeWatch.build(from: try payload("""
        {"m0": {"pullRequests": {"nodes": [
          {"number": 1,
           "author": {"login": "a"}, "repository": {"nameWithOwner": "acme/web"}},
          {"number": 2, "mergedAt": "2026-11-12T10:00:00Z",
           "author": null, "repository": {"nameWithOwner": "acme/web"}}
        ]}}}
        """))
        XCTAssertEqual(merges.map(\.number), [2], "no mergedAt, no merge")
        XCTAssertEqual(merges.first?.authorLogin, "", "a deleted account is not a failure")
        XCTAssertNil(merges.first?.url, "and a missing link is not one either")
    }

    // MARK: - The query

    func testTheQueryAsksOneAliasPerRepositoryForMergedPullRequestsOnly() throws {
        let query = try XCTUnwrap(Query.recentMerges(["acme/web", "acme/ios"]))
        XCTAssertTrue(query.contains("m0: repository(owner: \"acme\", name: \"web\")"), query)
        XCTAssertTrue(query.contains("m1: repository(owner: \"acme\", name: \"ios\")"), query)
        XCTAssertTrue(query.contains("states: MERGED"), query)
        // Every field `MergeWatch.build` refuses to work without, and
        // nothing else: a description nothing reads is a few kilobytes a
        // repository every sixty seconds.
        for field in ["number", "mergedAt", "nameWithOwner", "login", "url"] {
            XCTAssertTrue(query.contains(field), "the query stopped asking for \(field)")
        }
        XCTAssertFalse(query.contains("title"), "nothing shows the title")
    }

    /// Nothing to ask about is no request, not a request that asks nothing.
    func testNoRepositoriesIsNoQuery() {
        XCTAssertNil(Query.recentMerges([]))
        XCTAssertNil(Query.recentMerges(["not-a-qualified-name"]))
    }
}
