import Foundation

/// How much of the review goes out without being looked at.
///
/// Two modes rather than a switch called "post automatically", because they are
/// genuinely different ways of working rather than one setting turned off. In
/// one, the review is the machine's and you rule on it afterwards; in the other
/// the machine drafts and you decide what is worth a colleague's attention
/// before anything is sent. The difference is *where* the human judgement goes,
/// not how much of it there is.
public enum AutoReviewMode: String, CaseIterable, Sendable, Identifiable {
    /// Review, post, and leave the verdict to the row's buttons.
    case automatic
    /// Review, then wait: the findings are listed with their tiers and nothing
    /// is sent until they have been picked over.
    case curated

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .automatic: return "Post it for me"
        case .curated: return "Let me choose"
        }
    }

    public var detail: String {
        switch self {
        case .automatic:
            return "Every priority and mild finding is posted inline as soon as "
                 + "the review finishes. You still decide whether to approve, "
                 + "request changes, or let the comment stand."
        case .curated:
            return "Nothing is sent until you have looked. The row lists what was "
                 + "found, tier by tier, and you tick the ones worth posting."
        }
    }

    public var symbol: String {
        switch self {
        case .automatic: return "paperplane"
        case .curated: return "checklist"
        }
    }

    /// Whether a finished review posts itself.
    public var postsWithoutAsking: Bool { self == .automatic }
}
