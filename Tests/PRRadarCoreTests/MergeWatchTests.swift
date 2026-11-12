import XCTest
@testable import PRRadarCore

/// Which merges get a banner, and what is remembered afterwards.
///
/// Every case here is one somebody would otherwise have to arrange by waiting:
/// a first launch, a laptop shut for a weekend, a release train, an account
/// that failed to answer for one round. None of them is something you can sit
/// and wait for, and three of the four only go wrong in a direction nobody
/// notices — a banner that silently stops firing.
final class MergeWatchTests: XCTestCase {

    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func at(_ offset: TimeInterval) -> Date { now.addingTimeInterval(offset) }

    func merge(_ repo: String, _ number: Int,
               author: String = "alice",
               mergedAt: TimeInterval = -60) -> MergedPR {
        MergedPR(repo: repo, number: number, authorLogin: author, mergedAt: at(mergedAt))
    }

    // MARK: - What gets announced

    /// The first round is silent, whatever it finds. A fresh install sees the
    /// last few merges in every repository it watches, and every one of them is
    /// history the user has already read about somewhere else.
    func testFirstRoundSaysNothing() {
        let seen = [merge("acme/web", 1), merge("acme/web", 2)]
        XCTAssertTrue(MergeWatch.landed(seen, announced: [], now: now).isEmpty)
    }

    /// …and the round after it is not silent, because the first one wrote
    /// everything down.
    func testSecondRoundAnnouncesWhatTheFirstDidNotSee() {
        let first = [merge("acme/web", 1)]
        let store = MergeWatch.remembered([], seeing: first)

        let second = first + [merge("acme/web", 2)]
        XCTAssertEqual(MergeWatch.landed(second, announced: store, now: now).map(\.id),
                       ["acme/web#2"])
    }

    func testSomethingAlreadyAnnouncedNeverComesBack() {
        let seen = [merge("acme/web", 7)]
        XCTAssertTrue(MergeWatch.landed(seen, announced: ["acme/web#7"], now: now).isEmpty)
    }

    /// A Mac closed on Friday and opened on Monday has a weekend of merges it
    /// has never announced. Announcing them is not telling somebody what
    /// happened while they were out; it is ninety banners about things they
    /// read in Slack two days ago.
    func testABacklogIsNotNews() {
        let old = merge("acme/web", 1, mergedAt: -MergeWatch.freshness - 1)
        let fresh = merge("acme/web", 2, mergedAt: -MergeWatch.freshness + 1)
        XCTAssertEqual(MergeWatch.landed([old, fresh], announced: ["seed"], now: now).map(\.id),
                       ["acme/web#2"])
    }

    /// A clock a few seconds ahead of GitHub's is a merge stamped in the
    /// future. That is news, not a prediction to be filtered out.
    func testAMergeStampedInTheFutureStillCounts() {
        let skewed = merge("acme/web", 3, mergedAt: 30)
        XCTAssertEqual(MergeWatch.landed([skewed], announced: ["seed"], now: now).count, 1)
    }

    /// Oldest first, so a burst reads in the order the work actually landed.
    func testABurstReadsInTheOrderItLanded() {
        let seen = [merge("acme/web", 3, mergedAt: -10),
                    merge("acme/web", 1, mergedAt: -300),
                    merge("acme/web", 2, mergedAt: -100)]
        XCTAssertEqual(MergeWatch.landed(seen, announced: ["seed"], now: now).map(\.number),
                       [1, 2, 3])
    }

    // MARK: - What is remembered

    /// Everything in the window, not just what fired — the rule the comment
    /// notifier already keeps. Otherwise a merge the freshness floor suppressed
    /// arrives in a burst the next time something else lands.
    func testEverythingSeenIsRemembered() {
        let stale = merge("acme/web", 1, mergedAt: -MergeWatch.freshness - 1)
        let store = MergeWatch.remembered(["seed"], seeing: [stale])
        XCTAssertTrue(store.contains("acme/web#1"))
    }

