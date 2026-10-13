import XCTest
@testable import PRRadarCore

/// Reading `git merge-tree --write-tree --name-only`.
///
/// The count on the row comes from here, and the one answer this must never
/// give is a confident zero: GitHub has already said the branch is dirty, so
/// "conflicts · 0 files" is the row contradicting itself, and it would do it
/// on exactly the repositories where something went wrong.
final class MergeTreeTests: XCTestCase {

    func testACleanMergeHasNothingAfterTheTreeOid() {
        let paths = MergeTree.conflictedPaths(
            exitCode: 0, output: "4b825dc642cb6eb9a060e54bf8d69288fbee4904\n")
        XCTAssertEqual(paths, [])
    }

    func testConflictedPathsAreTheLinesAfterTheOid() {
        let output = """
        a1b2c3d4e5f60718293a4b5c6d7e8f9012345678
        Cargo.lock
        rust/src/effects.rs
        ios/App/HomeView.swift

        Auto-merging rust/src/effects.rs
        CONFLICT (content): Merge conflict in rust/src/effects.rs
        """
        XCTAssertEqual(MergeTree.conflictedPaths(exitCode: 1, output: output),
                       ["Cargo.lock", "rust/src/effects.rs", "ios/App/HomeView.swift"])
    }

    /// The blank line ends the list. Everything after it is git explaining
    /// itself, and counting those as files would roughly double every number.
    func testTheProseAfterTheBlankLineIsNotAFile() {
        let output = """
        a1b2c3d
        one.swift

        CONFLICT (content): Merge conflict in one.swift
        Auto-merging two.swift
        """
        XCTAssertEqual(MergeTree.conflictedPaths(exitCode: 1, output: output),
                       ["one.swift"])
    }

    func testAnUnanswerableQuestionIsNilRatherThanClean() {
        XCTAssertNil(MergeTree.conflictedPaths(
            exitCode: 128, output: "fatal: not a valid object name: origin/main"))
        XCTAssertNil(MergeTree.conflictedPaths(exitCode: 129, output: "usage: git"))
    }

    /// Checked against a real git, not assumed: asking about a ref the clone
    /// has never fetched exits **1** — the same code a genuine conflict uses —
    /// and explains itself on stderr, which this never sees. So the empty-names
    /// rule is the only thing separating the two, and without it every
    /// unfetched base would be reported as a conflict in zero files.
    func testAnUnfetchedBaseLooksExactlyLikeAConflictExceptForTheNames() {
        // What git actually prints: nothing on stdout, exit 1.
        XCTAssertNil(MergeTree.conflictedPaths(exitCode: 1, output: ""))
    }

    /// Exit 1 says it conflicted. Naming nothing is a contradiction, and the
    /// row must show its old wording rather than "0 files".
    func testConflictedWithNoNamesIsUnknownRatherThanZero() {
        XCTAssertNil(MergeTree.conflictedPaths(exitCode: 1, output: "a1b2c3d\n"))
        XCTAssertNil(MergeTree.conflictedPaths(exitCode: 1, output: "a1b2c3d\n\nnotes"))
    }

    func testEmptyOutputIsUnknown() {
        XCTAssertNil(MergeTree.conflictedPaths(exitCode: 1, output: ""))
    }

    func testWindowsLineEndingsAreRead() {
        XCTAssertEqual(
            MergeTree.conflictedPaths(exitCode: 1, output: "a1b2c3d\r\none.swift\r\n"),
            ["one.swift"])
    }

    /// `--name-only` is what keeps this cheap: without it a real conflict
    /// prints the conflicted blobs, which is the difference between a line and
    /// a megabyte on the sixty-second poll.
    func testTheQuestionAsksForNamesAndWritesNoIndex() {
        let arguments = MergeTree.arguments(head: "HEAD", base: "origin/main")
        XCTAssertEqual(arguments,
                       ["merge-tree", "--write-tree", "--name-only", "HEAD", "origin/main"])
    }

    /// A clean merge and an unanswerable question are different answers, and
    /// the caller has to be able to tell them apart.
    ///
    /// This is the distinction that shipped broken. The parser was right —
    /// clean is `[]`, unknown is nil — and the caller stored both, so a branch
    /// GitHub called dirty that merged cleanly against a *stale* local base
    /// came out as "Resolve conflicts · 0 files". The row contradicted itself
    /// and, worse, looked calmer than the truth. Nothing about this type was
    /// wrong; the test is here because the shape it returns is the whole basis
    /// of the fix.
    func testCleanAndUnknownAreDifferentAnswers() {
        XCTAssertEqual(MergeTree.conflictedPaths(exitCode: 0, output: "a1b2c3d\n"), [],
                       "a clean merge is an empty list, not nil")
        XCTAssertNil(MergeTree.conflictedPaths(exitCode: 1, output: ""),
                     "an unanswerable question is nil, not an empty list")

        // The caller's rule, stated here because it is what was missing:
        // on a pull request GitHub calls dirty, only a non-empty list is a
        // count. Both of the above mean "no number".
        for answer in [MergeTree.conflictedPaths(exitCode: 0, output: "a1b2c3d\n"),
                       MergeTree.conflictedPaths(exitCode: 1, output: "")] {
            XCTAssertTrue(answer?.isEmpty ?? true,
                          "neither may be shown as a count on a dirty row")
        }
    }

    /// A path with a space is a path, not two.
    func testAPathWithSpacesSurvives() {
        XCTAssertEqual(
            MergeTree.conflictedPaths(exitCode: 1, output: "a1b2c3d\nios/My File.swift\n"),
            ["ios/My File.swift"])
    }
}
