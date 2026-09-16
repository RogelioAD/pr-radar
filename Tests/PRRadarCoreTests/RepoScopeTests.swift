import XCTest
@testable import PRRadarCore

final class RepoScopeTests: XCTestCase {

    struct Row: Equatable {
        let repo: String
        let number: Int
    }

    let rows = [
        Row(repo: "acme/widgets-mobile", number: 1),
        Row(repo: "acme/widgets-web", number: 2),
        Row(repo: "acme/widgets-mobile", number: 3),
        Row(repo: "rogelioad/pr-radar", number: 4),
    ]

    // MARK: - Filtering

    func testNilRepoReturnsEverything() {
        XCTAssertEqual(RepoScope.apply(nil, to: rows, repoOf: \.repo), rows)
    }

    func testFiltersToOneRepo() {
        let filtered = RepoScope.apply("acme/widgets-mobile",
                                       to: rows, repoOf: \.repo)
        XCTAssertEqual(filtered.map(\.number), [1, 3])
    }

    func testFilteringPreservesOrder() {
        let filtered = RepoScope.apply("acme/widgets-mobile",
                                       to: rows, repoOf: \.repo)
        XCTAssertEqual(filtered.map(\.number), [1, 3], "sorting is applied afterwards")
    }

    func testUnknownRepoFiltersToNothing() {
        XCTAssertTrue(RepoScope.apply("someone/else", to: rows, repoOf: \.repo).isEmpty)
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertTrue(RepoScope.apply("a/b", to: [Row](), repoOf: \.repo).isEmpty)
    }

    // MARK: - Available repositories

    func testNamesUnionsBothTabsAndDeduplicates() {
        let names = RepoScope.names(
            reviews: ["org/a", "org/b", "org/a"],
            mine: ["org/b", "org/c"])
        XCTAssertEqual(names, ["org/a", "org/b", "org/c"])
    }

    /// A repo you only have reviews in, and one you only have PRs in, must both
    /// appear — the menu covers both tabs.
    func testNamesIncludeRepoPresentInOnlyOneTab() {
        let names = RepoScope.names(reviews: ["org/reviews-only"],
                                    mine: ["org/mine-only"])
        XCTAssertEqual(names, ["org/mine-only", "org/reviews-only"])
    }

    func testNamesSortCaseInsensitively() {
        XCTAssertEqual(RepoScope.names(reviews: ["org/Zebra", "org/apple"], mine: []),
                       ["org/apple", "org/Zebra"])
    }

    func testNamesOfNothingIsEmpty() {
        XCTAssertTrue(RepoScope.names(reviews: [], mine: []).isEmpty)
    }

    // MARK: - Display names

    func testShortNameDropsTheOwner() {
        XCTAssertEqual(RepoScope.shortName("acme/widgets-web"), "widgets-web")
    }

    func testShortNameTolleratesNoSlash() {
        XCTAssertEqual(RepoScope.shortName("bare"), "bare")
    }

    /// Two owners can have repos with the same short name. Filtering must key
    /// on the full path, or picking one would silently show both.
    func testSameShortNameUnderDifferentOwnersStaysDistinct() {
        let mixed = [Row(repo: "alice/tools", number: 1),
                     Row(repo: "bob/tools", number: 2)]
        XCTAssertEqual(RepoScope.shortName("alice/tools"),
                       RepoScope.shortName("bob/tools"),
                       "short names collide, which is the hazard")

        XCTAssertEqual(RepoScope.apply("alice/tools", to: mixed, repoOf: \.repo)
                        .map(\.number), [1])
        XCTAssertEqual(RepoScope.names(reviews: mixed.map(\.repo), mine: []).count, 2,
                       "both must still be offered separately")
    }
}
