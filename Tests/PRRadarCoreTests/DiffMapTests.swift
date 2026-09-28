import XCTest
@testable import PRRadarCore

final class DiffMapTests: XCTestCase {

    /// One file, one hunk starting at line 10 on the right.
    ///
    ///   10  context
    ///   11  added
    ///   12  added
    ///   13  context
    private let simple = """
    diff --git a/Sources/Foo.swift b/Sources/Foo.swift
    index 1111111..2222222 100644
    --- a/Sources/Foo.swift
    +++ b/Sources/Foo.swift
    @@ -10,3 +10,4 @@ final class Foo {
     context
    +added one
    +added two
     trailing context
    """

    // MARK: - What can take a comment

    func testAddedLinesAreCommentable() {
        let map = DiffMap.parse(unifiedDiff: simple)
        XCTAssertTrue(map.isCommentable(path: "Sources/Foo.swift", line: 11))
        XCTAssertTrue(map.isCommentable(path: "Sources/Foo.swift", line: 12))
    }

    /// GitHub will take a comment on an unchanged line inside a hunk, and a
    /// finding about code the PR merely moved past belongs there.
    func testContextLinesInsideAHunkAreCommentable() {
        let map = DiffMap.parse(unifiedDiff: simple)
        XCTAssertTrue(map.isCommentable(path: "Sources/Foo.swift", line: 10))
        XCTAssertTrue(map.isCommentable(path: "Sources/Foo.swift", line: 13))
    }

    /// A removed line exists only on the left, and anchoring a RIGHT-side
    /// comment to it is rejected — which would cost the whole review, not just
    /// that one thread.
    func testRemovedLinesDoNotConsumeRightSideNumbers() {
        let diff = """
        diff --git a/F.swift b/F.swift
        --- a/F.swift
        +++ b/F.swift
        @@ -1,3 +1,2 @@
         kept
        -deleted
        +replacement
        """
        let map = DiffMap.parse(unifiedDiff: diff)
        // right side is: 1 kept, 2 replacement
        XCTAssertTrue(map.isCommentable(path: "F.swift", line: 1))
        XCTAssertTrue(map.isCommentable(path: "F.swift", line: 2))
        XCTAssertFalse(map.isCommentable(path: "F.swift", line: 3))
    }

    func testALineOutsideEveryHunkIsNotCommentable() {
        let map = DiffMap.parse(unifiedDiff: simple)
        XCTAssertFalse(map.isCommentable(path: "Sources/Foo.swift", line: 400))
        XCTAssertFalse(map.isCommentable(path: "Sources/Foo.swift", line: 1))
    }

    func testAnUnknownPathIsNotCommentable() {
        let map = DiffMap.parse(unifiedDiff: simple)
        XCTAssertFalse(map.isCommentable(path: "Sources/Other.swift", line: 11))
    }

    // MARK: - Several hunks and files

    func testEveryHunkOfEveryFileIsMapped() {
        let diff = """
        diff --git a/A.swift b/A.swift
        --- a/A.swift
        +++ b/A.swift
        @@ -1,1 +1,2 @@
         one
        +two
        @@ -50,1 +51,2 @@
         fifty
        +fiftyone
        diff --git a/B.swift b/B.swift
        --- a/B.swift
        +++ b/B.swift
        @@ -5,1 +5,2 @@
         five
        +six
        """
        let map = DiffMap.parse(unifiedDiff: diff)
        XCTAssertEqual(map.paths, ["A.swift", "B.swift"])
        XCTAssertTrue(map.isCommentable(path: "A.swift", line: 2))
        XCTAssertTrue(map.isCommentable(path: "A.swift", line: 52))
        XCTAssertFalse(map.isCommentable(path: "A.swift", line: 30))
        XCTAssertTrue(map.isCommentable(path: "B.swift", line: 6))
    }

