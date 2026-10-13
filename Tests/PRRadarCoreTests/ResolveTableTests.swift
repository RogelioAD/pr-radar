import XCTest
@testable import PRRadarCore

/// The rules PR Radar applies to a run's answer rather than asking for.
///
/// Everything here guards something a run could get wrong silently: a thread
/// closed that nobody answered, a reply posted against an id that means
/// nothing, a sha cited that is not on the remote. The framing asks for all of
/// it politely. This is the part that does not ask.
final class ResolveTableTests: XCTestCase {

    private func thread(_ id: String) -> UnresolvedThread {
        UnresolvedThread(id: id, path: "A.swift", line: 1, isOutdated: false,
                         comments: [], moreComments: 0)
    }

    private func row(_ id: String,
                     _ disposition: ResolveDisposition = .fix,
                     sha: String? = nil) -> ResolveRow {
        ResolveRow(threadId: id, disposition: disposition,
                   reply: "Fixed in \(sha ?? "nothing")", sha: sha)
    }

    // MARK: - The one that matters most

    /// A thread resolved without being fixed or consciously deferred reads to
    /// every reviewer as handled. `needs-you` means nobody decided anything.
    func testNeedsYouNeverResolvesHoweverConfidentTheRunSounded() {
        XCTAssertFalse(ResolveDisposition.needsYou.mayResolve)
        for other in ResolveDisposition.allCases where other != .needsYou {
            XCTAssertTrue(other.mayResolve, "\(other)")
        }
    }

    /// Even when the run ticked it. The flag is the run's claim; this is the
    /// rule.
    func testANeedsYouRowIsUntickedWhateverTheRunSaid() {
        var claimed = row("T1", .needsYou)
        claimed.isSelected = true
        let table = ResolveTable(threads: [claimed])
            .sanitised(against: [thread("T1")])
        XCTAssertFalse(table.threads[0].isSelected)
        XCTAssertFalse(table.threads[0].mayResolve)
    }

    // MARK: - Ids

    func testAnIDPRRadarNeverSentIsDroppedAndNamed() {
        let table = ResolveTable(threads: [row("T1"), row("INVENTED")])
            .sanitised(against: [thread("T1")])
        XCTAssertEqual(table.threads.map(\.threadId), ["T1"])
        XCTAssertEqual(table.unknown, ["INVENTED"])
    }

    /// The alternative reading of a missing thread is "nothing to do about it",
    /// and that is exactly the silent drop this feature exists to prevent.
    func testAThreadTheRunNeverMentionedIsRecordedRatherThanAssumedFine() {
        let table = ResolveTable(threads: [row("T1")])
            .sanitised(against: [thread("T1"), thread("T2"), thread("T3")])
        XCTAssertEqual(table.missing, ["T2", "T3"])
        XCTAssertEqual(table.selection.total, 1, "it must not claim to have done three")
    }

    // MARK: - Shas

    /// A reply saying "fixed in a1b2c3d" is false until that commit is on the
    /// remote, and false in the one way nobody checks.
    func testAReplyCitingACommitThatWasNeverPushedIsHeldBack() {
        let table = ResolveTable(threads: [row("T1", .fix, sha: "deadbee")])
            .sanitised(against: [thread("T1")], pushedShas: ["a1b2c3d"])
        XCTAssertTrue(table.threads[0].shaIsUnpushed)
        XCTAssertFalse(table.threads[0].isSelected)
        XCTAssertFalse(table.threads[0].mayResolve)
    }

    func testAPushedCommitPassesEvenWhenAbbreviatedDifferently() {
        let short = ResolveTable(threads: [row("T1", .fix, sha: "a1b2c3d")])
            .sanitised(against: [thread("T1")], pushedShas: ["a1b2c3d4e5f6"])
        XCTAssertFalse(short.threads[0].shaIsUnpushed)

        let long = ResolveTable(threads: [row("T1", .fix, sha: "a1b2c3d4e5f6")])
            .sanitised(against: [thread("T1")], pushedShas: ["a1b2c3d"])
        XCTAssertFalse(long.threads[0].shaIsUnpushed)
    }

    /// A triage run cites nothing and pushes nothing; its rows must not all be
    /// held back for failing a check that does not apply.
    func testARunThatPushedNothingIsNotPunishedForCitingNothing() {
        let table = ResolveTable(threads: [row("T1", .disagree)])
            .sanitised(against: [thread("T1")], pushedShas: [])
        XCTAssertFalse(table.threads[0].shaIsUnpushed)
        XCTAssertTrue(table.threads[0].isSelected)
    }

