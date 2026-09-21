import Foundation

/// A run of your own PRs where each sits on the one below it.
///
/// `MyPRInbox.linkStacks` already works out who sits on whom; this is the shape
/// that turns those pairwise links into something the list can show as one
/// thing.
public struct MyPRStack: Identifiable, Sendable, Equatable {

    /// Base **last**. The PR everything else sits on is at the bottom, resting
    /// on the plate, which is the way a stack of anything is drawn.
    public let members: [MyPullRequest]

    public init(members: [MyPullRequest]) {
        precondition(members.count >= 2, "a stack of one is just a pull request")
        self.members = members
    }

    public var base: MyPullRequest { members[members.count - 1] }
    public var depth: Int { members.count }

    /// Keyed on the base rather than on the top: the base is the stable end.
    /// PRs get added on top of a stack far more often than underneath it, and a
    /// group whose identity changed every time you pushed would lose its
    /// measured height — and so resize the drawer — on every new PR.
    public var id: String { "stack:\(base.repo)#\(base.number)" }

    /// 1 at the base, counting upward. What a row's pancakes show.
    public func position(of item: MyPullRequest) -> Int {
        guard let index = members.firstIndex(where: { $0.id == item.id }) else { return 1 }
        return members.count - index
    }
}

/// One thing in the My PRs list: a lone PR, or a whole stack shown as a group.
///
/// The list is built out of these rather than out of PRs because the drawer
/// sizes itself by summing measured row heights and settling on a boundary
/// between them. A group's outline, padding and plate are height, and height
/// the sizing cannot see is height the drawer ends halfway through.
public enum MyPRUnit: Identifiable, Sendable, Equatable {
    case single(MyPullRequest)
    case stack(MyPRStack)

    public var id: String {
        switch self {
        case .single(let item): return item.id
        case .stack(let stack): return stack.id
        }
    }

    public var pullRequests: [MyPullRequest] {
        switch self {
        case .single(let item): return [item]
        case .stack(let stack): return stack.members
        }
    }

    public var isStack: Bool {
        if case .stack = self { return true }
        return false
    }
}

public enum MyPRGrouping {

    /// Groups a list into units and orders them.
    ///
    /// Links are resolved **only among `items`**. If a filter or the repo scope
    /// has hidden the middle of a chain, what is left is not a stack any more,
    /// and the group must not claim a relationship it is not showing — that is
    /// the difference between grouping what is on screen and grouping what
    /// happens to be in memory.
    ///
    /// A unit takes the place of its strongest-ranking member, so a stack
    /// carrying one conflicted PR surfaces under "needs attention" even when
    /// everything else in it is clean. Members keep stack order inside,
    /// whatever the sort — the order of a stack is a fact about the branches,
    /// not a preference.
    public static func units(_ items: [MyPullRequest],
                             order: MyPRSortOrder) -> [MyPRUnit] {
        let present = Set(items.map(\.id))
        let byNumber = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        /// The PR this one sits on, but only if that PR is also on screen.
        func parent(of item: MyPullRequest) -> MyPullRequest? {
            guard let key = parentID(of: item), present.contains(key) else { return nil }
            return byNumber[key]
        }

        // Children, resolved the same way and sorted so a branching stack comes
        // out the same on every refresh.
        var children: [String: [MyPullRequest]] = [:]
        for item in items {
            guard let parent = parent(of: item) else { continue }
            children[parent.id, default: []].append(item)
        }
        for key in children.keys {
            children[key]?.sort { $0.number < $1.number }
        }

        let roots = items.filter { parent(of: $0) == nil }
        var units: [MyPRUnit] = []
        for root in roots {
            // Deepest first, so the base lands at the end. `blocksRestackOf` is
            // a list, so a stack is a tree rather than always a line — a
            // depth-first walk is what keeps a branch's own run together
            // instead of interleaving it with its sibling's.
            var branch: [MyPullRequest] = []
            func walk(_ item: MyPullRequest) {
                for child in children[item.id] ?? [] { walk(child) }
                branch.append(item)
            }
            walk(root)
            units.append(branch.count >= 2 ? .stack(MyPRStack(members: branch))
                                           : .single(root))
        }

        return units.sorted { lhs, rhs in
            guard let left = strongest(of: lhs, order: order),
                  let right = strongest(of: rhs, order: order) else { return false }
            return order.isOrderedBefore(left, right)
        }
    }

    /// The heights the drawer may settle at, one per pull request, in display
    /// order — with a card's own chrome folded into its first member.
    ///
    /// A stack is one *unit* to the layout but several rows to the eye, and the
    /// drawer snaps to a boundary between rows. Counting a card as a single row
    /// leaves the list with one legal height and a top edge that cannot be
    /// dragged at all, which is what happens the moment the pancake button is
    /// the only thing showing.
    ///
    /// Folding the chrome into the first member keeps the arithmetic exact: the
    /// gaps inside a card are the same `rowSpacing` as the gaps between units,
    /// so the flattened run sums to precisely what the nested one did — and the
    /// boundary after a card's last member still lands on the card's own bottom
    /// edge, which is the one place a drag most wants to stop.
    public static func stopHeights(units: [MyPRUnit],
                                   stackChrome: CGFloat,
                                   height: (MyPullRequest) -> CGFloat?) -> [CGFloat] {
        var result: [CGFloat] = []
        for unit in units {
            // Charged to the first member that has actually reported, not the
            // first member: during the frame or two before everything has
            // measured, charging an absent row would drop the card's chrome
            // from the total altogether.
            var owed = unit.isStack ? stackChrome : 0
            for item in unit.pullRequests {
                guard let measured = height(item) else { continue }
                result.append(measured + owed)
                owed = 0
            }
        }
        return result
    }

    /// Whether any of these PRs sits on another of them — what decides whether
    /// the pancake filter is worth offering at all.
    ///
    /// Resolved among `items` for the same reason grouping is: a PR whose
    /// parent is not on screen is not part of a stack you could be shown.
    public static func containsStack(_ items: [MyPullRequest]) -> Bool {
        let present = Set(items.map(\.id))
        return items.contains { parentID(of: $0).map(present.contains) ?? false }
    }

    /// How a parent is addressed. One place knows how an id is spelled.
    private static func parentID(of item: MyPullRequest) -> String? {
        item.stackedOn.map { "\(item.repo)#\($0)" }
    }

    /// The member that would rank highest on its own.
    private static func strongest(of unit: MyPRUnit,
                                  order: MyPRSortOrder) -> MyPullRequest? {
        unit.pullRequests.min(by: order.isOrderedBefore)
    }
}
