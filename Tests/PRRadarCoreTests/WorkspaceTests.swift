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
    // MARK: - The throwaway review checkout

    func testAWorktreeNameCarriesThePrefixThatTheSweepLooksFor() {
        let name = Workspace.worktreeName(forPR: 812, token: "52FD6D0D")
        XCTAssertEqual(name, "pr-radar-812-52FD6D0D")
        XCTAssertTrue(Workspace.isWorktree(path: "/tmp/" + name))
    }

    /// The whole point of the shared prefix: whatever the creating side makes,
    /// the reaper has to recognise. A regression here is silent and the symptom
    /// is a slowly filling disk.
    func testEveryNameTheAppCreatesIsOneTheSweepWillRecognise() {
        for number in [1, 42, 812, 99_999] {
            let path = "/var/folders/xx/T/"
                + Workspace.worktreeName(forPR: number, token: "ABCD1234")
            XCTAssertTrue(Workspace.isWorktree(path: path), "missed \(path)")
        }
    }

    func testSomebodyElsesCheckoutIsNotOursToDelete() {
        XCTAssertFalse(Workspace.isWorktree(path: "/tmp/elevation-church-mobile-rust"))
        XCTAssertFalse(Workspace.isWorktree(path: "/tmp/pr-radar/my-real-clone"))
    }

    /// Matched on the last component only, so a temporary directory that
    /// happens to live inside a folder named like ours does not cost somebody
    /// every checkout underneath it.
    func testAParentFolderNamedLikeOursDoesNotCondemnWhatIsInsideIt() {
        XCTAssertFalse(Workspace.isWorktree(path: "/Users/me/pr-radar-stuff/important-clone"))
    }

    // MARK: - Deciding what the sweep may delete

    /// The one that matters: `make run` puts a second copy alongside the
    /// installed one, sharing a temporary directory. A launching copy must not
    /// delete a worktree the other copy is reviewing in.
    func testAWorktreeAnotherCopyIsStillUsingIsNeverDeleted() {
        XCTAssertFalse(Workspace.isReapable(.live, age: 0))
        XCTAssertFalse(Workspace.isReapable(.live, age: 86_400))
    }

    /// The leak this exists for: the owning process was killed, so the `defer`
    /// that removes the tree never ran. Reaped at once, whatever its age —
    /// waiting out a grace period would miss it in the commonest case of all,
    /// an install that relaunches seconds later.
    func testAWorktreeWhoseOwnerIsGoneIsReapedImmediately() {
        XCTAssertTrue(Workspace.isReapable(.abandoned, age: 1))
    }

    /// Written by a build from before the marker existed: nothing links it to a
    /// process, so age is the only evidence there is.
    func testAnUnmarkedWorktreeIsSpAredUntilItIsTooOldToBeLive() {
        XCTAssertFalse(Workspace.isReapable(.unmarked, age: 60))
        XCTAssertFalse(Workspace.isReapable(.unmarked, age: 15 * 60))
        XCTAssertTrue(Workspace.isReapable(.unmarked, age: 31 * 60))
    }

    /// The grace period has to clear the fifteen-minute review timeout, or the
    /// sweep could delete a live unmarked checkout.
    func testTheGracePeriodOutlastsTheLongestPossibleReview() {
        XCTAssertFalse(Workspace.isReapable(.unmarked, age: 15 * 60 + 1))
    }

}
