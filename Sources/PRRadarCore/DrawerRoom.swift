import Foundation

/// A surface reached from the header rather than from the tab strip, which
/// takes over everything below the header while it is open.
///
/// An enum rather than a flag per room, because the rooms are alternatives and
/// a pair of booleans can say something that has no meaning: the trophy shelf
/// and the settings panel both open at once. With one optional there is no such
/// value to write, so no call site has to remember to close the other.
///
/// `nil` — the absence of a room — is the drawer doing its actual job: a tab,
/// its filter bar, and a list.
public enum DrawerRoom: String, CaseIterable, Sendable {
    case trophies
    case settings

    /// The geometry this room measures and remembers its height under.
    public var surface: DrawerSurface {
        switch self {
        case .trophies: return .trophies
        case .settings: return .settings
        }
    }
}
