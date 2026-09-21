import Foundation

/// Everything a trophy rule is allowed to know.
///
/// One value, assembled by the app once per refresh and read by every rule.
/// No rule reaches past it — not to `Date()`, not to `Prefs`, not to a view —
/// which is what makes thirty rules testable without a screen, a network or a
/// clock, and what stops the next rule quietly acquiring a dependency nobody
/// notices until it misfires at midnight.
public struct TrophySnapshot: Sendable {

    // MARK: What GitHub says

    /// Reviews waiting on you. Unscoped by the repo filter on purpose: a
    /// trophy is a fact about your week, and a filter is a fact about the
    /// pane you happen to be looking through.
    public var reviews: [ReviewItem] = []
    public var myPRs: [MyPullRequest] = []
    /// Pull requests you have ever merged. nil when the count query has not
    /// answered — which must read as *unknown*, never as zero.
    public var mergedLifetime: Int?

    // MARK: What the app has watched you do

    /// The count the badge is showing, and what it was showing last refresh.
    ///
    /// Repo-scoped, unlike `reviews` — deliberately, and it is the one place
    /// the two disagree. Clearing the queue is the moment the badge's red
    /// count goes out, and a banner that fired at a different moment from
    /// the thing it is congratulating you for would be congratulating you
    /// for something else. Everything that counts or groups reviews reads
    /// the unscoped list instead: how many people are waiting on you is a
    /// fact about your week, not about the pane you are looking through.
    ///
    /// `previous` is nil until a second refresh has landed, which is what
    /// keeps launching into an empty queue from counting as arriving at one.
    public var scopedReviewCount = 0
    public var previousScopedReviewCount: Int?
    public var badgeTileSize: CGFloat = 0
    public var badgeMinimum: CGFloat = 0
    public var badgeMaximum: CGFloat = 0
    /// Mascot cycles since the drawer was last opened. The one witnessed fact
    /// that is *not* remembered: ten cycles across ten sittings is not the
    /// thing the trophy is about.
    public var mascotCyclesThisSession = 0

    // MARK: Context

    public var now = Date()
    /// Used by the hidden pr-radar trophies. Read from `Prefs.updateRepo`, so
    /// a fork rewards contributions to the fork.
    public var homeRepo = ""
    /// Injected so the time-of-day rules can be tested in a fixed zone rather
    /// than wherever the machine running the tests happens to be.
    public var calendar = Calendar.current

    public init() {}
}

/// Turns a snapshot into unlocks.
///
/// A pure function, and the only place a trophy is ever awarded. Rules are
/// written as *is this true now* wherever they can be: a state rule re-reads
/// as true on every refresh and unlocking is idempotent, so there is nothing
/// to remember and nothing to get out of step. Only the handful that are
/// genuinely about a change — clearing the queue — consult what the last
/// refresh saw.
public enum TrophyEvaluator {

