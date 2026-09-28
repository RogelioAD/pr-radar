import Foundation

/// The groups the automatic-review room is divided into, in the order they
/// appear.
///
/// Named here rather than inline in the view for the reason `SettingsSection`
/// gives: the drawer sizes itself by counting and measuring rows, and a section
/// is one row's worth of that. Listing them in one enum is what keeps the count
/// the view draws and the count the geometry believes from drifting apart.
///
/// Order: whether it is running, then the thing it runs, then what it runs
/// against, then where it is allowed to.
public enum ReviewSection: String, CaseIterable, Sendable, Identifiable {
    case status
    case skill
    case clones
    case repositories

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .status: return "Status"
        case .skill: return "Skill"
        case .clones: return "Clones"
        case .repositories: return "Repositories"
        }
    }

    public var symbol: String {
        switch self {
        // The same wand the header button wears, so the switch and the room it
        // opens are visibly one idea.
        case .status: return "wand.and.sparkles"
        case .skill: return "terminal"
        case .clones: return "folder"
        // The same seal the lead chips wear, for the same reason the leads
        // section borrows it: a list of repositories you have vouched for.
        case .repositories: return "checkmark.seal"
        }
    }
}
