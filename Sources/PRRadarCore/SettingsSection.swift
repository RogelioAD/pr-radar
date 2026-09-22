import Foundation

/// The groups the settings room is divided into, in the order they appear.
///
/// Named here rather than inline in the view because the drawer sizes itself by
/// counting and measuring rows, and a section is one row's worth of that: the
/// height snaps to whole groups, so a drag can never leave a toggle sheared in
/// half. Listing them in one enum is what keeps the count the view draws and
/// the count the geometry believes from drifting apart.
///
/// Order: who the app is looking as, then the settings everyone changes, then
/// what it is watching, then how it looks, then the machinery underneath.
public enum SettingsSection: String, CaseIterable, Sendable, Identifiable {
    case accounts
    case general
    case leads
    case appearance
    case updates

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accounts: return "Accounts"
        case .general: return "General"
        case .leads: return "Leads"
        case .appearance: return "Appearance"
        case .updates: return "Updates"
        }
    }

    /// Set beside the title, at the size a grouped form's header uses.
    public var symbol: String {
        switch self {
        // The same profile glyph the account picker wears in the filter bar.
        case .accounts: return "person.crop.circle"
        case .general: return "gearshape"
        // The same seal the lead chips wear on a row, so the setting and the
        // thing it governs are visibly one idea.
        case .leads: return "checkmark.seal"
        case .appearance: return "paintbrush"
        case .updates: return "arrow.down.circle"
        }
    }
}
