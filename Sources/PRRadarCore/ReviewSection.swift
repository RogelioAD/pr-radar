import Foundation

/// The groups the automatic-review room is divided into, in the order they
/// appear.
///
/// Named here rather than inline in the view for the reason `SettingsSection`
/// gives: the drawer sizes itself by counting and measuring rows, and a section
/// is one row's worth of that. Listing them in one enum is what keeps the count
/// the view draws and the count the geometry believes from drifting apart.
///
/// Order: what is happening, then each feature in one unbroken block, then the
/// setup they share.
///
/// It was not that. Reviewing's settings came first, then the clones folder,
/// then resolving's, then its answers, then the repository list — so the two
/// features were interleaved with the two groups that belong to both, and
/// reading down the room meant switching subject four times. Clones and
/// repositories are configured once and then forgotten; they go last, together,
/// where a thing you set up once belongs.
///
/// The raw values are persisted: they are row-height keys. Renaming one
/// silently discards whatever the drawer had been sized to.
public enum ReviewSection: String, CaseIterable, Sendable, Identifiable {
    case status
    case skill
    case resolve
    case resolveAnswers
    case clones
    case repositories

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .status: return "Status"
        case .skill: return "Review"
        case .resolve: return "Resolve"
        case .resolveAnswers: return "Resolve answers"
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
        // The chip the row's own button wears, so the setting and the thing it
        // configures are visibly one idea.
        case .resolve: return "arrow.triangle.merge"
        case .resolveAnswers: return "questionmark.bubble"
        // The same seal the lead chips wear, for the same reason the leads
        // section borrows it: a list of repositories you have vouched for.
        case .repositories: return "checkmark.seal"
        }
    }
}
