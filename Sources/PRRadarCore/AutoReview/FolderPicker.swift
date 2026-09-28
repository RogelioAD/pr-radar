import Foundation

/// The rules behind walking a folder tree in a menu.
///
/// Here rather than in the view for the usual reason: which entries are worth
/// offering, what counts as the top, and how a path is written down for a human
/// are all decisions, and decisions belong somewhere they can be argued with.
/// What is left to the view is the one thing that needs the disk — asking what
/// is actually in a directory.
public enum FolderPicker {

    /// How many subfolders a menu will show before it stops.
    ///
    /// A home directory with four hundred entries in it produces a menu taller
    /// than the screen, which is not a chooser — it is a wall. The cap keeps
    /// the control usable; the count beside it says when something was left out
    /// so the list is never quietly lying about what is there.
    public static let limit = 60

    /// Subfolders worth offering, from a raw directory listing.
    ///
    /// Dot-directories are dropped: `.git`, `.build`, `.Trash` and the rest are
    /// machinery, and nobody keeps their clones in one. Sorted the way Finder
    /// sorts, so the order matches the window the user would otherwise be
    /// looking in.
    public static func visible(_ names: [String]) -> [String] {
        names
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The folder above this one, or nil at the top.
    ///
    /// Nil at `/` and nil for anything that is not an absolute path, so the
    /// menu's way up disappears rather than offering a step that goes nowhere.
    public static func parent(of path: String) -> String? {
        let trimmed = normalized(path)
        guard trimmed.hasPrefix("/"), trimmed != "/" else { return nil }
        let up = (trimmed as NSString).deletingLastPathComponent
        return up.isEmpty ? "/" : up
    }

    /// Strips a trailing slash, so `/w/` and `/w` are one folder rather than
    /// two — they are stored, compared and shown, and disagreeing about the
    /// slash would make the same place look like two.
    public static func normalized(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.count > 1, expanded.hasSuffix("/") else { return expanded }
        return String(expanded.dropLast())
    }

    /// How a path is written for a person: home as `~`, and nothing else.
    public static func display(_ path: String) -> String {
        let normalized = normalized(path)
        let home = NSHomeDirectory()
        if normalized == home { return "~" }
        if normalized.hasPrefix(home + "/") {
            return "~" + normalized.dropFirst(home.count)
        }
        return normalized
    }

    /// Just the folder's own name, for a menu item.
    public static func name(of path: String) -> String {
        let normalized = normalized(path)
        return normalized == "/" ? "/" : ((normalized as NSString).lastPathComponent)
    }

    /// What the room says under the picker.
    ///
    /// The count is the whole point of the control: you are not choosing a
    /// folder, you are choosing *the folder your clones are in*, and the only
    /// way to know you have found it is to be told how many are there. Saying
    /// "none" plainly is what stops a plausible-looking wrong choice sitting
    /// there until the first review fails.
    public static func summary(cloneCount: Int, subfolderCount: Int) -> String {
        switch cloneCount {
        case 0 where subfolderCount == 0: return "Nothing in here."
        case 0: return "No clones directly in here — try one of its subfolders."
        case 1: return "1 clone here."
        default: return "\(cloneCount) clones here."
        }
    }
}
