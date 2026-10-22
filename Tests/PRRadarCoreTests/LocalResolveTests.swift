import XCTest
@testable import PRRadarCore

/// Resolving a thread from the drawer, before the poll agrees.
final class LocalResolveTests: XCTestCase {

    func thread(_ id: String) -> UnresolvedThread {
        UnresolvedThread(id: id, path: "a.swift", line: 1, isOutdated: false,
                         comments: [UnresolvedThread.Comment(author: "alice",
                                                             body: "why?")],
                         moreComments: 0, excerpt: nil)
    }

    func pr(threads: [String], count: Int? = nil) -> MyPullRequest {
        var item = MyPullRequest(
            repo: "acme/repo", number: 1, title: "t",
            url: URL(string: "https://github.com/acme/repo/pull/1")!,
            isDraft: false, createdAt: Date(), updatedAt: Date(),
            headRefName: "h", baseRefName: "main",
            reviewDecision: .none, mergeBlocker: .blocked, approvals: [],
            awaitingReviewers: [], unresolvedThreadCount: count ?? threads.count,
            totalThreadCount: 9, checks: .empty,
            additions: 1, deletions: 0, changedFiles: 1)
        item.unresolvedThreads = threads.map(thread)
        return item
    }

    func testTheThreadLeavesTheList() {
        let after = pr(threads: ["a", "b", "c"]).resolvingLocally(["b"])
        XCTAssertEqual(after.unresolvedThreads.map(\.id), ["a", "c"])
    }

    /// A row showing two threads over a chip saying three is the drawer
    /// disagreeing with itself, and the chip is the half people read.
    func testTheCountMovesWithTheList() {
        let after = pr(threads: ["a", "b", "c"]).resolvingLocally(["b"])
        XCTAssertEqual(after.unresolvedThreadCount, 2)
    }

    /// The count is of every unresolved thread; the list only holds the ones
    /// GitHub gave an id to. They are not the same number to begin with, so
    /// the count moves by how many actually went.
    func testTheCountIsNotJustTheListsLength() {
        // Five unresolved, only three of them with ids.
        let after = pr(threads: ["a", "b", "c"], count: 5).resolvingLocally(["a"])
        XCTAssertEqual(after.unresolvedThreads.count, 2)
        XCTAssertEqual(after.unresolvedThreadCount, 4)
    }

    func testResolvingNothingChangesNothing() {
        let before = pr(threads: ["a", "b"])
        XCTAssertEqual(before.resolvingLocally([]), before)
        XCTAssertEqual(before.resolvingLocally(["not-here"]), before)
    }

    func testResolvingEverythingEmptiesIt() {
        let after = pr(threads: ["a", "b"]).resolvingLocally(["a", "b"])
        XCTAssertTrue(after.unresolvedThreads.isEmpty)
        XCTAssertEqual(after.unresolvedThreadCount, 0)
    }

    /// Never below zero, whatever the two numbers were doing.
    func testTheCountNeverGoesNegative() {
        let after = pr(threads: ["a", "b"], count: 1).resolvingLocally(["a", "b"])
        XCTAssertEqual(after.unresolvedThreadCount, 0)
    }

    /// The whole point of taking it out of the list: a filter that asks for
    /// open threads stops matching once the last one is answered.
    func testTheOpenThreadsFilterAgrees() {
        let resolved = pr(threads: ["a"]).resolvingLocally(["a"])
        XCTAssertFalse(MyPRFilter.openThreads.matches(resolved))
        XCTAssertTrue(MyPRFilter.openThreads.matches(pr(threads: ["a"])))
    }
}
