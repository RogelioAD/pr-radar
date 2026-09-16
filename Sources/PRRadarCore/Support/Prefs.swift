import Foundation

/// Small persisted bits: where the badge sits, and which pings we already
/// notified about.
public enum Prefs {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let badgeX = "badge.origin.x"
        static let badgeY = "badge.origin.y"
        static let seenPings = "seen.pings"
        static let sortOrder = "list.sortOrder"
        static let drawerContentHeight = "drawer.contentHeight"
        static let selectedTab = "drawer.selectedTab"
        static let myPRSortOrder = "mine.sortOrder"
        static let myPRFilter = "mine.filter"
        static let leadLogins = "leads.logins"
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

    public static var sortOrder: ReviewSortOrder {
        get {
            guard let raw = defaults.string(forKey: Key.sortOrder),
                  let order = ReviewSortOrder(rawValue: raw)
            else { return .oldestFirst }
            return order
        }
        set { defaults.set(newValue.rawValue, forKey: Key.sortOrder) }
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
    /// Stored per tab: My PR rows are much taller than review rows, so one
    /// shared height would fight itself every time the tab changed.
    ///
    /// The author filter is deliberately *not* persisted: restoring one would
    /// show an empty drawer next to a non-zero badge.
    public static func drawerContentHeight(for tab: DrawerTab) -> CGFloat? {
        let key = "\(Key.drawerContentHeight).\(tab.rawValue)"
        guard defaults.object(forKey: key) != nil else { return nil }
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }

    public static func setDrawerContentHeight(_ height: CGFloat?, for tab: DrawerTab) {
        let key = "\(Key.drawerContentHeight).\(tab.rawValue)"
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
