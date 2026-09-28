import XCTest
@testable import PRRadarCore

final class WorkspaceTests: XCTestCase {

    func testTheFlatLayoutIsTriedFirstBecauseItIsWhatMostPeopleHave() {
        XCTAssertEqual(Workspace.candidates(root: "/Users/me/Developer", repo: "acme/repo").first,
                       "/Users/me/Developer/repo")
    }

    func testTheOwnerNestedAndHyphenatedLayoutsAreAlsoOffered() {
        let candidates = Workspace.candidates(root: "/w", repo: "acme/repo")
        XCTAssertEqual(candidates, ["/w/repo", "/w/acme/repo", "/w/acme-repo"])
    }

    func testATrailingSlashOnTheRootDoesNotDoubleUp() {
        XCTAssertEqual(Workspace.candidates(root: "/w/", repo: "acme/repo").first, "/w/repo")
    }

    /// The path comes from a settings field, where a tilde is what people type.
    func testATildeIsExpanded() {
        let first = Workspace.candidates(root: "~/Developer", repo: "acme/repo").first
        XCTAssertEqual(first, NSHomeDirectory() + "/Developer/repo")
    }

    func testSomethingThatIsNotOwnerSlashRepoOffersNothing() {
        XCTAssertTrue(Workspace.candidates(root: "/w", repo: "repo").isEmpty)
        XCTAssertTrue(Workspace.candidates(root: "/w", repo: "a/b/c").isEmpty)
    }

    func testAnEmptyRootOffersNothingRatherThanTheFilesystemRoot() {
        XCTAssertTrue(Workspace.candidates(root: "", repo: "acme/repo").isEmpty)
    }

    /// Its own ref namespace cannot collide with a branch the user has, does not
    /// clutter their branch list, and makes it obvious who left it there.
    func testTheFetchedHeadLandsInPRRadarsOwnRefNamespace() {
        XCTAssertEqual(Workspace.ref(forPR: 12), "refs/pr-radar/12")
        XCTAssertEqual(Workspace.fetchRefspec(forPR: 12), "pull/12/head:refs/pr-radar/12")
    }
}

// MARK: - Identifying a checkout by its remote

/// Matching a checkout to a pull request by the *name of its folder* fails on
/// the commonest real layout there is: a worktrees directory, where every
/// checkout is named after its branch and not one of them is named after the
/// repository. The remote is what a checkout says about itself.
extension WorkspaceTests {

    func testAnHTTPSRemoteNamesItsRepo() {
        XCTAssertEqual(
            Workspace.repoSlug(fromRemote: "https://github.com/acme/repo.git"),
            "acme/repo")
        XCTAssertEqual(
            Workspace.repoSlug(fromRemote: "https://github.com/acme/repo"),
            "acme/repo")
    }

    func testAnSCPStyleRemoteNamesItsRepo() {
        XCTAssertEqual(
            Workspace.repoSlug(fromRemote: "git@github.com:acme/repo.git"),
            "acme/repo")
    }

    func testAnSSHURLRemoteNamesItsRepo() {
        XCTAssertEqual(
            Workspace.repoSlug(fromRemote: "ssh://git@github.com/acme/repo.git"),
            "acme/repo")
    }

    /// `git remote get-url` hands back a trailing newline.
    func testSurroundingWhitespaceIsIgnored() {
        XCTAssertEqual(
            Workspace.repoSlug(fromRemote: "  https://github.com/acme/repo.git\n"),
            "acme/repo")
    }

    func testATrailingSlashIsIgnored() {
        XCTAssertEqual(
            Workspace.repoSlug(fromRemote: "https://github.com/acme/repo/"),
            "acme/repo")
    }

    /// A self-hosted instance can serve repos below a path prefix, and the last
    /// two segments are still the answer.
    func testAPathPrefixDoesNotBreakIt() {
        XCTAssertEqual(
            Workspace.repoSlug(fromRemote: "https://git.example.com/scm/acme/repo.git"),
            "acme/repo")
    }

    func testSomethingThatIsNotARemoteNamesNothing() {
        XCTAssertNil(Workspace.repoSlug(fromRemote: ""))
        XCTAssertNil(Workspace.repoSlug(fromRemote: "not a url"))
        XCTAssertNil(Workspace.repoSlug(fromRemote: "https://github.com/acme"))
    }

    /// GitHub treats repository names case-insensitively, and a capital letter
    /// in a remote is not a reason to decide this is a different project.
    func testMatchingIgnoresCaseTheWayGitHubDoes() {
        XCTAssertTrue(Workspace.remote("https://github.com/Acme/Repo.git",
                                       names: "acme/repo"))
        XCTAssertFalse(Workspace.remote("https://github.com/acme/other.git",
                                        names: "acme/repo"))
    }

    /// The case that sent me here: a worktree named after its branch, whose
    /// remote is the only thing that says which repository it belongs to.
    func testAWorktreeNamedAfterItsBranchIsStillMatched() {
        XCTAssertTrue(Workspace.remote(
            "https://github.com/elevationchurch/elevation-church-mobile-rust.git",
            names: "elevationchurch/elevation-church-mobile-rust"))
    }
}
