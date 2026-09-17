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

extension Staleness {
    /// Where an overdue review sits on the one severity scale. Kept here rather
    /// than in the view layer because it is the definition of the signal, not a
    /// choice about how to paint it — and because the mascot in the drawer and
    /// the count on the badge both have to read it to be guaranteed to agree.
    public var health: Health {
        switch self {
        case .fresh: return .running    // blue: nothing wrong, just waiting
        case .aging: return .attention
        case .stale: return .bad
        }
    }
}
