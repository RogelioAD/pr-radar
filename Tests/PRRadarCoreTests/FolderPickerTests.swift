import XCTest
@testable import PRRadarCore

final class FolderPickerTests: XCTestCase {

    // MARK: - What to offer

    /// `.git`, `.build`, `.Trash` and the rest are machinery, and nobody keeps
    /// their clones in one.
    func testDotDirectoriesAreNotOffered() {
        XCTAssertEqual(FolderPicker.visible([".git", "Developer", ".build", "Code"]),
                       ["Code", "Developer"])
    }

    /// Finder's ordering, so the menu matches the window the user would
    /// otherwise be looking in.
    func testEntriesAreSortedTheWayFinderSortsThem() {
        XCTAssertEqual(FolderPicker.visible(["repo10", "repo2", "Repo1"]),
                       ["Repo1", "repo2", "repo10"])
    }

    func testAnEmptyListIsEmptyRatherThanAnError() {
        XCTAssertTrue(FolderPicker.visible([]).isEmpty)
    }

    // MARK: - Going up

    func testTheParentIsTheFolderAbove() {
        XCTAssertEqual(FolderPicker.parent(of: "/Users/me/Developer"), "/Users/me")
    }

    /// The way up disappears at the top rather than offering a step that goes
    /// nowhere.
    func testThereIsNoParentOfTheRoot() {
        XCTAssertNil(FolderPicker.parent(of: "/"))
    }

    func testTheParentOfATopLevelFolderIsTheRoot() {
        XCTAssertEqual(FolderPicker.parent(of: "/Users"), "/")
    }

    func testARelativePathHasNoParentRatherThanAGuessedOne() {
        XCTAssertNil(FolderPicker.parent(of: "Developer"))
        XCTAssertNil(FolderPicker.parent(of: ""))
    }

    /// A trailing slash must not cost a level.
    func testATrailingSlashDoesNotChangeTheParent() {
        XCTAssertEqual(FolderPicker.parent(of: "/Users/me/Developer/"), "/Users/me")
    }

    // MARK: - Normalising

    /// The path is stored, compared and displayed. Disagreeing about the slash
    /// would make one place look like two.
    func testATrailingSlashIsStripped() {
        XCTAssertEqual(FolderPicker.normalized("/w/"), "/w")
        XCTAssertEqual(FolderPicker.normalized("/w"), "/w")
    }

    func testTheRootKeepsItsOnlySlash() {
        XCTAssertEqual(FolderPicker.normalized("/"), "/")
    }

    func testATildeIsExpanded() {
        XCTAssertEqual(FolderPicker.normalized("~/Developer"),
                       NSHomeDirectory() + "/Developer")
    }

    // MARK: - Writing it down

    func testHomeIsWrittenAsATilde() {
        XCTAssertEqual(FolderPicker.display(NSHomeDirectory()), "~")
        XCTAssertEqual(FolderPicker.display(NSHomeDirectory() + "/Developer"), "~/Developer")
    }

    /// A folder that merely starts with the same letters as home is not inside
    /// it, and must not be abbreviated as though it were.
    func testAPathThatOnlyLooksLikeHomeIsLeftAlone() {
        XCTAssertEqual(FolderPicker.display(NSHomeDirectory() + "-backup"),
                       NSHomeDirectory() + "-backup")
    }

    func testAPathOutsideHomeIsShownWhole() {
        XCTAssertEqual(FolderPicker.display("/Volumes/Work/src"), "/Volumes/Work/src")
    }

    func testTheNameIsTheLastComponent() {
        XCTAssertEqual(FolderPicker.name(of: "/Users/me/Developer"), "Developer")
        XCTAssertEqual(FolderPicker.name(of: "/Users/me/Developer/"), "Developer")
        XCTAssertEqual(FolderPicker.name(of: "/"), "/")
    }

    // MARK: - The line under the picker

    /// You are not choosing a folder, you are choosing the folder your clones
    /// are in, and the count is the only way to know you have found it.
    func testTheSummaryCountsClones() {
        XCTAssertEqual(FolderPicker.summary(cloneCount: 14, subfolderCount: 20),
                       "14 clones here.")
        XCTAssertEqual(FolderPicker.summary(cloneCount: 1, subfolderCount: 3),
                       "1 clone here.")
    }

    /// Said plainly, so a plausible-looking wrong choice does not sit there
    /// until the first review fails.
    func testNoClonesSaysSoAndPointsFurtherDown() {
        XCTAssertEqual(FolderPicker.summary(cloneCount: 0, subfolderCount: 8),
                       "No clones directly in here — try one of its subfolders.")
    }

    /// Suggesting subfolders when there are none would be advice that cannot be
    /// taken.
    func testAnEmptyFolderDoesNotSuggestSubfoldersItDoesNotHave() {
        XCTAssertEqual(FolderPicker.summary(cloneCount: 0, subfolderCount: 0),
                       "Nothing in here.")
    }
}