    public static func evaluate(_ snapshot: TrophySnapshot,
                                state: TrophyState) -> (state: TrophyState,
                                                        unlocked: [TrophyID]) {
        var state = state

        // A new calendar day, which is what the two long-service trophies
        // count. Days seen rather than hours accumulated: an app that lives
        // in the corner is running whenever the machine is, so hours would
        // measure the laptop's habits rather than yours.
        let today = Self.dayKey(snapshot.now, calendar: snapshot.calendar)
        if state.lastDay != today {
            state.lastDay = today
            state.bump(TrophyState.Counters.runningDays)
        }

        // The one transition anything depends on. Guarded on a *previous*
        // count: with no previous refresh to compare against there has been
        // no arrival at zero, however empty things are.
        let clearedFrom = snapshot.previousScopedReviewCount ?? 0
        let cleared = clearedFrom > 0 && snapshot.scopedReviewCount == 0
        if cleared { state.bump(TrophyState.Counters.queueCleared) }

        var earns: Set<TrophyID> = []
        func award(_ id: TrophyID, _ condition: Bool) {
            if condition { earns.insert(id) }
        }

        // MARK: The review queue

        award(.inboxZero, cleared)
        award(.backToZero, state.count(TrophyState.Counters.queueCleared) >= 5)
        award(.cleanSweep, cleared && clearedFrom >= 10)
        award(.swamped, snapshot.reviews.count >= 10)
        award(.inDemand, Set(snapshot.reviews.map(\.authorLogin)).count >= 5)

        // MARK: What time you did it at
        //
        // Hung off the same transition rather than off the clock alone: the
        // trophy is for clearing the queue at that hour, and a rule that only
        // looked at the time would award it to anyone whose laptop was awake.

        if cleared {
            let hour = snapshot.calendar.component(.hour, from: snapshot.now)
            award(.nightWatch, hour >= 22 || hour < 4)
            let weekday = snapshot.calendar.component(.weekday, from: snapshot.now)
            award(.weekendWork, weekday == 1 || weekday == 7)
        }

        // MARK: Your own pull requests

        let mine = snapshot.myPRs
        award(.juggler, mine.count >= 5)
        award(.greenLight, mine.contains(where: \.isReadyToMerge))
        award(.allClear, mine.count >= 3 && mine.allSatisfy(\.isReadyToMerge))
        award(.rubberStamp, mine.contains { $0.liveApprovals.count >= 3 })

        let depth = deepestStack(mine)
        award(.shortStack, depth >= 2)
        award(.tallStack, depth >= 4)
        award(.branchingOut, hasBranchingStack(mine))

        // MARK: The long count

        if let merged = snapshot.mergedLifetime {
            award(.fiftyMerged, merged >= 50)
            award(.century, merged >= 100)
        }

        // MARK: The app itself

        award(.meetTheCast, MascotID.allCases.allSatisfy {
            state.has(TrophyFact.mascotSeen($0))
        })
        // Both guarded on a real bound. An unset snapshot has the size and
        // both limits at zero, and `0 >= 0` is true — so without the guard a
        // caller that simply never mentioned the badge would be handed a
        // trophy for dragging it somewhere.
        award(.bigBadge, snapshot.badgeMaximum > 0
              && snapshot.badgeTileSize >= snapshot.badgeMaximum)
        award(.tinyBadge, snapshot.badgeMinimum > 0
              && snapshot.badgeTileSize <= snapshot.badgeMinimum)
        award(.pancakePress, state.has(TrophyFact.usedStackedFilter))
        award(.regular, state.runningDays >= 7)
        award(.veteran, state.runningDays >= 30)
        award(.upToDate, state.has(TrophyFact.installedOfferedUpdate))

        // MARK: Hidden

        let home = snapshot.homeRepo
        let mineAtHome = !home.isEmpty && mine.contains { $0.repo == home }
        let reviewAtHome = !home.isEmpty && snapshot.reviews.contains { $0.repo == home }
        award(.homeTeam, mineAtHome)
        award(.peerReview, reviewAtHome)
        award(.fullCircle, mineAtHome && reviewAtHome)
        award(.palindrome, mine.contains { isPalindrome($0.number) })
        award(.zeroSum, mine.contains { $0.additions > 0 && $0.additions == $0.deletions })
        award(.carousel, snapshot.mascotCyclesThisSession >= 10)
        award(.fourCorners, state.flags.filter { $0.hasPrefix(TrophyFact.cornerPrefix) }.count >= 4)

        // MARK: Commit

        let fresh = Trophy.all
            .map(\.id)
            .filter { earns.contains($0) && !state.isUnlocked($0) }
        for id in fresh {
            state.unlock(id, at: snapshot.now)
        }

        // The silent backfill. Everything already true is on the shelf and
        // marked unseen, so the room has something in it and the button has
        // its dot — but nothing is announced, because none of it happened
        // while anybody was watching.
        guard state.established else {
            state.established = true
            return (state, [])
        }
        return (state, fresh)
    }
}

extension TrophyEvaluator {

    /// `yyyy-MM-dd` in the snapshot's calendar.
    ///
    /// Built from components rather than a `DateFormatter`: a formatter
    /// carries a locale, and a locale can render this in a numbering system
    /// that makes yesterday sort after today.
    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d",
                      parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// How deep the deepest stack among these pull requests runs.
    ///
    /// Resolved against the list itself, the same way `MyPRGrouping` does it:
    /// a link to a pull request that is not here is not a stack, it is a
    /// dangling reference to something already merged.
    static func deepestStack(_ items: [MyPullRequest]) -> Int {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        func parent(of item: MyPullRequest) -> MyPullRequest? {
            guard let number = item.stackedOn else { return nil }
            return byID["\(item.repo)#\(number)"]
        }

        var best = items.isEmpty ? 0 : 1
        for item in items {
            var depth = 1
            var walker = item
            // Bounded by the list length, so a cycle in the data — which
            // GitHub should never produce and this code must survive anyway —
            // stops rather than spins.
            while let next = parent(of: walker), depth <= items.count {
                depth += 1
                walker = next
            }
            best = max(best, depth)
        }
        return best
    }

    /// Whether two pull requests sit on the same parent, making the stack a
    /// tree rather than a line.
    static func hasBranchingStack(_ items: [MyPullRequest]) -> Bool {
        let present = Set(items.map(\.id))
        var children: [String: Int] = [:]
        for item in items {
            guard let number = item.stackedOn else { continue }
            let parent = "\(item.repo)#\(number)"
            guard present.contains(parent) else { continue }
            children[parent, default: 0] += 1
        }
        return children.values.contains { $0 >= 2 }
    }

    /// Three digits minimum. `#11` reads the same backwards and is not worth a
    /// trophy — about one pull request in ten would earn it, which is not a
    /// coincidence, it is just how counting works.
    static func isPalindrome(_ number: Int) -> Bool {
        let digits = String(number)
        return digits.count >= 3 && digits == String(digits.reversed())
    }
}
