import XCTest
@testable import PRRadarCore

/// Grouping is what the list is built out of, so its rules are assertions
/// rather than a careful look at the drawer.
final class MyPRStackTests: XCTestCase {

    // MARK: - Fixtures

    /// One PR. `on` is the number it is stacked on, already linked — this
    /// exercises grouping, not `MyPRInbox.linkStacks`, which has its own tests.
    private func pr(_ number: Int,
                    repo: String = "acme/repo",
                    on parent: Int? = nil,
                    created: TimeInterval = 0,
                    updated: TimeInterval = 0,
                    blocker: MergeBlocker = .blocked,
                    failing: Int = 0) -> MyPullRequest {
        MyPullRequest(
            repo: repo, number: number, title: "#\(number)",
            url: URL(string: "https://example.com/\(number)")!, isDraft: false,
            createdAt: Date(timeIntervalSince1970: created),
            updatedAt: Date(timeIntervalSince1970: updated),
            headRefName: "h\(number)", baseRefName: "b\(number)",
            reviewDecision: .reviewRequired, mergeBlocker: blocker,
            approvals: [], awaitingReviewers: [], unresolvedThreadCount: 0,
            totalThreadCount: 0,
            checks: ChecksSummary(passing: 0, failing: failing, running: 0,
                                  skipped: 0, failingNames: [], rollupState: nil),
            additions: 1, deletions: 1, changedFiles: 1,
            stackedOn: parent)
    }

    private func units(_ items: [MyPullRequest],
                       _ order: MyPRSortOrder = .newestFirst) -> [MyPRUnit] {
        MyPRGrouping.units(items, order: order)
    }

    // MARK: - Chains

    /// The live shape: five PRs each sitting on the one below. They become one
    /// unit, base last, because that is the end that rests on the plate.
    func testChainBecomesOneStackWithTheBaseLast() {
        let result = units([pr(793, on: 792), pr(791), pr(795, on: 794),
                            pr(792, on: 791), pr(794, on: 793)])
        XCTAssertEqual(result.count, 1)
        guard case .stack(let stack) = result[0] else { return XCTFail("not a stack") }
        XCTAssertEqual(stack.members.map(\.number), [795, 794, 793, 792, 791])
        XCTAssertEqual(stack.depth, 5)
        XCTAssertEqual(stack.base.number, 791)
    }

    /// 1 at the base, counting upward — what the row's pancakes show.
    func testPositionCountsUpFromTheBase() {
        guard case .stack(let stack) = units([pr(101), pr(102, on: 101),
                                              pr(103, on: 102)])[0]
        else { return XCTFail("not a stack") }
        XCTAssertEqual(stack.position(of: stack.members[2]), 1, "the base")
        XCTAssertEqual(stack.position(of: stack.members[1]), 2)
        XCTAssertEqual(stack.position(of: stack.members[0]), 3, "the top")
    }

    /// Keyed on the base, not the top: PRs are pushed onto a stack far more
    /// often than slid underneath it, and an id that changed on every push
    /// would lose the group's measured height and resize the drawer.
    func testStackIdentityFollowsTheBase() {
        guard case .stack(let two) = units([pr(101), pr(102, on: 101)])[0],
              case .stack(let three) = units([pr(101), pr(102, on: 101),
                                              pr(103, on: 102)])[0]
        else { return XCTFail("not a stack") }
        XCTAssertEqual(two.id, three.id, "pushing a PR on top keeps the group")
    }

