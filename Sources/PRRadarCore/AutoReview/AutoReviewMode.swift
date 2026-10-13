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

    /// One line, because it sits under a picker in a 440pt drawer and the
    /// drawer has five other groups in it. What a mode *also* does — that you
    /// still rule on the review afterwards either way — is the same in both and
    /// so says nothing about the choice.
    public var detail: String {
        switch self {
        case .automatic:
            return "Priority and mild findings are posted inline as soon as the "
                 + "review finishes."
        case .curated:
            return "Nothing is sent until you have ticked it."
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