    /// A rename anchors to where the file ends up, because that is the name a
    /// RIGHT-side comment is addressed to.
    func testARenameIsMappedUnderItsNewName() {
        let diff = """
        diff --git a/Old.swift b/New.swift
        similarity index 90%
        rename from Old.swift
        rename to New.swift
        --- a/Old.swift
        +++ b/New.swift
        @@ -1,1 +1,2 @@
         one
        +two
        """
        let map = DiffMap.parse(unifiedDiff: diff)
        XCTAssertEqual(map.paths, ["New.swift"])
    }

    /// A deleted file has no right side, so nothing in it can be commented on.
    func testADeletedFileContributesNothing() {
        let diff = """
        diff --git a/Gone.swift b/Gone.swift
        deleted file mode 100644
        --- a/Gone.swift
        +++ /dev/null
        @@ -1,2 +0,0 @@
        -one
        -two
        """
        XCTAssertTrue(DiffMap.parse(unifiedDiff: diff).paths.isEmpty)
    }

    func testAnEmptyDiffIsAnEmptyMapRatherThanACrash() {
        XCTAssertTrue(DiffMap.parse(unifiedDiff: "").paths.isEmpty)
        XCTAssertTrue(DiffMap.parse(unifiedDiff: "not a diff at all").paths.isEmpty)
    }

    // MARK: - Snapping

    func testAnExactHitSnapsToItself() {
        let map = DiffMap.parse(unifiedDiff: simple)
        XCTAssertEqual(map.snap(path: "Sources/Foo.swift", line: 11), 11)
    }

    /// The point of snapping is to rescue an off-by-a-line anchor.
    func testANearMissSnapsToTheNearestLineInTheSameHunk() {
        let diff = """
        diff --git a/F.swift b/F.swift
        --- a/F.swift
        +++ b/F.swift
        @@ -20,1 +20,2 @@
         twenty
        +twentyone
        """
        let map = DiffMap.parse(unifiedDiff: diff)
        XCTAssertEqual(map.snap(path: "F.swift", line: 22), 21)
    }

    /// Not to reattach a finding to an unrelated change, where it would read as
    /// a confident comment about the wrong code.
    func testSnappingRefusesToCrossIntoAnotherHunk() {
        let diff = """
        diff --git a/F.swift b/F.swift
        --- a/F.swift
        +++ b/F.swift
        @@ -1,1 +1,2 @@
         one
        +two
        @@ -100,1 +101,2 @@
         hundred
        +hundredone
        """
        let map = DiffMap.parse(unifiedDiff: diff)
        XCTAssertNil(map.snap(path: "F.swift", line: 50))
    }

    func testSnappingRespectsItsBound() {
        let diff = """
        diff --git a/F.swift b/F.swift
        --- a/F.swift
        +++ b/F.swift
        @@ -20,1 +20,2 @@
         twenty
        +twentyone
        """
        let map = DiffMap.parse(unifiedDiff: diff)
        XCTAssertNil(map.snap(path: "F.swift", line: 40, within: 3))
    }

    func testSnappingAnUnknownPathIsNil() {
        XCTAssertNil(DiffMap.parse(unifiedDiff: simple).snap(path: "Nope.swift", line: 1))
    }

    // MARK: - Header parsing

    func testTheHunkHeaderYieldsTheNewSideStart() {
        XCTAssertEqual(DiffMap.newStart(ofHunkHeader: "@@ -12,7 +34,9 @@ func thing() {"), 34)
        XCTAssertEqual(DiffMap.newStart(ofHunkHeader: "@@ -1 +1 @@"), 1)
        XCTAssertNil(DiffMap.newStart(ofHunkHeader: "@@ nonsense @@"))
    }

    func testGitPathPrefixesAreStripped() {
        XCTAssertEqual(DiffMap.strippingPrefix("b/Sources/Foo.swift"), "Sources/Foo.swift")
        XCTAssertEqual(DiffMap.strippingPrefix("Sources/Foo.swift"), "Sources/Foo.swift")
    }
}
