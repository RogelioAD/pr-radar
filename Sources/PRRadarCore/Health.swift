import Foundation

/// One semantic scale for every coloured signal in the UI — checks, merge
/// blockers, approvals, staleness. Keeping it in one place is what stops the
/// palettes drifting apart as indicators are added.
public enum Health: String, Sendable, CaseIterable {
    case good       // passing, approved, ready
    case running    // in progress, not yet known
    case attention  // needs something from a human
    case bad        // failing, rejected, conflicted
    case neutral    // skipped, draft, dismissed

    /// Ranks severity so a row can report its worst signal.
    public var severity: Int {
        switch self {
        case .bad: return 4
        case .attention: return 3
        case .running: return 2
        case .good: return 1
        case .neutral: return 0
        }
    }

    public static func worst(_ values: [Health]) -> Health {
        values.max { $0.severity < $1.severity } ?? .neutral
    }
}
