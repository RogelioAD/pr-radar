import Foundation

/// A pull request that has landed in one of the repositories the user can see.
///
/// Deliberately not a `ReviewItem` and not a `MyPullRequest`. Both of those are
/// rows — things the drawer keeps, sorts, filters and counts. A merge is not a
/// row: it is an event with a lifetime of about three seconds, and the only
/// questions asked of it are *where*, *which one* and *when*.
///
/// Not restricted to the viewer's own work either. Something of yours going in
/// is already read off the lifetime count the trophies fetch — see
/// `AppDelegate.refresh`. This is the other half: a colleague's pull request
/// landing in a repository you work in, which nothing in the app said anything
/// about before.
public struct MergedPR: Identifiable, Equatable, Sendable {
    public let repo: String
    public let number: Int
    /// Who wrote it, rather than who pressed the button.
    ///
    /// On most teams those are the same person. Where they differ the author is
    /// the one the news is about — "alice's work went in" is what a colleague
    /// wants to hear, not "bob clicked merge".
    public let authorLogin: String
    public let mergedAt: Date

    public var id: String { "\(repo)#\(number)" }
    public var repoShortName: String { RepoScope.shortName(repo) }

    /// No title and no URL, deliberately. The banner says a repository and a
    /// number, it ignores the mouse like every other banner this app drops,
    /// and a pull request's description is a few kilobytes that would be
    /// fetched for every watched repository every sixty seconds in order to be
    /// thrown away. Nothing reads them, so nothing asks for them.
    public init(repo: String, number: Int, authorLogin: String, mergedAt: Date) {
        self.repo = repo
        self.number = number
        self.authorLogin = authorLogin
        self.mergedAt = mergedAt
    }
}

/// Which of the merges a refresh turned up are worth putting on screen, and
/// what to remember afterwards so none of them arrives twice.
///
/// Pure, like every other rule in this target, because the cases that matter
/// cannot be arranged on a Tuesday afternoon: a first launch, a laptop that was
/// shut for a week, eleven pull requests going in during a release, a repository
/// that drops out of the lists for one round because an account failed to
/// answer. All four are three lines of a test and none of them is something you
/// can wait for.
public enum MergeWatch {

    /// Turns one round's aliased payload into merges.
    ///
    /// Total, in the sense that nothing here can fail the round: a repository
    /// that came back null, a node with no number, a node the server sent
    /// without the one field that says *when* — each one drops the single
    /// merge it belongs to and leaves the rest alone. Being told about four of
    /// five merges is a fair outcome for a decoration; failing a refresh that
    /// is carrying both tabs is not.
    ///
    /// The repository comes off the node rather than off the alias it arrived
    /// under. The alias is positional, and positions are exactly the thing that
    /// goes wrong quietly — a name that failed to split would shift every one
    /// after it, and the banner would announce the right number against the
    /// wrong repo.
    public static func build(from payload: [String: MergesResult]) -> [MergedPR] {
        payload.values.flatMap { result in
            (result.pullRequests?.nodes ?? []).compactMap(merge(from:))
        }
    }

    private static func merge(from node: MergedNode) -> MergedPR? {
        guard let number = node.number,
              let repo = node.repository?.nameWithOwner,
              let mergedAt = node.mergedAt
        else { return nil }
        return MergedPR(repo: repo,
                        number: number,
                        // A pull request whose author has since deleted their
                        // account has none. The banner says "MERGED" on its own
                        // there rather than naming a ghost.
                        authorLogin: node.author?.login ?? "",
                        mergedAt: mergedAt)
    }

    /// Past this many in one round the queue is abandoned for a single line.
    ///
    /// Three, where the trophy banner allows five. A trophy burst is a backfill
    /// that happens once per machine; merges are other people's work landing all
    /// day, and a release train can put six in at once. Three banners is around
    /// eleven seconds of somebody's screen being used by something they did not
    /// ask for, which is about the limit of what an unprompted nod can spend.
    public static let maximumInARow = 3

    /// Nothing older than this is news.
    ///
    /// The seen-set alone would be enough to stop a merge being announced
    /// twice, and not enough to stop a backlog being announced once. A Mac
    /// closed on Friday and opened on Monday has ninety merges it has never
    /// seen, every one of them already read about in Slack — and a feature that
    /// opens with ninety banners is one that gets turned off in its first
    /// minute. An hour is "while I was at lunch", which is the window where
    /// this is actually telling you something.
    public static let freshness: TimeInterval = 3_600

