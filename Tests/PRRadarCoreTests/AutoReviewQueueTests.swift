import XCTest
@testable import PRRadarCore

final class AutoReviewQueueTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_789_000_000)
    let me: Set<String> = ["RogelioAD"]
    let allowed: Set<String> = ["acme/repo"]

    private func item(number: Int = 1,
                      repo: String = "acme/repo",
                      author: String = "someone",
                      draft: Bool = false,
                      nodeID: String? = "PR_1",
                      pingedAt: TimeInterval = 0) -> ReviewItem {
        ReviewItem(repo: repo, number: number, title: "t",
                   url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
                   isDraft: draft, authorLogin: author, authorAvatarURL: nil,
                   pingedAt: now.addingTimeInterval(pingedAt), nodeID: nodeID)
    }

    private func policy(_ enabled: Bool = true) -> AutoReviewPolicy {
        AutoReviewPolicy(isEnabled: enabled)
    }

    private func skip(_ item: ReviewItem,
                      log: AutoReviewLog = AutoReviewLog(),
                      allowlist: Set<String>? = nil,
                      policy custom: AutoReviewPolicy? = nil,
                      startedInLastHour: Int = 0) -> AutoReviewSkip? {
        AutoReviewQueue.skip(for: item, log: log, viewerLogins: me,
                             allowlist: allowlist ?? allowed,
                             policy: custom ?? policy(),
                             startedInLastHour: startedInLastHour, now: now)
    }

    // MARK: - The happy path

    func testAnOrdinaryPingIsPending() {
        XCTAssertNil(skip(item()))
    }

    func testPendingIsOldestPingFirst() {
        let items = [item(number: 1, pingedAt: 100), item(number: 2, pingedAt: -100)]
        let pending = AutoReviewQueue.pending(
            items: items, log: AutoReviewLog(), viewerLogins: me,
            allowlist: allowed, policy: policy(), startedInLastHour: 0, now: now)
        XCTAssertEqual(pending.map(\.number), [2, 1])
    }

    // MARK: - Each exclusion

    func testNothingIsReviewedWhileTheToggleIsOff() {
        XCTAssertEqual(skip(item(), policy: policy(false)), .disabled)
        XCTAssertTrue(AutoReviewQueue.pending(
            items: [item()], log: AutoReviewLog(), viewerLogins: me,
            allowlist: allowed, policy: policy(false),
            startedInLastHour: 0, now: now).isEmpty)
    }

    /// The guard that keeps a stray review request from an unfamiliar repo from
    /// getting an automated comment.
    func testARepoOutsideTheAllowlistIsNeverTouched() {
        XCTAssertEqual(skip(item(repo: "other/thing")), .repoNotAllowed)
    }

    /// A capital letter in a settings field is not a decision to exclude a repo.
    func testTheAllowlistIsMatchedCaseInsensitively() {
        XCTAssertNil(skip(item(repo: "Acme/Repo")))
    }

    /// You cannot approve your own PR, and reviewing it would only be an
    /// expense with a rejected mutation at the end.
    func testMyOwnPullRequestIsNeverReviewed() {
        XCTAssertEqual(skip(item(author: "RogelioAD")), .ownPullRequest)
    }

    func testADraftIsNotAskingYet() {
        XCTAssertEqual(skip(item(draft: true)), .draft)
    }

    func testDraftsAreReviewedWhenThePolicySaysSo() {
        var allowing = policy()
        allowing.skipDrafts = false
        XCTAssertNil(skip(item(draft: true), policy: allowing))
    }

    /// Every mutation needs the PR's node id. A review nobody can post is only
    /// an expense.
    func testAPRWithNoNodeIDIsNotActionable() {
        XCTAssertEqual(skip(item(nodeID: nil)), .notActionable)
    }

    // MARK: - Never twice

    /// The most important exclusion in the list: one ping gets one review, or
    /// the poll loop posts a comment every sixty seconds.
    func testAPingWhoseReviewIsDoneOrInFlightIsNeverReviewedAgain() {
        for status in [AutoReviewStatus.running, .ready, .posted, .dismissed] {
            var log = AutoReviewLog()
            log[item().pingKey] = AutoReviewRecord(status: status)
            XCTAssertEqual(skip(item(), log: log), .alreadyHandled, "\(status)")
        }
    }

    /// Queued means wanted, not started — a reason to run, not to refuse.
    ///
    /// Counting it as handled was a deadlock with no way out. Re-run sets
    /// exactly this status, so pressing it parked the row in `queued` for good:
    /// the button meant to retry a review was the one that made retrying
    /// impossible, and nothing short of deleting a defaults key recovered it.
    func testAQueuedPingIsStillPending() {
        var log = AutoReviewLog()
        log[item().pingKey] = AutoReviewRecord(status: .queued)
        XCTAssertNil(skip(item(), log: log))

        let pending = AutoReviewQueue.pending(
            items: [item()], log: log, viewerLogins: me,
            allowlist: allowed, policy: policy(), startedInLastHour: 0, now: now)
        XCTAssertEqual(pending.count, 1)
    }

    /// A skip is a condition, not a verdict.
    ///
    /// This one shipped wrong. A PR seen before its repo was ticked got
    /// `skipped: auto-review off here` written down — and because *any* record
    /// counted as already handled, ticking the repo afterwards changed nothing.
    /// The row went on insisting on a reason that had stopped being true, and
    /// the only way out was deleting a defaults key. Every skip reason is
    /// something the user then goes and fixes, so every one of them has to be
    /// re-tested rather than remembered.
    func testASkippedRecordDoesNotStopAPRThatNowQualifies() {
        var log = AutoReviewLog()
        var stale = AutoReviewRecord(status: .skipped)
        stale.failure = AutoReviewSkip.repoNotAllowed.reason
        log[item().pingKey] = stale
        XCTAssertNil(skip(item(), log: log))
    }

    /// And when the condition really has not changed, the reason is named
    /// again rather than falling silently through.
    func testASkippedRecordStillReportsTheReasonWhenItStillApplies() {
        var log = AutoReviewLog()
        log[item(repo: "other/thing").pingKey] = AutoReviewRecord(status: .skipped)
        XCTAssertEqual(skip(item(repo: "other/thing"), log: log), .repoNotAllowed)
    }

    /// The same PR must become genuinely reviewable, not merely un-skipped.
    func testAPreviouslySkippedPRIsPickedUpOnceTheRepoIsAllowlisted() {
        var log = AutoReviewLog()
        var stale = AutoReviewRecord(status: .skipped)
        stale.failure = AutoReviewSkip.repoNotAllowed.reason
        log[item().pingKey] = stale
        let pending = AutoReviewQueue.pending(
            items: [item()], log: log, viewerLogins: me,
            allowlist: allowed, policy: policy(), startedInLastHour: 0, now: now)
        XCTAssertEqual(pending.count, 1)
    }

    /// A re-request is a new ping, so it is a new key, so the old record does
    /// not answer for it — which is what makes "please look again" work.
    func testARerequestMakesAnAlreadyPostedPRPendingAgain() {
        var log = AutoReviewLog()
        log[item(pingedAt: 0).pingKey] = AutoReviewRecord(status: .posted)
        XCTAssertNil(skip(item(pingedAt: 86_400), log: log))
    }

    // MARK: - Failure and retry

    func testAFailureIsRetriedOnceTheBackoffHasPassed() {
        var record = AutoReviewRecord(status: .failed)
        record.attempts = 1
        record.finishedAt = now.addingTimeInterval(-7_200)
        var log = AutoReviewLog()
        log[item().pingKey] = record
        XCTAssertNil(skip(item(), log: log))
    }

    func testAFailureInsideTheBackoffWaits() {
        var record = AutoReviewRecord(status: .failed)
        record.attempts = 1
        record.finishedAt = now.addingTimeInterval(-60)
        var log = AutoReviewLog()
        log[item().pingKey] = record
        XCTAssertEqual(skip(item(), log: log), .backingOff)
    }

    /// A broken setup should stop, not work its way down the list twice an hour
    /// forever.
    func testAFailureStopsBeingRetriedOnceTheAttemptsAreSpent() {
        var record = AutoReviewRecord(status: .failed)
        record.attempts = 2
        record.finishedAt = now.addingTimeInterval(-7_200)
        var log = AutoReviewLog()
        log[item().pingKey] = record
        XCTAssertEqual(skip(item(), log: log), .attemptsExhausted)
    }

    // MARK: - Rate cap

    /// A ceiling on what this can cost while nobody is watching.
    func testTheHourlyCapStopsTheQueue() {
        XCTAssertTrue(AutoReviewQueue.pending(
            items: [item()], log: AutoReviewLog(), viewerLogins: me,
            allowlist: allowed, policy: policy(), startedInLastHour: 6, now: now).isEmpty)
    }

    func testTheQueueNeverHandsBackMoreThanTheCapAllows() {
        let items = (1...10).map { item(number: $0, pingedAt: TimeInterval($0)) }
        let pending = AutoReviewQueue.pending(
            items: items, log: AutoReviewLog(), viewerLogins: me,
            allowlist: allowed, policy: policy(), startedInLastHour: 4, now: now)
        XCTAssertEqual(pending.count, 2)
    }

    // MARK: - What the row says

    /// A PR quietly not being reviewed looks identical to one the feature is
    /// broken for, so the interesting reasons are shown and the rest are not.
    func testOnlyTheInformativeReasonsAreWorthShowing() {
        XCTAssertFalse(AutoReviewSkip.disabled.isWorthShowing)
        XCTAssertFalse(AutoReviewSkip.alreadyHandled.isWorthShowing)
        XCTAssertTrue(AutoReviewSkip.repoNotAllowed.isWorthShowing)
        XCTAssertTrue(AutoReviewSkip.attemptsExhausted.isWorthShowing)
    }
}
