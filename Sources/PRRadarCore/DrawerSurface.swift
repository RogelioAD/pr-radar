import Foundation

/// Everything the drawer can be showing below its header.
///
/// Not the same thing as `DrawerTab`, and deliberately so. A tab is something
/// the tab strip offers; a room is reached from the header and *replaces* the
/// strip, so putting one in `DrawerTab` would have it appear as a button in the
/// very control it hides.
///
/// What the two share is geometry. Each surface measures its own rows, and the
/// drawer remembers a dragged height per surface — a grid row is 64pt and a My
/// PRs row can be four times that, so one shared height would fight itself
/// exactly the way the two tabs already would.
///
/// The raw values match `DrawerTab`'s on purpose: they are the namespace for
/// stored row heights and the suffix of the persisted drawer-height key, so
/// anyone upgrading keeps the heights they already dragged to.
public enum DrawerSurface: String, CaseIterable, Sendable {
    case reviews
    case mine
    case trophies
    case settings

    public init(_ tab: DrawerTab) {
        switch tab {
        case .reviews: self = .reviews
        case .mine: self = .mine
        }
    }
}
