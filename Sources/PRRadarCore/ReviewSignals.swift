import Foundation

/// GitHub's own one-word verdict on a head commit's checks.
///
/// The rollup's `state` and nothing under it. The Reviews tab asks a triage
/// question — *is this even reviewable yet* — which is one word; the per-check
/// breakdown is the My PRs tab's job, and it costs a hundred context nodes per
/// pull request to answer.
public enum RollupVerdict: String, Sendable, Codable, Equatable {
    case success = "SUCCESS"
    case failure = "FAILURE"
    case error = "ERROR"
    case pending = "PENDING"
    case expected = "EXPECTED"

    public var label: String {
        switch self {
        case .success: return "checks green"
        case .failure, .error: return "checks failing"
        case .pending: return "checks running"
        case .expected: return "checks expected"
        }
    }

    public var health: Health {
        switch self {
        case .success: return .good
        case .failure, .error: return .bad
        case .pending: return .running
        case .expected: return .neutral
        }
    }

    public var symbol: String {
        switch self {
        case .success: return "checkmark.circle"
        case .failure, .error: return "xmark.octagon"
        case .pending: return "clock"
        case .expected: return "clock"
        }
    }

    /// Whether reviewing now means reviewing something the machine has already
    /// said is broken. `expected` is not one of these: a check that has been
    /// promised and never arrived says nothing about the diff.
    public var isFailing: Bool { self == .failure || self == .error }
}

/// What a review will cost to do, and whether it is worth starting.
///
/// Every one of these is a question the Reviews tab used to answer by sending
/// you to a browser tab: how big is it, is CI red, and am I the only one on the
/// hook. They ride the fragment the list was already fetching, so the whole
/// thing is one round trip exactly as before.
///
/// Optional on the item, for the reason `nodeID` is optional: a row redrawn
/// from a persisted auto-review record never carried these, and a missing
/// signal has to read as *not known* rather than as `+0 −0 · 0 files`.
public struct ReviewSignals: Equatable, Sendable, Codable {
    public let additions: Int
    public let deletions: Int
    public let changedFiles: Int

    /// nil when the head commit has no checks at all, which is deliberately
    /// not the same as passing — a repository with no CI and a repository
    /// whose CI has not started are both honestly described as *nothing to
    /// say*, and neither is "green".
    public let checks: RollupVerdict?

    /// Reviewers still being waited on who are not me and not a team of mine.
    ///
    /// This is what tells a request aimed at you alone from a team ping that
    /// went to six people. The red badge counts them the same, and should —
    /// it is a count of what has been asked of you — but the row no longer
    /// has to leave you to find out which kind it is.
    public let otherReviewers: Int

    /// Live approvals already in, by the same rule the lead chip uses: a
    /// dismissed approval is not an approval, and a COMMENTED review is not
    /// an opinion.
    public let approvals: Int

    public init(additions: Int, deletions: Int, changedFiles: Int,
                checks: RollupVerdict?, otherReviewers: Int, approvals: Int) {
        self.additions = additions
        self.deletions = deletions
        self.changedFiles = changedFiles
        self.checks = checks
        self.otherReviewers = otherReviewers
        self.approvals = approvals
    }

    /// The one number a size sort orders by.
    public var lines: Int { additions + deletions }

    /// `+120 −40 · 6f`, in the shape the My PRs row has always drawn it.
    public var sizeLabel: String {
        "+\(additions) −\(deletions) · \(changedFiles)f"
    }

    /// How much of a sitting this is. Deliberately coarse: the row already
    /// prints the exact numbers, and a tint is a glance rather than a measure.
    public var weight: Health {
        if lines >= 1_000 || changedFiles >= 30 { return .attention }
        if lines >= 250 { return .running }
        return .neutral
    }

    public var sizeHelp: String {
        "\(additions) added, \(deletions) removed across "
            + "\(changedFiles) file\(changedFiles == 1 ? "" : "s")"
    }
}

/// What a row is narrowed to on the Reviews tab.
///
/// A second axis from the author menu, in the same sense the pancake button is
/// a second axis on My PRs: *small ones nobody has looked at* is one question,
/// and it is two controls.
public enum ReviewFilter: String, CaseIterable, Sendable {
    case all
    case checksNotFailing
    case notYetApproved

    public var label: String {
        switch self {
        case .all: return "Anything"
        case .checksNotFailing: return "CI not failing"
        case .notYetApproved: return "Nobody has approved"
        }
    }

    public var symbol: String {
        switch self {
        case .all: return "line.3.horizontal.decrease.circle"
        case .checksNotFailing: return "checkmark.shield"
        case .notYetApproved: return "person.crop.circle.badge.questionmark"
        }
    }

    /// What to call an empty list this filter produced.
    ///
    /// Said as the fact about the queue rather than as the filter's own name.
    /// "Nothing CI not failing" is the filter talking about itself; "every one
    /// of them has failing checks" is the answer you were looking for.
    public var emptyTitle: String {
        switch self {
        case .all: return "Nothing to show"
        case .checksNotFailing: return "Every one has failing checks"
        case .notYetApproved: return "Every one is already approved"
        }
    }

    /// An item whose signals never arrived matches everything.
    ///
    /// The alternative is to hide rows for failing a test they were never
    /// given, which is the filter equivalent of reading a failed lookup as
    /// "up to date" — and this list's whole job is to be the complete account
    /// of what is waiting on you.
    public func matches(_ item: ReviewItem) -> Bool {
        guard let signals = item.signals else { return true }
        switch self {
        case .all: return true
        case .checksNotFailing: return !(signals.checks?.isFailing ?? false)
        case .notYetApproved: return signals.approvals == 0
        }
    }

    public func apply(to items: [ReviewItem]) -> [ReviewItem] {
        self == .all ? items : items.filter(matches)
    }

    /// Whether this filter could ever hide anything in the list as it stands.
    ///
    /// The control is only offered when one of them could, by the rule the
    /// pancake button already follows: a filter that can only ever return
    /// everything, or only ever return nothing, is worse than no filter.
    public static func isUseful(on items: [ReviewItem]) -> Bool {
        items.contains { item in
            guard let signals = item.signals else { return false }
            return (signals.checks?.isFailing ?? false) || signals.approvals > 0
        }
    }
}
