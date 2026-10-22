import Foundation

/// What a key press in the open drawer means.
///
/// A type rather than a `switch` inside the panel, so the mapping can be
/// tested without a window — and so the one place that decides what `S` does
/// is not three hundred lines into an event handler.
public enum KeyCommand: Equatable, Sendable {
    case moveDown
    case moveUp
    case open
    case snooze
    case collapse
    case tab(Int)
    case refresh

    /// Characters, not key codes. The drawer's keys are all letters, arrows
    /// and Return, and a layout that puts `s` somewhere else should still
    /// snooze on the key marked `s`.
    public static func from(characters: String, keyCode: UInt16,
                            hasCommand: Bool, hasOption: Bool,
                            hasControl: Bool) -> KeyCommand? {
        // Nothing here is a chord except the tab switches. A modifier held
        // over a letter belongs to whatever shortcut the user meant, and
        // swallowing it would make the drawer eat ⌘Q.
        if hasCommand {
            switch characters {
            case "1": return .tab(0)
            case "2": return .tab(1)
            case "r": return .refresh
            default: return nil
            }
        }
        guard !hasOption, !hasControl else { return nil }

        switch keyCode {
        case 125: return .moveDown     // ↓
        case 126: return .moveUp       // ↑
        case 36, 76: return .open      // Return, Enter
        case 53: return .collapse      // Esc
        default: break
        }

        switch characters.lowercased() {
        case "j": return .moveDown
        case "k": return .moveUp
        case "s": return .snooze
        default: return nil
        }
    }
}

/// Where the selection is, and how it moves.
///
/// Separate from the list it indexes, because the list is rebuilt on every
/// poll and the selection has to survive that: it is held as an **id** rather
/// than an index, so a pull request arriving above the selected row does not
/// silently move the selection onto its neighbour.
public struct Selection: Equatable, Sendable {
    public private(set) var id: String?

    public init(id: String? = nil) { self.id = id }

    /// Moves by one, selecting the first row when nothing is selected yet.
    ///
    /// Stops at the ends rather than wrapping. A list you are stepping through
    /// to clear is one you want to reach the bottom of and know it; wrapping
    /// to the top silently starts you round again.
    public mutating func move(by delta: Int, in ids: [String]) {
        guard !ids.isEmpty else { id = nil; return }
        guard let current = id, let index = ids.firstIndex(of: current) else {
            id = delta >= 0 ? ids.first : ids.last
            return
        }
        let next = index + delta
        guard ids.indices.contains(next) else { return }
        id = ids[next]
    }

    /// Drops a selection whose row is gone, so Return cannot open something
    /// that is no longer on screen.
    public mutating func validate(against ids: [String]) {
        guard let current = id else { return }
        if !ids.contains(current) { id = ids.first }
    }

    public mutating func clear() { id = nil }
    public mutating func select(_ newID: String?) { id = newID }
}