    func testLonePRStaysSingle() {
        let result = units([pr(700)])
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].isStack)
        XCTAssertEqual(result[0].id, "acme/repo#700")
    }

    // MARK: - Only what is on screen

    /// A filter that hides a chain's middle leaves two PRs that are no longer
    /// related to each other. Grouping them anyway would draw a stack that does
    /// not exist — the group must only ever claim what it is showing.
    func testHidingTheMiddleOfAChainSplitsIt() {
        // 103 is stacked on 102, which is not in the list.
        let result = units([pr(101), pr(103, on: 102)])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { !$0.isStack })
    }

    /// Two repos can share branch names, and `linkStacks` already refuses to
    /// cross them; grouping must not undo that by matching on number alone.
    func testStacksDoNotCrossRepositories() {
        let result = units([pr(101, repo: "acme/one"),
                            pr(102, repo: "acme/two", on: 101)])
        XCTAssertEqual(result.count, 2)
        XCTAssertTrue(result.allSatisfy { !$0.isStack })
    }

    // MARK: - Branching

    /// `blocksRestackOf` is a list, so a stack is a tree. Both branches stay in
    /// one group, each branch's own run kept together rather than interleaved.
    func testBranchingStackStaysOneGroupInAStableOrder() {
        let first = units([pr(101), pr(102, on: 101), pr(103, on: 101)])
        let again = units([pr(103, on: 101), pr(101), pr(102, on: 101)])
        guard case .stack(let a) = first[0], case .stack(let b) = again[0]
        else { return XCTFail("not a stack") }
        XCTAssertEqual(a.members.map(\.number), b.members.map(\.number),
                       "input order must not change the drawing")
        XCTAssertEqual(a.base.number, 101)
        XCTAssertEqual(a.depth, 3)
    }

    // MARK: - Ordering

    /// A unit takes the place of its strongest member, so a stack carrying one
    /// broken PR surfaces even when everything else in it is clean.
    func testStackRanksByItsStrongestMember() {
        let lone = pr(700, created: 100)
        let base = pr(101, created: 200)
        let broken = pr(102, on: 101, created: 300, failing: 3)
        let result = units([lone, base, broken], .needsAttention)
        XCTAssertTrue(result[0].isStack,
                      "the stack holds the only failing PR, so it outranks the lone one")
        XCTAssertEqual(result[1].id, lone.id)
    }

    /// Members keep stack order inside whatever the sort is — the order of a
    /// stack is a fact about the branches, not a preference.
    func testSortDoesNotReorderWithinAStack() {
        for order in MyPRSortOrder.allCases {
            let result = MyPRGrouping.units(
                [pr(101, created: 300), pr(102, on: 101, created: 100)], order: order)
            guard case .stack(let stack) = result[0] else { return XCTFail("not a stack") }
            XCTAssertEqual(stack.members.map(\.number), [102, 101], "\(order)")
        }
    }

    // MARK: - Is there a stack at all

    /// What decides whether the pancake filter is offered. A control that
    /// cannot change anything is worse than no control.
    func testContainsStackOnlyWhenSomethingActuallySitsOnSomething() {
        XCTAssertFalse(MyPRGrouping.containsStack([]))
        XCTAssertFalse(MyPRGrouping.containsStack([pr(700), pr(701)]))
        XCTAssertTrue(MyPRGrouping.containsStack([pr(101), pr(102, on: 101)]))
    }

    /// The same rule grouping uses: a PR whose parent is not on screen is not
    /// part of a stack you could be shown, so it must not light the button.
    func testAnOrphanedChildIsNotAStack() {
        XCTAssertFalse(MyPRGrouping.containsStack([pr(103, on: 102)]),
                       "#102 is not in the list")
    }

    func testStacksAcrossRepositoriesDoNotCount() {
        XCTAssertFalse(MyPRGrouping.containsStack([
            pr(101, repo: "acme/one"),
            pr(102, repo: "acme/two", on: 101),
        ]))
    }

    /// It has to agree with the grouping, or the button appears over a list
    /// with no cards in it — or worse, fails to appear over one that has them.
    func testItAgreesWithWhatGroupingActuallyProduces() {
        let cases: [[MyPullRequest]] = [
            [],
            [pr(700)],
            [pr(700), pr(701)],
            [pr(101), pr(102, on: 101)],
            [pr(103, on: 102)],
            [pr(101), pr(102, on: 101), pr(700)],
            [pr(101, repo: "acme/one"), pr(102, repo: "acme/two", on: 101)],
        ]
        for items in cases {
            XCTAssertEqual(MyPRGrouping.containsStack(items),
                           units(items).contains { $0.isStack },
                           "\(items.map(\.number))")
        }
    }

    // MARK: - Where the drawer may stop

    /// A card is one unit but several rows. Counting it as one leaves the list
    /// with a single legal height and a top edge that cannot be dragged at all
    /// — which is exactly the state the pancake filter puts it in.
    func testEveryPullRequestIsAStoppingPoint() {
        let items = [pr(101), pr(102, on: 101), pr(103, on: 102), pr(700)]
        let stops = MyPRGrouping.stopHeights(units: units(items), stackChrome: 12,
                                             height: { _ in 100 })
        XCTAssertEqual(stops.count, 4, "one per PR, not one per unit")
    }

    /// The chrome rides on the card's first member, so the flattened run sums
    /// to exactly what the nested one did — the gaps inside a card are the same
    /// row spacing as the gaps between units.
    func testCardChromeIsChargedOnceToItsFirstMember() {
        let items = [pr(101), pr(102, on: 101), pr(700)]
        let stops = MyPRGrouping.stopHeights(units: units(items), stackChrome: 12,
                                             height: { _ in 100 })
        XCTAssertEqual(stops.reduce(0, +), 100 * 3 + 12,
                       "the card is charged for its padding exactly once")
        XCTAssertEqual(stops.filter { $0 == 112 }.count, 1)
        XCTAssertEqual(stops.filter { $0 == 100 }.count, 2)
    }

    /// A lone PR is not a card and pays no chrome.
    func testLonePullRequestsCarryNoChrome() {
        let stops = MyPRGrouping.stopHeights(units: units([pr(700), pr(701)]),
                                             stackChrome: 12, height: { _ in 90 })
        XCTAssertEqual(stops, [90, 90])
    }

    /// The boundary after a card's last member is the card's own bottom edge,
    /// which is where a drag most wants to settle.
    func testTheCardsOwnBottomEdgeIsAStoppingPoint() {
        let items = [pr(101), pr(102, on: 101), pr(103, on: 102)]
        let stops = MyPRGrouping.stopHeights(units: units(items), stackChrome: 12,
                                             height: { _ in 100 })
        // Three rows, two gaps inside the card, plus its padding.
        let sizing = DrawerSizing(rowSpacing: 2, listPadding: 12, chromeHeight: 0,
                                  maxHeight: 10_000, estimatedRowHeight: 100)
        let boundaries = sizing.rowBoundaries(rowHeights: stops, itemCount: stops.count)
        let rows: CGFloat = 100 * 3
        let gaps: CGFloat = 2 * 2
        let chrome: CGFloat = 12
        let listPadding: CGFloat = 12
        XCTAssertEqual(boundaries.last, rows + gaps + chrome + listPadding,
                       "the last boundary is the whole card plus the list's padding")
        XCTAssertEqual(boundaries.count, 3, "and you can stop at any row inside it")
    }

    /// Rows that have not reported yet are skipped rather than guessed at here;
    /// `DrawerSizing` already falls back to its estimate for the tail. The
    /// card's chrome must survive that, or the total shrinks by 12pt for the
    /// frame or two before everything has measured.
    func testChromeSurvivesAnUnmeasuredFirstMember() {
        let items = [pr(101), pr(102, on: 101)]
        // Members are base-last, so #102 is first and #101 is the base.
        let stops = MyPRGrouping.stopHeights(units: units(items), stackChrome: 12,
                                             height: { $0.number == 101 ? 100 : nil })
        XCTAssertEqual(stops, [112], "the chrome moves to whichever row reported")
    }

    /// The refactor that exposed the comparator must not have changed the sort.
    func testFlatSortStillMatchesTheComparator() {
        let items = [pr(1, created: 300), pr(2, created: 100), pr(3, created: 200)]
        for order in MyPRSortOrder.allCases {
            XCTAssertEqual(order.apply(to: items).map(\.number),
                           items.sorted(by: order.isOrderedBefore).map(\.number),
                           "\(order)")
        }
    }
}
