import CoreGraphics

/// Measured row heights are stored under surface-namespaced keys
/// (`"reviews:owner/name#1"`) so no two surfaces can collide.
///
/// Pruning them therefore has to strip the namespace before comparing against
/// live row ids. Comparing the raw keys matched nothing, which silently
/// discarded *every* measurement on each refresh — the drawer then fell back to
/// its per-row estimate and re-measured, visibly resizing itself twice per
/// poll. Extracted here so both tabs prune through one tested path.
public enum RowHeightKeys {

    public static func key(surface: DrawerSurface, id: String) -> String {
        "\(surface.rawValue):\(id)"
    }

    /// Removes entries for rows of `surface` that are no longer present,
    /// leaving every other surface's entries untouched.
    public static func pruned(_ heights: [String: CGFloat],
                              surface: DrawerSurface,
                              liveIDs: Set<String>) -> [String: CGFloat] {
        let prefix = "\(surface.rawValue):"
        return heights.filter { key, _ in
            guard key.hasPrefix(prefix) else { return true }
            return liveIDs.contains(String(key.dropFirst(prefix.count)))
        }
    }
}
