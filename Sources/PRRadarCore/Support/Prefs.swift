import Foundation

/// Small persisted bits: where the badge sits, and which pings we already
/// notified about.
public enum Prefs {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let badgeX = "badge.origin.x"
        static let badgeY = "badge.origin.y"
        static let badgeTile = "badge.tileSize"
        static let seenPings = "seen.pings"
        static let sortOrder = "list.sortOrder"
        static let drawerContentHeight = "drawer.contentHeight"
        static let selectedTab = "drawer.selectedTab"
        static let myPRSortOrder = "mine.sortOrder"
        static let myPRFilter = "mine.filter"
        static let myPRStackedOnly = "mine.stackedOnly"
        static let celebrateCleared = "celebrate.cleared"
        static let leadsByRepo = "leads.byRepo"
        static let repoFilter = "list.repoFilter"
        static let accountFilter = "list.accountFilter"
        static let updateRepo = "update.repo"
        static let notifiedUpdate = "update.notifiedVersion"
        static let mascot = "mascot.choice"
        static let trophies = "trophies.state"
        static let drawerRoom = "drawer.room"
        /// Superseded by `drawerRoom`. Still read once, to carry an upgrader
        /// who left the drawer sitting in the trophy room.
        static let legacyShowingTrophies = "drawer.showingTrophies"
        static let reviewAuto = "review.auto"
        static let reviewSkill = "review.skill"
        static let reviewMode = "review.mode"
        /// Superseded by `reviewMode`. Still read once, to carry anyone who had
        /// already turned automatic posting off.
        static let reviewAutoPost = "review.autoPost"
        static let reviewRepos = "review.repos"
        static let reviewWorkspace = "review.workspace"
        static let reviewModel = "review.model"
        static let reviewBudget = "review.budget"
        static let reviewLog = "review.log"
    }

    public static var badgeOrigin: CGPoint? {
        get {
            guard defaults.object(forKey: Key.badgeX) != nil,
                  defaults.object(forKey: Key.badgeY) != nil
            else { return nil }
            return CGPoint(x: defaults.double(forKey: Key.badgeX),
                           y: defaults.double(forKey: Key.badgeY))
        }
        set {
            guard let point = newValue else { return }
            defaults.set(point.x, forKey: Key.badgeX)
            defaults.set(point.y, forKey: Key.badgeY)
        }
    }

    /// The badge's square size in points, as dragged from one of its corners.
    ///
    /// nil means never resized, which is not the same as zero — the default is
    /// the user's Dock tile size, and that is the app's to decide rather than
    /// this store's.
    public static var badgeTileSize: CGFloat? {
        get {
            guard defaults.object(forKey: Key.badgeTile) != nil else { return nil }
            return CGFloat(defaults.double(forKey: Key.badgeTile))
        }
        set {
            if let newValue {
                defaults.set(Double(newValue), forKey: Key.badgeTile)
            } else {
                defaults.removeObject(forKey: Key.badgeTile)
            }
        }
    }

    public static var sortOrder: ReviewSortOrder {
        get {
            guard let raw = defaults.string(forKey: Key.sortOrder),
                  let order = ReviewSortOrder(rawValue: raw)
            else { return .oldestFirst }
            return order
        }
        set { defaults.set(newValue.rawValue, forKey: Key.sortOrder) }
    }

    /// The repo the drawer is narrowed to, as `owner/name`, or nil for all.
    ///
    /// Unlike the author filter this *is* persisted — "I'm working in one repo
    /// today" outlives a restart. The empty-drawer risk that keeps the author
    /// filter session-only is handled by validating it on every refresh and
    /// dropping it when it matches nothing.
    public static var repoFilter: String? {
        get { defaults.string(forKey: Key.repoFilter) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.repoFilter)
            } else {
                defaults.removeObject(forKey: Key.repoFilter)
            }
        }
    }

    /// Which account the lists are scoped to, by `host/login`. nil means all
    /// of them. Persisted like the repo scope, and validated on every refresh:
    /// an account logged out of between launches must not leave the app scoped
    /// to an identity it can no longer read, which would show an empty drawer
    /// that looks exactly like having nothing to do.
    public static var accountFilter: String? {
        get { defaults.string(forKey: Key.accountFilter) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.accountFilter)
            } else {
                defaults.removeObject(forKey: Key.accountFilter)
            }
        }
    }

    /// Which repository the update check watches. Overridable so a fork
    /// checks its own releases rather than the original's.
    public static var updateRepo: String {
        get { defaults.string(forKey: Key.updateRepo) ?? "RogelioAD/pr-radar" }
        set { defaults.set(newValue, forKey: Key.updateRepo) }
    }

    /// The newest version already announced, so one release notifies once.
    public static var notifiedUpdate: String? {
        get { defaults.string(forKey: Key.notifiedUpdate) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: Key.notifiedUpdate)
            } else {
                defaults.removeObject(forKey: Key.notifiedUpdate)
            }
        }
    }

    /// Which character keeps you company, or nil for none.
    ///
    /// Stored as a string rather than an index so reordering the cast never
    /// silently changes somebody's pick. An unrecognised value — a character
    /// that existed in an older build — falls back to the default rather than
    /// to nothing, because a missing mascot looks like a bug and a different
    /// one looks like a choice.
    public static var mascot: MascotID? {
        get {
            guard let raw = defaults.string(forKey: Key.mascot) else { return .pip }
            if raw == mascotOffValue { return nil }
            return MascotID(rawValue: raw) ?? .pip
        }
        set { defaults.set(newValue?.rawValue ?? mascotOffValue, forKey: Key.mascot) }
    }

    private static let mascotOffValue = "off"

    /// Whether the My PRs list is narrowed to stacks.
    ///
    /// A second axis rather than another `MyPRFilter` case: "show me the stack I
    /// am juggling" is a different question from "show me what is broken", and
    /// answering both at once is the useful combination.
    public static var myPRStackedOnly: Bool {
        get { defaults.bool(forKey: Key.myPRStackedOnly) }
        set { defaults.set(newValue, forKey: Key.myPRStackedOnly) }
    }

    /// Whether clearing the review queue drops the achievement banner.
    ///
    /// Defaults on, and has no UI: it fires rarely enough to be a pleasure
    /// rather than an interruption. `defaults write ... celebrate.cleared
    /// -bool false` for anyone who disagrees.
    public static var celebrateCleared: Bool {
        get {
            guard defaults.object(forKey: Key.celebrateCleared) != nil else { return true }
            return defaults.bool(forKey: Key.celebrateCleared)
        }
        set { defaults.set(newValue, forKey: Key.celebrateCleared) }
    }

    /// The trophy shelf, as one JSON blob.
    ///
    /// One key rather than a key per trophy: the whole thing is rewritten on
    /// every refresh, and thirty writes to say nothing changed is twenty-nine
    /// more than the job needs. Decoding is total — a corrupt or absent value
    /// reads as an empty shelf rather than throwing, because a trophy room is
    /// not worth failing a launch over.
    public static var trophyState: TrophyState {
        get { TrophyState.decoded(from: defaults.data(forKey: Key.trophies)) }
        set { defaults.set(newValue.encoded(), forKey: Key.trophies) }
    }

    /// Which room the drawer is sitting in, or nil for the ordinary tabs.
    ///
    /// Persisted, like the selected tab, so the drawer opens on whatever you
    /// were last looking at. The tab underneath is kept as well, so leaving a
    /// room puts you back where you were rather than on the default tab.
    ///
    /// Stored as a string with an explicit "none", the way the mascot is, so
    /// that "no room" and "never asked" are different values in the store —
    /// which is what lets the old boolean be read exactly once, on the first
    /// launch after upgrading, and never consulted again.
    ///
    /// An unrecognised value reads as no room rather than as a fault: a build
    /// that drops a room should put someone back in the drawer, not strand
    /// them in a surface it can no longer draw.
    public static var drawerRoom: DrawerRoom? {
        get {
            guard let raw = defaults.string(forKey: Key.drawerRoom) else {
                return defaults.bool(forKey: Key.legacyShowingTrophies) ? .trophies : nil
            }
            return raw == noRoomValue ? nil : DrawerRoom(rawValue: raw)
        }
        set { defaults.set(newValue?.rawValue ?? noRoomValue, forKey: Key.drawerRoom) }
    }

    private static let noRoomValue = "none"

    public static var selectedTab: DrawerTab {
        get {
            defaults.string(forKey: Key.selectedTab)
                .flatMap(DrawerTab.init(rawValue:)) ?? .reviews
        }
        set { defaults.set(newValue.rawValue, forKey: Key.selectedTab) }
    }

    public static var myPRSortOrder: MyPRSortOrder {
        get {
            defaults.string(forKey: Key.myPRSortOrder)
                .flatMap(MyPRSortOrder.init(rawValue:)) ?? .newestFirst
        }
        set { defaults.set(newValue.rawValue, forKey: Key.myPRSortOrder) }
    }

    public static var myPRFilter: MyPRFilter {
        get {
            defaults.string(forKey: Key.myPRFilter)
                .flatMap(MyPRFilter.init(rawValue:)) ?? .all
        }
        set { defaults.set(newValue.rawValue, forKey: Key.myPRFilter) }
    }

    /// Leads per repository, keyed by lowercase `owner/repo`.
    public static var leadsByRepo: [String: [String]] {
        get { defaults.dictionary(forKey: Key.leadsByRepo) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: Key.leadsByRepo) }
    }

    /// Height of the row list the user dragged the drawer to, if they have.
    /// Stored per surface: My PR rows are much taller than review rows and a
    /// trophy grid row is shorter than either, so one shared height would
    /// fight itself every time the drawer changed what it was showing.
    ///
    /// The author filter is deliberately *not* persisted: restoring one would
    /// show an empty drawer next to a non-zero badge.
    public static func drawerContentHeight(for surface: DrawerSurface) -> CGFloat? {
        let key = "\(Key.drawerContentHeight).\(surface.rawValue)"
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }

    public static func setDrawerContentHeight(_ height: CGFloat?, for surface: DrawerSurface) {
        let key = "\(Key.drawerContentHeight).\(surface.rawValue)"
        if let height {
            defaults.set(Double(height), forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Automatic review

    /// Whether PR Radar reviews the PRs waiting on you by itself.
    ///
    /// Off until asked, and inert without `reviewSkill` — the header toggle
    /// sends you to Settings rather than turning on a feature that has nothing
    /// to run.
    public static var autoReview: Bool {
        get { defaults.bool(forKey: Key.reviewAuto) }
        set { defaults.set(newValue, forKey: Key.reviewAuto) }
    }

    /// The review skill to run, as the user types it — `/code-review`.
    ///
    /// Deliberately not hardcoded and deliberately not a picker: which review
    /// skill a developer has is theirs, and a list here would go stale the
    /// first time they installed another one.
    public static var reviewSkill: String? {
        get { defaults.string(forKey: Key.reviewSkill) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.reviewSkill) }
            else { defaults.removeObject(forKey: Key.reviewSkill) }
        }
    }

    /// How much of a finished review goes out without being looked at.
    ///
    /// Superseded the old `review.autoPost` boolean, which is still read once
    /// so that anyone who had turned posting off does not silently get it back
    /// on: off meant "let me see it first", which is exactly `.curated`.
    ///
    /// An unrecognised value reads as `.curated` rather than `.automatic`. A
    /// build that cannot understand the stored mode must not resolve that
    /// doubt by posting to somebody's pull request.
    public static var reviewMode: AutoReviewMode {
        get {
            if let raw = defaults.string(forKey: Key.reviewMode) {
                return AutoReviewMode(rawValue: raw) ?? .curated
            }
            guard defaults.object(forKey: Key.reviewAutoPost) != nil else { return .automatic }
            return defaults.bool(forKey: Key.reviewAutoPost) ? .automatic : .curated
        }
        set { defaults.set(newValue.rawValue, forKey: Key.reviewMode) }
    }

    /// The repositories automatic review is allowed to touch, as `owner/name`.
    ///
    /// An allowlist rather than a blocklist, because the failure modes are not
    /// symmetric: forgetting to add a repo costs a review that did not happen,
    /// and forgetting to block one costs a comment on a stranger's PR.
    public static var reviewRepos: [String] {
        get { defaults.stringArray(forKey: Key.reviewRepos) ?? [] }
        set { defaults.set(newValue, forKey: Key.reviewRepos) }
    }

    /// Where the user's clones live, so a review has code to read.
    public static var reviewWorkspace: String? {
        get { defaults.string(forKey: Key.reviewWorkspace) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.reviewWorkspace) }
            else { defaults.removeObject(forKey: Key.reviewWorkspace) }
        }
    }

    /// An explicit model for the review session, or nil to let the CLI choose.
    public static var reviewModel: String? {
        get { defaults.string(forKey: Key.reviewModel) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.reviewModel) }
            else { defaults.removeObject(forKey: Key.reviewModel) }
        }
    }

    /// The ceiling on one review, in dollars. Zero means no ceiling, which is
    /// a choice rather than a default.
    ///
    /// Ten, because the first real measurement of this was $3.89 for one review
    /// of one pull request — and the fifty cents it defaulted to before that
    /// was not a cautious ceiling, it was a guarantee of failure. Every review
    /// died partway through, exited non-zero, and reported nothing useful. A
    /// cap is worth having; a cap below the cost of the thing it caps is just a
    /// slow way of turning the feature off.
    public static var reviewBudget: Double {
        get {
            guard defaults.object(forKey: Key.reviewBudget) != nil else { return 10 }
            return defaults.double(forKey: Key.reviewBudget)
        }
        set { defaults.set(newValue, forKey: Key.reviewBudget) }
    }

    /// Every automatic review the app remembers, as one JSON blob — the same
    /// shape, and for the same reason, as `trophyState`.
    public static var autoReviewLog: AutoReviewLog {
        get { AutoReviewLog.decoded(from: defaults.data(forKey: Key.reviewLog)) }
        set { defaults.set(newValue.encoded(), forKey: Key.reviewLog) }
    }

    public static var seenPings: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.seenPings) ?? []) }
        set {
            // Keep this from growing without bound across months of use.
            let trimmed = newValue.count > 400 ? Set(newValue.prefix(400)) : newValue
            defaults.set(Array(trimmed), forKey: Key.seenPings)
        }
    }
}
