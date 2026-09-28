import Foundation

/// How much a finding is worth interrupting someone for.
///
/// Three tiers rather than a severity number, because this is the vocabulary
/// review skills already speak and the row has room for three chips, not a
/// scale. Decoded leniently so a skill inventing a fourth tier costs one
/// finding rather than the whole payload.
public enum FindingTier: String, Codable, Sendable, CaseIterable {
    case priority
    case mild
    case nit

    /// Where a tier sits on the app's one severity scale, so the chips on a row
    /// read as members of the same system as every other coloured signal.
    public var health: Health {
        switch self {
        case .priority: return .bad
        case .mild: return .attention
        case .nit: return .neutral
        }
    }

    public var label: String { rawValue }
}

/// One thing a review skill noticed.
///
/// `recommendation` is required rather than optional on purpose: a finding
/// with nothing to do about it is a complaint, and this feature posts under the
/// user's own name. The location fields are optional because not every finding
/// has one — an observation about the PR as a whole still belongs in the body.
public struct Finding: Codable, Equatable, Sendable {
    public let tier: FindingTier
    public let file: String?
    public let line: Int?
    /// The last line of the cited range, when the finding covers more than one.
    /// Required before a suggestion can be rendered, because a replacement has
    /// to know what it replaces.
    public let endLine: Int?
    public let summary: String
    public let detail: String?
    public let recommendation: String
    /// A literal replacement for lines `line...endLine`, when the fix is one.
    public let suggestion: String?

    public init(tier: FindingTier, file: String? = nil, line: Int? = nil,
                endLine: Int? = nil, summary: String, detail: String? = nil,
                recommendation: String, suggestion: String? = nil) {
        self.tier = tier
        self.file = file
        self.line = line
        self.endLine = endLine
        self.summary = summary
        self.detail = detail
        self.recommendation = recommendation
        self.suggestion = suggestion
    }

    /// The range a suggestion would replace, or nil when there is not one to
    /// anchor to. `endLine` defaults to `line`, so a single-line fix does not
    /// have to say so twice.
    public var lineRange: ClosedRange<Int>? {
        guard let line, line > 0 else { return nil }
        let end = endLine ?? line
        return end >= line ? line...end : nil
    }
}

/// What one run of a review skill produced.
public struct AutoReviewFindings: Codable, Equatable, Sendable {
    public let verdict: String?
    public let findings: [Finding]

    public init(verdict: String? = nil, findings: [Finding]) {
        self.verdict = verdict
        self.findings = findings
    }

    public func of(_ tier: FindingTier) -> [Finding] { findings.filter { $0.tier == tier } }
    public func count(_ tier: FindingTier) -> Int { of(tier).count }

    /// Counts by raw tier name, which is the shape `AutoReviewRecord` stores.
    public var counts: [String: Int] {
        Dictionary(uniqueKeysWithValues: FindingTier.allCases.map { ($0.rawValue, count($0)) })
    }

    /// Everything worth putting on the PR. Nits are counted, never raised —
    /// posting a colleague a list of nits under your own name is how an
    /// automated reviewer gets muted.
    public var raisable: [Finding] { findings.filter { $0.tier != .nit } }
}
