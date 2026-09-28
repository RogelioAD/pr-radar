import XCTest
@testable import PRRadarCore

/// Reading the threads behind `3 open`, rather than only counting them.
final class UnresolvedThreadTests: XCTestCase {

    func testACommentIsTidiedForARow() {
        XCTAssertEqual(UnresolvedThread.trimmed("\n\n  nit: typo  \n"), "nit: typo")
        XCTAssertEqual(UnresolvedThread.trimmed("one\r\ntwo"), "one\ntwo")
    }

    /// A pasted stack trace must not push the rest of the drawer off the screen.
    func testALongCommentIsCutAtAWord() {
        let body = String(repeating: "alpha ", count: 200)
        let trimmed = UnresolvedThread.trimmed(body)
        XCTAssertTrue(trimmed.hasSuffix("…"))
        XCTAssertLessThanOrEqual(trimmed.count, UnresolvedThread.bodyLimit + 1)
        // Cut at a space, so it does not end mid-token.
        XCTAssertFalse(trimmed.dropLast().hasSuffix("alph"))
    }

    func testAShortCommentIsLeftAlone() {
        XCTAssertEqual(UnresolvedThread.trimmed("Looks good"), "Looks good")
    }

    func testAThreadSaysWhereItIs() {
        let thread = UnresolvedThread(id: "T1", path: "crates/app/src/lib.rs", line: 209,
                                      isOutdated: false, comments: [], moreComments: 0)
        XCTAssertEqual(thread.location, "lib.rs:209")
    }

    /// A thread on a whole file has no line, and says the file rather than
    /// inventing one.
    func testAThreadWithNoLineStillSaysTheFile() {
        let thread = UnresolvedThread(id: "T1", path: "README.md", line: nil,
                                      isOutdated: false, comments: [], moreComments: 0)
        XCTAssertEqual(thread.location, "README.md")
    }

    func testAThreadWithNoPathSaysNothing() {
        let thread = UnresolvedThread(id: "T1", path: nil, line: nil,
                                      isOutdated: false, comments: [], moreComments: 0)
        XCTAssertNil(thread.location)
    }

    // MARK: Built from what GitHub sends

