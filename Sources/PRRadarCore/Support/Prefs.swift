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
        static let leadLogins = "leads.logins"
        static let repoFilter = "list.repoFilter"
        static let updateRepo = "update.repo"
        static let notifiedUpdate = "update.notifiedVersion"
        static let mascot = "mascot.choice"
        static let trophies = "trophies.state"
        static let showingTrophies = "drawer.showingTrophies"
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

    /// Whether the drawer is showing the trophy room rather than a list.
    ///
    /// Persisted, like the selected tab, so the drawer opens on whatever you
    /// were last looking at. The tab underneath is kept as well, so leaving
    /// the room puts you back where you were rather than on the default tab.
    public static var showingTrophies: Bool {
        get { defaults.bool(forKey: Key.showingTrophies) }
        set { defaults.set(newValue, forKey: Key.showingTrophies) }
    }

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

    /// Overrides the built-in lead list, so a team change needs no rebuild.
    public static var leadLogins: [String] {
        get {
            let stored = defaults.stringArray(forKey: Key.leadLogins) ?? []
            return stored.isEmpty ? Leads.defaultLogins : stored
        }
        set { defaults.set(newValue, forKey: Key.leadLogins) }
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

    public static var seenPings: Set<String> {
        get { Set(defaults.stringArray(forKey: Key.seenPings) ?? []) }
        set {
            // Keep this from growing without bound across months of use.
            let trimmed = newValue.count > 400 ? Set(newValue.prefix(400)) : newValue
            defaults.set(Array(trimmed), forKey: Key.seenPings)
        }
    }
}