    /// The merges this round should announce, oldest first.
    ///
    /// Oldest first so a burst reads in the order the work actually landed.
    ///
    /// `announced` empty means a first round — a fresh install, or the first
    /// one after this feature arrived — and a first round says nothing. The
    /// same rule `Notifier.notifyNewPings` follows, for the same reason: the
    /// twenty merges already in the window are not news, they are history, and
    /// opening with them is indistinguishable from a bug.
    public static func landed(_ candidates: [MergedPR],
                              announced: Set<String>,
                              now: Date = Date()) -> [MergedPR] {
        guard !announced.isEmpty else { return [] }
        return candidates
            .filter { !announced.contains($0.id) }
            // A merge timestamped in the future is a clock disagreeing with
            // GitHub's, not a prediction. `timeIntervalSince` goes negative
            // there, which passes this test — which is the right answer: it
            // just landed.
            .filter { now.timeIntervalSince($0.mergedAt) <= freshness }
            .sorted { $0.mergedAt < $1.mergedAt }
    }

    /// What to remember, given everything this round could see.
    ///
    /// Everything in the window is marked, not just what was announced — the
    /// rule `Notifier.notifyNewComments` spells out: something the freshness
    /// floor suppressed must not arrive in a burst later.
    ///
    /// The store prunes itself rather than being trimmed to a fixed size. An id
    /// that has fallen out of its repository's window can never come back, so
    /// forgetting it costs nothing; an arbitrary `prefix(400)` across a set, by
    /// contrast, forgets whichever ids the hash seed happened to put last.
    ///
    /// The one thing it must not do is forget a repository it did not look at.
    /// A round where one account failed returns no candidates for that
    /// account's repositories, and pruning on that would re-announce their last
    /// hour of merges the moment the account came back.
    public static func remembered(_ announced: Set<String>,
                                  seeing candidates: [MergedPR]) -> Set<String> {
        let asked = Set(candidates.map(\.repo))
        let live = Set(candidates.map(\.id))
        return announced.filter { !asked.contains(repo(of: $0)) }
            .union(live)
            .union([seeded])
    }

    /// Written on every round, so that an empty store means *never ran* and
    /// nothing else.
    ///
    /// Without it, "nothing has been announced yet" and "the repositories you
    /// watch have not merged anything yet" are the same value — and the first
    /// pull request ever to land in a brand-new set of repositories would be
    /// swallowed as though it were a backlog.
    ///
    /// Parenthesised because a GitHub owner or repository name cannot contain
    /// one, so this can never collide with a real id. It survives the prune
    /// above for the same reason: no round ever asks about a repository by
    /// this name.
    static let seeded = "(seeded)"

    /// The repository half of a `MergedPR.id`.
    ///
    /// Splitting on `#` is safe in the one direction that matters: a repository
    /// name cannot contain one, so everything before the first `#` is the repo
    /// however odd the rest looks.
    static func repo(of id: String) -> String {
        id.split(separator: "#", maxSplits: 1).first.map(String.init) ?? id
    }

    /// Every repository worth asking about, from what the two tabs turned up.
    ///
    /// *Available* is deliberately read as "appears in your lists", not as
    /// "your account can read it". The second is thousands of repositories for
    /// anyone in a large org, and being told that a stranger merged something
    /// in a repository you have never opened is noise with a progress bar in
    /// front of it. What you are working in is what the app already knows.
    ///
    /// Capped, and the cap is not a formality: this is one aliased query per
    /// repository on every poll, and somebody with reviews open across forty
    /// repositories would be spending the whole minute on it. The busiest ones
    /// are not knowable from here, so the cap takes them in name order — stable
    /// across rounds, which matters more than which ones it keeps, because a
    /// set that reshuffled every poll would announce a different slice of the
    /// same hour each time.
    public static func watchable(reviews: [String], mine: [String],
                                 limit: Int = 20) -> [String] {
        Array(RepoScope.names(reviews: reviews, mine: mine).prefix(limit))
    }
}