    private func inbox(_ node: String) -> [MyPullRequest] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = #"{"mine":{"issueCount":1,"nodes":[\#(node)]}}"#
        let result = try! decoder.decode(MyPRPayload.self, from: Data(payload.utf8)).mine
        return MyPRInbox().build(from: result)
    }

    func testOnlyUnresolvedThreadsAreCarried() {
        let prs = inbox(Self.payload)
        let pr = try! XCTUnwrap(prs.first)
        XCTAssertEqual(pr.unresolvedThreadCount, 2)
        XCTAssertEqual(pr.unresolvedThreads.count, 2)
        XCTAssertFalse(pr.unresolvedThreads.contains { $0.id == "T_resolved" })
    }

    /// A thread GitHub gave no id to cannot keep its place across a refresh, so
    /// it is counted and not listed rather than reshuffling every sixty seconds.
    func testAThreadWithNoIdIsCountedButNotListed() {
        let prs = inbox(Self.payload)
        let pr = try! XCTUnwrap(prs.first)
        XCTAssertEqual(pr.unresolvedThreadCount, 2)
        XCTAssertTrue(pr.unresolvedThreads.allSatisfy { !$0.id.isEmpty })
    }

    func testCommentsBeyondTheFetchedOnesAreCounted() {
        let pr = try! XCTUnwrap(inbox(Self.payload).first)
        let thread = try! XCTUnwrap(pr.unresolvedThreads.first { $0.id == "T_busy" })
        XCTAssertEqual(thread.comments.count, 2)
        XCTAssertEqual(thread.moreComments, 5)
    }

    func testAnAuthorlessCommentStillHasSomebodyToAttributeItTo() {
        let pr = try! XCTUnwrap(inbox(Self.payload).first)
        let thread = try! XCTUnwrap(pr.unresolvedThreads.first { $0.id == "T_busy" })
        XCTAssertEqual(thread.comments.last?.author, "someone")
    }

    func testOutdatedIsCarriedThrough() {
        let pr = try! XCTUnwrap(inbox(Self.payload).first)
        XCTAssertTrue(pr.unresolvedThreads.first { $0.id == "T_old" }?.isOutdated == true)
        XCTAssertTrue(pr.unresolvedThreads.first { $0.id == "T_busy" }?.isOutdated == false)
    }

    // MARK: The code the thread is about

    /// GitHub's `diffHunk` is a bare fragment: one `@@` header and the lines
    /// under it, with no `+++` file header, which is why it needs a parser of
    /// its own rather than the one that reads a whole diff.
    func testTheHunkIsReadFromWhatGitHubSends() {
        let pr = try! XCTUnwrap(inbox(Self.payload).first)
        let thread = try! XCTUnwrap(pr.unresolvedThreads.first { $0.id == "T_busy" })
        let excerpt = try! XCTUnwrap(thread.excerpt)

        XCTAssertEqual(excerpt.path, "src/lib.rs")
        XCTAssertEqual(excerpt.focus, 209)
        XCTAssertTrue(excerpt.lines.contains { $0.text.contains("RESERVED") })
    }

    /// Numbered from the `@@` header's right-hand side, so the gutter agrees
    /// with the line GitHub says the comment is on.
    func testTheGutterAgreesWithTheLineTheCommentIsOn() {
        let pr = try! XCTUnwrap(inbox(Self.payload).first)
        let excerpt = try! XCTUnwrap(
            pr.unresolvedThreads.first { $0.id == "T_busy" }?.excerpt)
        let added = try! XCTUnwrap(excerpt.lines.first { $0.kind == .added })
        XCTAssertEqual(added.number, 209)
        XCTAssertTrue(excerpt.isFocused(209))
    }

    func testARemovedLineIsKeptAndUnnumbered() {
        let pr = try! XCTUnwrap(inbox(Self.payload).first)
        let excerpt = try! XCTUnwrap(
            pr.unresolvedThreads.first { $0.id == "T_busy" }?.excerpt)
        let removed = try! XCTUnwrap(excerpt.lines.first { $0.kind == .removed })
        XCTAssertNil(removed.number)
    }

    /// The tail is kept, not the head: the comment is anchored to the last line
    /// of the hunk, and lead-in that pushes it off the bottom helps nobody.
    func testALongHunkKeepsTheEndTheCommentIsOn() {
        let body = (1...30).map { " line \($0)" }.joined(separator: "\n")
        let excerpt = try! XCTUnwrap(
            DiffExcerpt.parse(diffHunk: "@@ -1,30 +1,30 @@\n" + body,
                              path: "a.rs", line: 30, keepingLast: 4))
        XCTAssertEqual(excerpt.lines.count, 4)
        XCTAssertEqual(excerpt.lines.last?.number, 30)
        XCTAssertEqual(excerpt.lines.first?.number, 27)
    }

    /// A thread on a file rather than a line has no hunk, and the comments are
    /// still worth showing without one.
    func testAThreadWithNoHunkStillCarriesItsComments() {
        let pr = try! XCTUnwrap(inbox(Self.payload).first)
        let thread = try! XCTUnwrap(pr.unresolvedThreads.first { $0.id == "T_old" })
        XCTAssertNil(thread.excerpt)
        XCTAssertEqual(thread.comments.count, 1)
    }

    func testAnUnreadableHunkIsNoHunkRatherThanAnEmptyOne() {
        XCTAssertNil(DiffExcerpt.parse(diffHunk: "", path: "a.rs", line: 1))
        XCTAssertNil(DiffExcerpt.parse(diffHunk: "@@ -1,2 +1,2 @@", path: "a.rs", line: 1))
    }

    private static let payload = """
    {
      "id": "PR1", "number": 7, "title": "t", "url": "https://example.com/7",
      "isDraft": false, "createdAt": "2026-09-01T00:00:00Z",
      "updatedAt": "2026-09-01T00:00:00Z",
      "headRefName": "feat", "baseRefName": "main",
      "repository": {"nameWithOwner": "acme/app"},
      "reviewThreads": {
        "totalCount": 3,
        "nodes": [
          {"id": "T_busy", "isResolved": false, "isOutdated": false,
           "path": "src/lib.rs", "line": 209,
           "comments": {"totalCount": 7, "nodes": [
             {"author": {"login": "ana"}, "body": "  why not a guard?  "},
             {"body": "because of the ordering"}
           ]},
           "hunk": {"nodes": [
             {"diffHunk": "@@ -204,6 +207,9 @@ fn resolve()\\n     let mut parts = path.split(0);\\n     let seg = parts.next()?;\\n-    if seg.is_empty() {\\n+    if RESERVED.contains(seg) {"}
           ]}},
          {"id": "T_old", "isResolved": false, "isOutdated": true,
           "path": "src/old.rs", "line": 4,
           "comments": {"totalCount": 1, "nodes": [
             {"author": {"login": "bo"}, "body": "stale"}
           ]}},
          {"id": "T_resolved", "isResolved": true, "isOutdated": false,
           "path": "src/done.rs", "line": 1,
           "comments": {"totalCount": 1, "nodes": []}}
        ]
      }
    }
    """
}
