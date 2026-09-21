import XCTest
@testable import PRRadarCore

/// Every trophy rule, stated once here and once in `TrophyEvaluator`.
///
/// The evaluator is a pure function of a snapshot, which is the whole reason
/// thirty rules can be checked without a window, a network or a real clock —
/// including the four that are about what time it is.
final class TrophyEvaluatorTests: XCTestCase {

    // MARK: - Fixtures

    /// A clock that does not move, in a zone that does not argue. Tuesday,
    /// 21 September 2027, 15:00 UTC.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: iso)!
    }

    private var noon: Date { at("2027-09-21T15:00:00Z") }

    private func review(_ number: Int,
                        repo: String = "acme/repo",
                        author: String = "dana") -> ReviewItem {
        ReviewItem(repo: repo, number: number, title: "#\(number)",
                   url: URL(string: "https://example.com/\(number)")!,
                   isDraft: false, authorLogin: author, authorAvatarURL: nil,
                   pingedAt: noon)
    }

    private func pr(_ number: Int,
                    repo: String = "acme/repo",
                    on parent: Int? = nil,
                    blocker: MergeBlocker = .blocked,
                    approvals: [Approval] = [],
                    additions: Int = 5,
                    deletions: Int = 3) -> MyPullRequest {
        MyPullRequest(
            repo: repo, number: number, title: "#\(number)",
            url: URL(string: "https://example.com/\(number)")!, isDraft: false,
            createdAt: noon, updatedAt: noon,
            headRefName: "h\(number)", baseRefName: "b\(number)",
            reviewDecision: .reviewRequired, mergeBlocker: blocker,
            approvals: approvals, awaitingReviewers: [], unresolvedThreadCount: 0,
            totalThreadCount: 0, checks: .empty,
            additions: additions, deletions: deletions, changedFiles: 1,
            stackedOn: parent)
    }

    /// A snapshot with the first evaluation already behind it, so unlocks are
    /// announced rather than backfilled.
    private func snapshot(_ build: (inout TrophySnapshot) -> Void = { _ in })
        -> TrophySnapshot {
        var snapshot = TrophySnapshot()
        snapshot.now = noon
        snapshot.calendar = calendar
        build(&snapshot)
        return snapshot
    }

    private var settled: TrophyState {
        var state = TrophyState()
        state.established = true
        return state
    }

    private func unlocks(_ snapshot: TrophySnapshot,
                         from state: TrophyState? = nil) -> Set<TrophyID> {
        Set(TrophyEvaluator.evaluate(snapshot, state: state ?? settled).unlocked)
    }

    // MARK: - Clearing the queue

    func testClearingTheQueueUnlocksInboxZero() {
        let snapshot = snapshot { $0.previousScopedReviewCount = 3 }
        XCTAssertTrue(unlocks(snapshot).contains(.inboxZero))
    }

    /// The first refresh of a session has nothing to compare against, so
    /// arriving already empty is not arriving.
    func testAnAlreadyEmptyQueueIsNotAnAchievement() {
        XCTAssertFalse(unlocks(snapshot()).contains(.inboxZero))
    }

    func testStillHavingReviewsIsNotClearing() {
        let snapshot = snapshot {
            $0.previousScopedReviewCount = 3
            $0.scopedReviewCount = 1
            $0.reviews = [self.review(1)]
        }
        XCTAssertFalse(unlocks(snapshot).contains(.inboxZero))
    }

    /// The badge's count, not the unscoped list: the banner has to arrive the
    /// moment the badge's red count goes out.
    func testClearingFollowsTheBadgeRatherThanTheWholeInbox() {
        let snapshot = snapshot {
            $0.previousScopedReviewCount = 2
            $0.scopedReviewCount = 0
            // Still plenty waiting outside the repo filter.
            $0.reviews = (1...4).map { self.review($0) }
        }
        XCTAssertTrue(unlocks(snapshot).contains(.inboxZero))
    }

    func testFiveClearingsUnlockBackToZero() {
        var state = settled
        var seen: Set<TrophyID> = []
        for _ in 1...5 {
            let result = TrophyEvaluator.evaluate(
                snapshot { $0.previousScopedReviewCount = 1 }, state: state)
            state = result.state
            seen.formUnion(result.unlocked)
        }
        XCTAssertTrue(seen.contains(.backToZero))
    }

    func testFourClearingsDoNot() {
        var state = settled
        var seen: Set<TrophyID> = []
        for _ in 1...4 {
            let result = TrophyEvaluator.evaluate(
                snapshot { $0.previousScopedReviewCount = 1 }, state: state)
            state = result.state
            seen.formUnion(result.unlocked)
        }
        XCTAssertFalse(seen.contains(.backToZero))
    }

    func testDiggingOutOfTenUnlocksCleanSweep() {
        XCTAssertTrue(unlocks(snapshot { $0.previousScopedReviewCount = 10 })
            .contains(.cleanSweep))
        XCTAssertFalse(unlocks(snapshot { $0.previousScopedReviewCount = 9 })
            .contains(.cleanSweep))
    }

    // MARK: - The size and shape of the queue

    func testTenWaitingUnlocksSwamped() {
        XCTAssertTrue(unlocks(snapshot { $0.reviews = (1...10).map { self.review($0) } })
            .contains(.swamped))
        XCTAssertFalse(unlocks(snapshot { $0.reviews = (1...9).map { self.review($0) } })
            .contains(.swamped))
    }

    func testFiveDistinctAuthorsUnlockInDemand() {
        let many = snapshot {
            $0.reviews = ["a", "b", "c", "d", "e"].enumerated().map {
                self.review($0.offset, author: $0.element)
            }
        }
        XCTAssertTrue(unlocks(many).contains(.inDemand))
    }

    /// Five requests from one person is not five people.
    func testFiveRequestsFromOnePersonIsNotInDemand() {
        let same = snapshot {
            $0.reviews = (1...5).map { self.review($0, author: "dana") }
        }
        XCTAssertFalse(unlocks(same).contains(.inDemand))
    }

    // MARK: - Your own pull requests

    func testFiveOpenUnlocksJuggler() {
        XCTAssertTrue(unlocks(snapshot { $0.myPRs = (1...5).map { self.pr($0) } })
            .contains(.juggler))
        XCTAssertFalse(unlocks(snapshot { $0.myPRs = (1...4).map { self.pr($0) } })
            .contains(.juggler))
    }

    func testOneReadyToMergeUnlocksGreenLight() {
        let ready = snapshot { $0.myPRs = [self.pr(1, blocker: .clean)] }
        XCTAssertTrue(unlocks(ready).contains(.greenLight))
    }

    func testAllClearNeedsThreeAndEveryOneReady() {
        let three = snapshot {
            $0.myPRs = (1...3).map { self.pr($0, blocker: .clean) }
        }
        XCTAssertTrue(unlocks(three).contains(.allClear))

        let oneBlocked = snapshot {
            $0.myPRs = [self.pr(1, blocker: .clean), self.pr(2, blocker: .clean),
                        self.pr(3, blocker: .dirty)]
        }
        XCTAssertFalse(unlocks(oneBlocked).contains(.allClear))

        let onlyTwo = snapshot {
            $0.myPRs = (1...2).map { self.pr($0, blocker: .clean) }
        }
        XCTAssertFalse(unlocks(onlyTwo).contains(.allClear))
    }

    func testThreeApprovalsUnlockRubberStamp() {
        let approvals = ["a", "b", "c"].map {
            Approval(login: $0, state: .approved, isLead: false)
        }
        XCTAssertTrue(unlocks(snapshot { $0.myPRs = [self.pr(1, approvals: approvals)] })
            .contains(.rubberStamp))
    }

    /// Dismissed approvals are not approvals, the same rule the rows follow.
    func testDismissedApprovalsDoNotCountTowardsRubberStamp() {
        let approvals = [Approval(login: "a", state: .approved, isLead: false),
                         Approval(login: "b", state: .approved, isLead: false),
                         Approval(login: "c", state: .dismissed, isLead: false)]
        XCTAssertFalse(unlocks(snapshot { $0.myPRs = [self.pr(1, approvals: approvals)] })
            .contains(.rubberStamp))
    }

    // MARK: - Stacks

    func testTwoDeepUnlocksShortStackOnly() {
        let earned = unlocks(snapshot {
            $0.myPRs = [self.pr(1), self.pr(2, on: 1)]
        })
        XCTAssertTrue(earned.contains(.shortStack))
        XCTAssertFalse(earned.contains(.tallStack))
    }

    func testFourDeepUnlocksTallStack() {
        let earned = unlocks(snapshot {
            $0.myPRs = [self.pr(1), self.pr(2, on: 1),
                        self.pr(3, on: 2), self.pr(4, on: 3)]
        })
        XCTAssertTrue(earned.contains(.tallStack))
    }

    /// A link to something not in the list is a dangling reference to a
    /// merged PR, not a stack — the same rule `MyPRGrouping` follows.
    func testALinkToSomethingAbsentIsNotAStack() {
        XCTAssertFalse(unlocks(snapshot { $0.myPRs = [self.pr(2, on: 1)] })
            .contains(.shortStack))
    }

    func testTwoOnTheSameParentUnlockBranchingOut() {
        let earned = unlocks(snapshot {
            $0.myPRs = [self.pr(1), self.pr(2, on: 1), self.pr(3, on: 1)]
        })
        XCTAssertTrue(earned.contains(.branchingOut))
    }

    func testAStraightChainIsNotBranching() {
        XCTAssertFalse(unlocks(snapshot {
            $0.myPRs = [self.pr(1), self.pr(2, on: 1), self.pr(3, on: 2)]
        }).contains(.branchingOut))
    }

    /// Two repos can each have a `#1`; a stack is resolved within a repo.
    func testTheSameNumberInAnotherRepoIsNotAParent() {
        XCTAssertFalse(unlocks(snapshot {
            $0.myPRs = [self.pr(1, repo: "acme/one"),
                        self.pr(2, repo: "acme/two", on: 1)]
        }).contains(.shortStack))
    }

    /// Data this shape should never arrive, and must not hang the app if it
    /// does.
    func testACycleTerminates() {
        let earned = unlocks(snapshot {
            $0.myPRs = [self.pr(1, on: 2), self.pr(2, on: 1)]
        })
        XCTAssertTrue(earned.contains(.shortStack))
    }

    // MARK: - What time you did it at

    func testClearingAtNightUnlocksNightWatch() {
        let late = snapshot {
            $0.now = self.at("2027-09-21T23:30:00Z")
            $0.previousScopedReviewCount = 1
        }
        XCTAssertTrue(unlocks(late).contains(.nightWatch))

        let early = snapshot {
            $0.now = self.at("2027-09-21T03:30:00Z")
            $0.previousScopedReviewCount = 1
        }
        XCTAssertTrue(unlocks(early).contains(.nightWatch))
    }

    func testClearingInTheAfternoonDoesNot() {
        XCTAssertFalse(unlocks(snapshot { $0.previousScopedReviewCount = 1 })
            .contains(.nightWatch))
    }

    func testClearingOnASaturdayUnlocksWeekendWork() {
        let saturday = snapshot {
            $0.now = self.at("2027-09-25T15:00:00Z")
            $0.previousScopedReviewCount = 1
        }
        XCTAssertTrue(unlocks(saturday).contains(.weekendWork))
    }

    /// The time rules hang off the clearing, not off the clock — otherwise
    /// they would fire for anyone whose laptop happened to be awake.
    func testBeingAwakeAtNightIsNotEnough() {
        let late = snapshot { $0.now = self.at("2027-09-21T23:30:00Z") }
        XCTAssertFalse(unlocks(late).contains(.nightWatch))
    }

    // MARK: - The long count

    func testTheMergeLadder() {
        XCTAssertFalse(unlocks(snapshot { $0.mergedLifetime = 49 }).contains(.fiftyMerged))
        XCTAssertTrue(unlocks(snapshot { $0.mergedLifetime = 50 }).contains(.fiftyMerged))
        let hundred = unlocks(snapshot { $0.mergedLifetime = 100 })
        XCTAssertTrue(hundred.contains(.fiftyMerged))
        XCTAssertTrue(hundred.contains(.century))
    }

    /// A count that did not answer must read as unknown, never as zero.
    func testAnUnansweredCountAwardsNothingAndDeniesNothing() {
        let earned = unlocks(snapshot { $0.mergedLifetime = nil })
        XCTAssertFalse(earned.contains(.fiftyMerged))
        XCTAssertFalse(earned.contains(.century))
    }

    // MARK: - The app itself

    func testSeeingEveryMascotUnlocksMeetTheCast() {
        var state = settled
        for id in MascotID.allCases.dropLast() {
            state.record(TrophyFact.mascotSeen(id))
        }
        XCTAssertFalse(unlocks(snapshot(), from: state).contains(.meetTheCast))

        state.record(TrophyFact.mascotSeen(MascotID.allCases.last!))
        XCTAssertTrue(unlocks(snapshot(), from: state).contains(.meetTheCast))
    }

    func testTheBadgeSizeLimits() {
        let big = snapshot {
            $0.badgeMinimum = 28; $0.badgeMaximum = 128; $0.badgeTileSize = 128
        }
        XCTAssertTrue(unlocks(big).contains(.bigBadge))
        XCTAssertFalse(unlocks(big).contains(.tinyBadge))

        let small = snapshot {
            $0.badgeMinimum = 28; $0.badgeMaximum = 128; $0.badgeTileSize = 28
        }
        XCTAssertTrue(unlocks(small).contains(.tinyBadge))
        XCTAssertFalse(unlocks(small).contains(.bigBadge))
    }

    /// A snapshot that never mentions the badge must not award either.
    func testAnUnsetBadgeSizeAwardsNothing() {
        let earned = unlocks(snapshot())
        XCTAssertFalse(earned.contains(.tinyBadge))
        XCTAssertFalse(earned.contains(.bigBadge))
    }

    func testTheStackedFilterAndTheUpdateAreRemembered() {
        var state = settled
        state.record(TrophyFact.usedStackedFilter)
        state.record(TrophyFact.installedOfferedUpdate)
        let earned = unlocks(snapshot(), from: state)
        XCTAssertTrue(earned.contains(.pancakePress))
        XCTAssertTrue(earned.contains(.upToDate))
    }

    func testFourParkedCornersUnlockFourCorners() {
        var state = settled
        for corner in ["top-left", "top-right", "bottom-left"] {
            state.record(TrophyFact.badgeCorner(corner))
        }
        XCTAssertFalse(unlocks(snapshot(), from: state).contains(.fourCorners))
        state.record(TrophyFact.badgeCorner("bottom-right"))
        XCTAssertTrue(unlocks(snapshot(), from: state).contains(.fourCorners))
    }

    func testTenCyclesUnlockCarousel() {
        XCTAssertTrue(unlocks(snapshot { $0.mascotCyclesThisSession = 10 })
            .contains(.carousel))
        XCTAssertFalse(unlocks(snapshot { $0.mascotCyclesThisSession = 9 })
            .contains(.carousel))
    }

    // MARK: - Days seen running

    func testEachNewDayCountsOnceHoweverManyRefreshes() {
        var state = settled
        for hour in 0..<6 {
            let time = self.at(String(format: "2027-09-21T%02d:00:00Z", hour))
            state = TrophyEvaluator.evaluate(snapshot { $0.now = time }, state: state).state
        }
        XCTAssertEqual(state.runningDays, 1)
    }

    func testSevenDaysUnlockRegularAndThirtyUnlockVeteran() {
        var state = settled
        var seen: Set<TrophyID> = []
        for day in 1...30 {
            let time = self.at(String(format: "2027-09-%02dT12:00:00Z", day))
            let result = TrophyEvaluator.evaluate(snapshot { $0.now = time }, state: state)
            state = result.state
            seen.formUnion(result.unlocked)
            if day == 7 { XCTAssertTrue(seen.contains(.regular)) }
            if day == 6 { XCTAssertFalse(seen.contains(.veteran)) }
        }
        XCTAssertTrue(seen.contains(.veteran))
    }

    // MARK: - Hidden

    func testTheHomeRepoTrophies() {
        let home = "RogelioAD/pr-radar"
        let mine = snapshot { $0.homeRepo = home; $0.myPRs = [self.pr(1, repo: home)] }
        XCTAssertTrue(unlocks(mine).contains(.homeTeam))
        XCTAssertFalse(unlocks(mine).contains(.peerReview))
        XCTAssertFalse(unlocks(mine).contains(.fullCircle))

        let both = snapshot {
            $0.homeRepo = home
            $0.myPRs = [self.pr(1, repo: home)]
            $0.reviews = [self.review(2, repo: home)]
        }
        XCTAssertTrue(unlocks(both).contains(.fullCircle))
    }

    /// An unset home repo must not match every pull request with an empty
    /// repo name, which is what a bare equality check would do.
    func testNoHomeRepoAwardsNothing() {
        let earned = unlocks(snapshot { $0.myPRs = [self.pr(1, repo: "")] })
        XCTAssertFalse(earned.contains(.homeTeam))
    }

    func testPalindromeNeedsThreeDigits() {
        XCTAssertTrue(unlocks(snapshot { $0.myPRs = [self.pr(121)] }).contains(.palindrome))
        XCTAssertTrue(unlocks(snapshot { $0.myPRs = [self.pr(1331)] }).contains(.palindrome))
        XCTAssertFalse(unlocks(snapshot { $0.myPRs = [self.pr(11)] }).contains(.palindrome))
        XCTAssertFalse(unlocks(snapshot { $0.myPRs = [self.pr(7)] }).contains(.palindrome))
        XCTAssertFalse(unlocks(snapshot { $0.myPRs = [self.pr(123)] }).contains(.palindrome))
    }

    func testZeroSumNeedsAnEqualAndNonEmptyDiff() {
        XCTAssertTrue(unlocks(snapshot {
            $0.myPRs = [self.pr(1, additions: 40, deletions: 40)]
        }).contains(.zeroSum))

        // A pull request that changes nothing is not a refactor.
        XCTAssertFalse(unlocks(snapshot {
            $0.myPRs = [self.pr(1, additions: 0, deletions: 0)]
        }).contains(.zeroSum))
    }

    // MARK: - The shelf itself

    /// The first evaluation fills the shelf and says nothing. Installing this
    /// into a working setup satisfies a dozen rules at once.
    func testTheFirstEvaluationIsSilentButStillFillsTheShelf() {
        let busy = snapshot {
            $0.reviews = (1...10).map { self.review($0) }
            $0.mergedLifetime = 200
        }
        let result = TrophyEvaluator.evaluate(busy, state: TrophyState())

        XCTAssertTrue(result.unlocked.isEmpty, "the backfill must not announce itself")
        XCTAssertTrue(result.state.isUnlocked(.swamped))
        XCTAssertTrue(result.state.isUnlocked(.century))
        XCTAssertTrue(result.state.established)
        // Silent, but not invisible: the dot on the button is the only thing
        // that tells anyone the room filled up.
        XCTAssertTrue(result.state.hasUnseen)
    }

    func testTheSecondEvaluationAnnounces() {
        let first = TrophyEvaluator.evaluate(snapshot(), state: TrophyState()).state
        let result = TrophyEvaluator.evaluate(
            snapshot { $0.reviews = (1...10).map { self.review($0) } }, state: first)
        XCTAssertEqual(result.unlocked, [.swamped])
    }

    /// Unlocking is idempotent: a state rule reads as true on every refresh
    /// forever, and must announce itself exactly once.
    func testATrophyIsNeverAwardedTwice() {
        let busy = snapshot { $0.reviews = (1...10).map { self.review($0) } }
        let first = TrophyEvaluator.evaluate(busy, state: settled)
        XCTAssertEqual(first.unlocked, [.swamped])

        let second = TrophyEvaluator.evaluate(busy, state: first.state)
        XCTAssertTrue(second.unlocked.isEmpty)
    }

    /// Nothing is ever taken away. A stack you merged does not un-earn the
    /// trophy for having had one.
    func testATrophyIsNeverTakenBack() {
        let stacked = snapshot { $0.myPRs = [self.pr(1), self.pr(2, on: 1)] }
        let earned = TrophyEvaluator.evaluate(stacked, state: settled).state
        let after = TrophyEvaluator.evaluate(snapshot(), state: earned).state
        XCTAssertTrue(after.isUnlocked(.shortStack))
    }

    /// Announced in roster order, so a burst of banners reads down the shelf
    /// rather than in whatever order a `Set` felt like.
    func testUnlocksAreAnnouncedInRosterOrder() {
        let several = snapshot {
            $0.reviews = (1...10).map { self.review($0) }
            $0.myPRs = (1...5).map { self.pr($0) }
        }
        let unlocked = TrophyEvaluator.evaluate(several, state: settled).unlocked
        let order = Trophy.all.map(\.id)
        let positions = unlocked.compactMap { order.firstIndex(of: $0) }
        XCTAssertEqual(positions, positions.sorted())
    }
}
