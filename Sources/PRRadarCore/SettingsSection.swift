import Foundation

/// The groups the settings room is divided into, in the order they appear.
///
/// Named here rather than inline in the view because the drawer sizes itself by
/// counting and measuring rows, and a section is one row's worth of that: the
/// height snaps to whole groups, so a drag can never leave a toggle sheared in
/// half. Listing them in one enum is what keeps the count the view draws and
/// the count the geometry believes from drifting apart.
///
/// macOS order: the settings everyone changes first, then what the app is
/// watching, then how it looks, then the machinery underneath.
public enum SettingsSection: String, CaseIterable, Sendable, Identifiable {
    case general
    case leads
    case appearance
    case updates

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: return "General"
        case .leads: return "Leads"
        case .appearance: return "Appearance"
        case .updates: return "Updates"
        }
    }

    /// Set beside the title, at the size a grouped form's header uses.
    public var symbol: String {
        switch self {
        case .general: return "gearshape"
        // The same seal the lead chips wear on a row, so the setting and the
        // thing it governs are visibly one idea.
        case .leads: return "checkmark.seal"
        case .appearance: return "paintbrush"
        case .updates: return "arrow.down.circle"
        }
    }
}