    // MARK: - Counting

    func testTheRowCountsByDisposition() {
        let table = ResolveTable(threads: [
            row("T1", .fix), row("T2", .fix), row("T3", .defer_), row("T4", .needsYou),
        ]).sanitised(against: [thread("T1"), thread("T2"), thread("T3"), thread("T4")])

        XCTAssertEqual(table.count(.fix), 2)
        XCTAssertEqual(table.count(.defer_), 1)
        XCTAssertEqual(table.count(.needsYou), 1)
        XCTAssertEqual(table.selection.chosen, 3)
        XCTAssertEqual(table.selection.total, 4)
    }

    func testAnUntrackedGapIsSurfacedBecauseNothingElseWill() {
        var gap = row("T1", .defer_)
        gap.asanaGap = true
        gap.asanaNote = "Extract the card"
        let table = ResolveTable(threads: [gap, row("T2", .fix)])
            .sanitised(against: [thread("T1"), thread("T2")])
        XCTAssertEqual(table.untrackedGaps.map(\.threadId), ["T1"])
    }

    func testARowWithNothingToSayIsNotPostable() {
        let silent = ResolveRow(threadId: "T1", disposition: .fix, reply: "")
        let table = ResolveTable(threads: [silent]).sanitised(against: [thread("T1")])
        XCTAssertTrue(table.postable.isEmpty, "never resolve a thread without a reply")
    }

    // MARK: - A conflicts run

    /// A conflicts run was never asked about threads, so it has not dropped
    /// any. Holding it to the threads contract would brand every successful
    /// merge "6 not triaged" — a warning about work nobody requested.
    func testAConflictsRunIsNotAccusedOfSkippingThreads() {
        let table = ResolveTable(merge: MergeReport(conflicted: true,
                                                    files: ["Cargo.lock"]))
            .sanitised(against: [thread("T1"), thread("T2")], scope: .conflicts)
        XCTAssertTrue(table.missing.isEmpty)
        XCTAssertTrue(table.unknown.isEmpty)
        XCTAssertTrue(table.threads.isEmpty)
        XCTAssertEqual(table.merge?.files, ["Cargo.lock"])
    }

    /// A threads run that skipped two is still accused, which is the point of
    /// the scope being a parameter rather than inferred from an empty array.
    func testAThreadsRunIsStillHeldToIt() {
        let table = ResolveTable(threads: [row("T1")])
            .sanitised(against: [thread("T1"), thread("T2")], scope: .threads)
        XCTAssertEqual(table.missing, ["T2"])
    }

    /// A branch that turned out to merge cleanly is a different answer from one
    /// that was fixed. Reporting it as "0 files resolved" would read as work.
    func testAMergeThatDidNotConflictSaysSo() {
        let table = ResolveTable(merge: MergeReport(conflicted: false))
            .sanitised(against: [], scope: .conflicts)
        XCTAssertEqual(table.merge?.conflicted, false)
        XCTAssertTrue(table.merge?.files.isEmpty == true)
    }

    func testAMergeReportWrittenByAnOlderBuildStillDecodes() throws {
        let legacy = Data(#"{"conflicted":true}"#.utf8)
        let merge = try JSONDecoder().decode(MergeReport.self, from: legacy)
        XCTAssertTrue(merge.conflicted)
        XCTAssertTrue(merge.files.isEmpty)
        XCTAssertNil(merge.sha)
    }

    // MARK: - Decoding

    func testARowWrittenByAnOlderBuildStillDecodes() throws {
        let legacy = Data(#"{"threadId":"T1","disposition":"fix","reply":"done"}"#.utf8)
        let row = try JSONDecoder().decode(ResolveRow.self, from: legacy)
        XCTAssertEqual(row.threadId, "T1")
        XCTAssertTrue(row.isSelected)
        XCTAssertFalse(row.shaIsUnpushed)
    }

    /// An unreadable disposition becomes the one that is never auto-resolved,
    /// which is the safe way to be wrong about it.
    func testAnUnknownDispositionDecodesAsNeedsYou() throws {
        let odd = Data(#"{"threadId":"T1","reply":"done"}"#.utf8)
        let row = try JSONDecoder().decode(ResolveRow.self, from: odd)
        XCTAssertEqual(row.disposition, .needsYou)
        XCTAssertFalse(row.mayResolve)
    }
}
