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
        static let seenComments = "seen.comments"
        static let notifyComments = "notify.comments"
        static let notifyBotComments = "notify.botComments"
        static let sortOrder = "list.sortOrder"
        static let drawerContentHeight = "drawer.contentHeight"
        static let selectedTab = "drawer.selectedTab"
        static let myPRSortOrder = "mine.sortOrder"
        static let myPRFilter = "mine.filter"
        static let myPRStackedOnly = "mine.stackedOnly"
        static let celebrateCleared = "celebrate.cleared"
        static let widgetVisible = "badge.visible"
        static let leadsByRepo = "leads.byRepo"
        static let repoFilter = "list.repoFilter"
        static let accountFilter = "list.accountFilter"
        static let updateRepo = "update.repo"
        static let notifiedUpdate = "update.notifiedVersion"
        static let mascot = "mascot.choice"
        static let seenCastNotice = "mascot.seenCastNotice"
        static let trophies = "trophies.state"
        static let drawerRoom = "drawer.room"
        /// Superseded by `drawerRoom`. Still read once, to carry an upgrader
        /// who left the drawer sitting in the trophy room.
        static let legacyShowingTrophies = "drawer.showingTrophies"
        static let reviewAuto = "review.auto"
        static let reviewSkill = "review.skill"

        static let claudePath = "review.claudePath"
        static let reviewMode = "review.mode"
        /// Superseded by `reviewMode`. Still read once, to carry anyone who had
        /// already turned automatic posting off.
        static let reviewAutoPost = "review.autoPost"
        static let reviewRepos = "review.repos"
        static let reviewWorkspace = "review.workspace"
        static let reviewModel = "review.model"
        static let reviewBudget = "review.budget"
        static let reviewMaxPerHour = "review.maxPerHour"
        static let reviewLog = "review.log"

        static let resolveSkill = "resolve.skill"
        static let resolveMode = "resolve.mode"
        static let resolveRepos = "resolve.repos"
        static let resolveOutOfScope = "resolve.outOfScope"
        static let resolvePending = "resolve.pending"
        static let resolveGates = "resolve.gates"
        static let resolveBudget = "resolve.budget"
        static let resolveTimeout = "resolve.timeoutMinutes"
        static let resolveLog = "resolve.log"
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
            guard let raw = defaults.string(forKey: Key.mascot) else { return .blip }
            if raw == mascotOffValue { return nil }
            return MascotID(rawValue: raw) ?? .blip
        }
        set { defaults.set(newValue?.rawValue ?? mascotOffValue, forKey: Key.mascot) }
    }

    private static let mascotOffValue = "off"

    /// The cohort whose arrival notice has already been seen, as
    /// `MascotCohort`'s raw value.
    ///
    /// The cohort rather than a boolean, so the next group of characters is
    /// news again instead of inheriting a flag set years earlier.
    public static var seenCastNotice: String? {
        get { defaults.string(forKey: Key.seenCastNotice) }
        set { defaults.set(newValue, forKey: Key.seenCastNotice) }
    }

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
    /// Whether the widget is on the desktop at all.
    ///
    /// One switch, answered once, in the menu bar — not a condition the app
    /// re-evaluates behind you.
    ///
    /// It used to hide itself whenever nothing was waiting and you had no open
    /// pull requests, which sounds tidy and is not: the drawer collapses when
    /// you click away from it, so a widget opened to change one setting was
    /// gone again at the next poll, and the thing you most want to be able to
    /// reach vanished at the exact moment it was least in the way. Worse, it
    /// made "is it running?" and "do I have work?" the same question, so the
    /// answer to the first was always inferred from the second.
    ///
    /// Now it is on until you say otherwise and off until you say otherwise.
    /// The menu bar icon is always there either way, so turning it off cannot
    /// strand you.
    public static var widgetVisible: Bool {
        get {
            guard defaults.object(forKey: Key.widgetVisible) != nil else { return true }
            return defaults.bool(forKey: Key.widgetVisible)
        }
        set { defaults.set(newValue, forKey: Key.widgetVisible) }
    }

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

    /// The review skill to run, as the user types it — `/my-review`.
    ///
    /// Deliberately not hardcoded and deliberately not a picker: which review
    /// skill a developer has is theirs, and a list here would go stale the
    /// first time they installed another one.
    ///
    /// It also has to be one they *wrote for this*. An ordinary interactive
    /// review skill — `/code-review` among them — asks questions, posts on its
    /// own account and answers in prose, and headless there means a quarter of
    /// an hour of nothing followed by a timeout. The field says so.
    public static var reviewSkill: String? {
        get { defaults.string(forKey: Key.reviewSkill) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.reviewSkill) }
            else { defaults.removeObject(forKey: Key.reviewSkill) }
        }
    }

    /// A `claude` binary named by hand, for a setup neither the candidate list
    /// nor the login shell turns up.
    ///
    /// Worth having because the failure it answers is total and silent: the
    /// room says "Claude Code is not installed" and there is nothing the
    /// developer can do about it from inside the app, however plainly they can
    /// see the binary in their own terminal.
    public static var claudePath: String? {
        get { defaults.string(forKey: Key.claudePath) }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty { defaults.set(trimmed, forKey: Key.claudePath) }
            else { defaults.removeObject(forKey: Key.claudePath) }
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

    /// How many reviews may *start* in any rolling hour. Zero means no cap.
    ///
    /// Six, which is what it was when it was hardcoded — the point of surfacing
    /// it is not a better default but a visible one. A row that says "hourly
    /// limit reached" is naming a number, and a number nobody can see or change
    /// reads as the feature having quietly broken.
    ///
    /// Counted from the moment a review *starts*, so a run that fails still
    /// spends its slot. That is the honest accounting — a failed review costs
    /// the same tokens as one that worked — but it does mean a broken setup
    /// burns the hour twice as fast as it looks like it should.
    public static var reviewMaxPerHour: Int {
        get {
            guard defaults.object(forKey: Key.reviewMaxPerHour) != nil else { return 6 }
            return max(0, defaults.integer(forKey: Key.reviewMaxPerHour))
        }
        set { defaults.set(max(0, newValue), forKey: Key.reviewMaxPerHour) }
    }

    /// Every automatic review the app remembers, as one JSON blob — the same
    /// shape, and for the same reason, as `trophyState`.
    public static var autoReviewLog: AutoReviewLog {
        get { AutoReviewLog.decoded(from: defaults.data(forKey: Key.reviewLog)) }
        set { defaults.set(newValue.encoded(), forKey: Key.reviewLog) }
    }

    /// Whether somebody commenting on one of your own pull requests is worth a
    /// banner.
    ///
    /// On by default. The row has always carried the count and the count has
    /// always been the wrong unit for this: it says there is post, never that
    /// something has just arrived.
    public static var notifyComments: Bool {
        get {
            guard defaults.object(forKey: Key.notifyComments) != nil else { return true }
            return defaults.bool(forKey: Key.notifyComments)
        }
        set { defaults.set(newValue, forKey: Key.notifyComments) }
    }

    /// Whether a machine counts.
    ///
    /// On by default, and a separate switch rather than folded into the one
    /// above, because the two are genuinely different appetites: bots are most
    /// of the volume on a busy repo and also most of what there is to answer.
    /// Somebody who wants the humans and not the robots can have that without
    /// turning the feature off.
    public static var notifyBotComments: Bool {
        get {
            guard defaults.object(forKey: Key.notifyBotComments) != nil else { return true }
            return defaults.bool(forKey: Key.notifyBotComments)
        }
        set { defaults.set(newValue, forKey: Key.notifyBotComments) }
    }

    /// Comments already announced, by `PRComment.id`.
    ///
    /// Its own store rather than sharing `seenPings`, so that clearing one
    /// cannot silence the other — and because they fill at very different
    /// rates: a busy pull request produces more comments in a morning than you
    /// get review requests in a month, and one shared 400-entry window would
    /// let the comments evict the pings.
    public static var seenComments: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.seenComments) ?? []) }
        set {
            let trimmed = newValue.count > 600 ? Set(newValue.prefix(600)) : newValue
            defaults.set(Array(trimmed), forKey: Key.seenComments)
        }
    }

    // MARK: - Resolve

    /// The skill that answers threads on your own pull requests.
    ///
    /// Its own setting rather than the review skill reused, because they are
    /// opposite jobs: one reads and reports, the other edits and pushes. A
    /// developer who has both has two skills, and the one that writes is not a
    /// mode of the one that reads.
    public static var resolveSkill: String? {
        get { defaults.string(forKey: Key.resolveSkill) }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.resolveSkill) }
            else { defaults.removeObject(forKey: Key.resolveSkill) }
        }
    }

    /// How much of a resolve run happens without being looked at.
    ///
    /// Defaults to `.curated`, and an unrecognised value reads as `.triage`
    /// rather than as anything else. A build that cannot understand the stored
    /// mode must not resolve that doubt by editing somebody's checkout.
    public static var resolveMode: ResolveMode {
        get {
            guard let raw = defaults.string(forKey: Key.resolveMode) else { return .curated }
            return ResolveMode(rawValue: raw) ?? .triage
        }
        set { defaults.set(newValue.rawValue, forKey: Key.resolveMode) }
    }

    /// The repositories resolve is allowed to write in.
    ///
    /// **A second allowlist, not the review one reused.** Safe-to-read and
    /// safe-to-write are different questions, and sharing one list would answer
    /// the second with an answer given to the first: ticking a repo so a review
    /// could read it would silently also let an unattended session commit and
    /// push there. Resolve ticks therefore start empty even for a repo already
    /// ticked for review.
    public static var resolveRepos: [String] {
        get { defaults.stringArray(forKey: Key.resolveRepos) ?? [] }
        set { defaults.set(newValue, forKey: Key.resolveRepos) }
    }

    /// What a run does about work outside the pull request's stated job.
    public static var resolveOutOfScope: ResolveOutOfScope {
        get {
            guard let raw = defaults.string(forKey: Key.resolveOutOfScope)
            else { return .deferWithReasoning }
            return ResolveOutOfScope(rawValue: raw) ?? .leaveOpen
        }
        set { defaults.set(newValue.rawValue, forKey: Key.resolveOutOfScope) }
    }

    /// What a run does about an unsubmitted draft review of your own.
    ///
    /// Defaults to leaving it, because publishing one releases every comment in
    /// somebody's draft at once — including ones written weeks ago — rather
    /// than this run's replies.
    public static var resolvePending: ResolvePendingPolicy {
        get {
            guard let raw = defaults.string(forKey: Key.resolvePending) else { return .leave }
            return ResolvePendingPolicy(rawValue: raw) ?? .leave
        }
        set { defaults.set(newValue.rawValue, forKey: Key.resolvePending) }
    }

    /// How much checking a run does before committing.
    ///
    /// Defaults to `.full`, which is the thorough answer and the slow one. An
    /// unrecognised value also reads as `.full`: a build that cannot understand
    /// the stored setting must not resolve that doubt by checking less.
    public static var resolveGates: ResolveGates {
        get {
            guard let raw = defaults.string(forKey: Key.resolveGates) else { return .full }
            return ResolveGates(rawValue: raw) ?? .full
        }
        set { defaults.set(newValue.rawValue, forKey: Key.resolveGates) }
    }

    /// The ceiling on one resolve run, in dollars. Zero means no ceiling.
    ///
    /// Higher than a review's, because the work is longer: this one reads every
    /// thread, writes the fixes, and runs the repository's own gates.
    public static var resolveBudget: Double {
        get {
            guard defaults.object(forKey: Key.resolveBudget) != nil else { return 25 }
            return defaults.double(forKey: Key.resolveBudget)
        }
        set { defaults.set(max(0, newValue), forKey: Key.resolveBudget) }
    }

    /// How long one run may take, in minutes.
    ///
    /// Ninety, where a review gets fifteen. Not a near miss: a run here applies
    /// fixes, runs the whole test suite for the platform it touched, and then
    /// commits behind a pre-commit hook that runs the suite again. Fifteen
    /// minutes would time out mid-commit on every real repository.
    ///
    /// Surfaced rather than hardcoded, for the reason the hourly review limit
    /// was: a ceiling nobody can see reads as the feature having broken.
    public static var resolveTimeoutMinutes: Int {
        get {
            guard defaults.object(forKey: Key.resolveTimeout) != nil else { return 90 }
            return max(5, defaults.integer(forKey: Key.resolveTimeout))
        }
        set { defaults.set(max(5, newValue), forKey: Key.resolveTimeout) }
    }

    public static var resolveLog: ResolveLog {
        get { ResolveLog.decoded(from: defaults.data(forKey: Key.resolveLog)) }
        set { defaults.set(newValue.encoded(), forKey: Key.resolveLog) }
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
