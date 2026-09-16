import CoreGraphics

/// Measured row heights are stored under tab-namespaced keys
/// (`"reviews:owner/name#1"`) so the two tabs cannot collide.
///
/// Pruning them therefore has to strip the namespace before comparing against
/// live row ids. Comparing the raw keys matched nothing, which silently
/// discarded *every* measurement on each refresh — the drawer then fell back to
/// its per-row estimate and re-measured, visibly resizing itself twice per
/// poll. Extracted here so both tabs prune through one tested path.
public enum RowHeightKeys {

    public static func key(tab: DrawerTab, id: String) -> String {
        "\(tab.rawValue):\(id)"
    }

    /// Removes entries for rows of `tab` that are no longer present, leaving
    /// the other tab's entries untouched.
    public static func pruned(_ heights: [String: CGFloat],
                              tab: DrawerTab,
                              liveIDs: Set<String>) -> [String: CGFloat] {
        let prefix = "\(tab.rawValue):"
        return heights.filter { key, _ in
            guard key.hasPrefix(prefix) else { return true }
            return liveIDs.contains(String(key.dropFirst(prefix.count)))
        }
    }
}