    /// An id that has fallen out of its repository's window can never come
    /// back, so forgetting it costs nothing — and it is the only thing keeping
    /// the store from growing for ever.
    func testIdsThatHaveFallenOutOfTheWindowAreForgotten() {
        let store = MergeWatch.remembered(["acme/web#1", "acme/web#2"],
                                          seeing: [merge("acme/web", 3)])
        XCTAssertEqual(store.subtracting([MergeWatch.seeded]), ["acme/web#3"])
    }

    /// An empty store has to mean *never ran* and nothing else. Without a mark
    /// of its own it would also mean "the repositories you watch have not
    /// merged anything yet", and the first pull request ever to land in a new
    /// set of repositories would be swallowed as though it were a backlog.
    func testARoundThatSawNothingStillCountsAsHavingRun() {
        let store = MergeWatch.remembered([], seeing: [])
        XCTAssertFalse(store.isEmpty)
        XCTAssertEqual(MergeWatch.landed([merge("acme/web", 1)],
                                         announced: store, now: now).map(\.id),
                       ["acme/web#1"])
    }

    /// The mark survives the prune, because no round ever asks about a
    /// repository by that name — and it can never collide with a real id,
    /// because a GitHub name cannot contain a parenthesis.
    func testTheMarkIsNotPrunedAndCannotCollide() {
        let store = MergeWatch.remembered([MergeWatch.seeded],
                                          seeing: [merge("acme/web", 1)])
        XCTAssertTrue(store.contains(MergeWatch.seeded))
        XCTAssertFalse(MergeWatch.seeded.contains("/"), "not a repository name")
    }

    /// The one thing it must not do. A round where an account failed returns
    /// nothing for that account's repositories; pruning on that would
    /// re-announce their last hour the moment the account came back.
    func testARepositoryNobodyLookedAtIsKept() {
        let store = MergeWatch.remembered(["acme/ios#9", "acme/web#1"],
                                          seeing: [merge("acme/web", 2)])
        XCTAssertTrue(store.contains("acme/ios#9"), "the ios account did not answer")
        XCTAssertFalse(store.contains("acme/web#1"), "but the web one did")
    }

    /// Together: a failed round must not make the next one talkative.
    func testAFailedRoundIsNotFollowedByABurst() {
        var store = MergeWatch.remembered([], seeing: [merge("acme/ios", 9)])
        // The round where that account could not be read at all.
        store = MergeWatch.remembered(store, seeing: [])
        XCTAssertTrue(MergeWatch.landed([merge("acme/ios", 9)],
                                        announced: store, now: now).isEmpty)
    }

    func testRepoOfSplitsOnTheFirstHashOnly() {
        XCTAssertEqual(MergeWatch.repo(of: "acme/web#12"), "acme/web")
        XCTAssertEqual(MergeWatch.repo(of: "acme/web"), "acme/web")
    }

    // MARK: - Which repositories are watched

    func testWatchesEveryRepositoryInEitherList() {
        XCTAssertEqual(MergeWatch.watchable(reviews: ["acme/web"], mine: ["acme/ios"]),
                       ["acme/ios", "acme/web"])
    }

    func testARepositoryInBothListsIsWatchedOnce() {
        XCTAssertEqual(MergeWatch.watchable(reviews: ["acme/web"], mine: ["acme/web"]),
                       ["acme/web"])
    }

    /// One aliased query per repository, on the sixty-second poll. The cap is
    /// the only thing standing between somebody with reviews open across forty
    /// repositories and a request that takes the whole minute.
    func testTheWatchListIsCappedAndStableAcrossRounds() {
        let many = (1...40).map { "acme/repo-\($0)" }
        let first = MergeWatch.watchable(reviews: many, mine: [], limit: 5)
        let second = MergeWatch.watchable(reviews: many.reversed(), mine: [], limit: 5)
        XCTAssertEqual(first.count, 5)
        XCTAssertEqual(first, second, "the same five, whatever order they arrived in")
    }

    func testNothingToWatchIsAnEmptyList() {
        XCTAssertTrue(MergeWatch.watchable(reviews: [], mine: []).isEmpty)
    }
}
