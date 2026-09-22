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

    /// Whether this surface is always exactly as tall as what it holds.
    ///
    /// True only for settings, and because of what it *is*: a form, not a list.
    /// A list has more of itself to show, so a height the user dragged to is a
    /// real instruction — "show me four rows" — and worth remembering. A form
    /// has a bottom. Every height other than its own either hides a setting or
    /// leaves a band of empty material under the last one, and neither is
    /// something anybody meant to ask for.
    ///
    /// The drag is disabled here rather than ignored, so the edge does not
    /// fight a pointer that will not move it.
    public var fitsContent: Bool { self == .settings }

    public init(_ tab: DrawerTab) {
        switch tab {
        case .reviews: self = .reviews
        case .mine: self = .mine
        }
    }
}
