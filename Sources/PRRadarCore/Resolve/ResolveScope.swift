import Foundation

/// What a resolve run is being asked to deal with.
///
/// Two jobs, one feature — deliberately. Answering review threads and fixing a
/// conflicted merge look like different buttons, and underneath they are the
/// same thing: your resolve skill, running headlessly, in the checkout that
/// holds the pull request's branch, under the guards that decide whether that
/// checkout is safe to work in, holding the same lease so two of them cannot
/// run at once.
///
/// Making conflicts a second feature would mean a second coordinator, a second
/// set of guards and a second lease — three copies of the dangerous part, to
/// express a difference that is really one sentence in a prompt. So it is a
/// scope on the one run instead, and everything that protects the threads run
/// protects this one unchanged.
///
/// The skill already knows how to do both: its conflicted-files pass runs
/// *before* triage precisely because a fix applied to a branch that cannot
/// merge gets re-resolved by hand later.
public enum ResolveScope: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Drive every unresolved review thread to a disposition.
    case threads
    /// Merge the base branch in and resolve what conflicts. No triage.
    case conflicts

    public var id: String { rawValue }

    /// What the button on the row says.
    public var buttonTitle: String {
        switch self {
        case .threads: return "Resolve"
        case .conflicts: return "Resolve conflicts"
        }
    }

    public var symbol: String {
        switch self {
        case .threads: return "arrow.triangle.merge"
        case .conflicts: return "exclamationmark.triangle"
        }
    }

    /// What the row says while it is going.
    public var runningLabel: String {
        switch self {
        case .threads: return "resolving…"
        case .conflicts: return "merging…"
        }
    }

    /// Whether a finished run has replies to tick.
    ///
    /// A conflicts run has none: there is nothing to post, only a merge that
    /// either happened or did not. So the row shows what it did rather than a
    /// table of drafts, and the posting half of the feature sits this one out.
    public var producesReplies: Bool { self == .threads }
}

/// What a conflicts run did about the merge.
public struct MergeReport: Codable, Equatable, Sendable {
    /// Whether the branch actually conflicted. A run that found it clean says
    /// so rather than inventing work.
    public var conflicted: Bool
    public var files: [String]
    /// How each class of conflict was settled, in the run's own words.
    public var resolution: String?
    /// The merge commit, once it is pushed.
    public var sha: String?

    public init(conflicted: Bool, files: [String] = [],
                resolution: String? = nil, sha: String? = nil) {
        self.conflicted = conflicted
        self.files = files
        self.resolution = resolution
        self.sha = sha
    }

    enum CodingKeys: String, CodingKey { case conflicted, files, resolution, sha }

    /// Lenient, like everything else persisted here.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        conflicted = try container.decodeIfPresent(Bool.self, forKey: .conflicted) ?? false
        files = try container.decodeIfPresent([String].self, forKey: .files) ?? []
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
        sha = try container.decodeIfPresent(String.self, forKey: .sha)
    }
}
