import Foundation

/// What a resolve run decided about one thread.
public enum ResolveDisposition: String, Codable, Sendable, CaseIterable {
    case fix
    case alreadyDone = "already-done"
    case disagree
    case defer_ = "defer"
    case needsYou = "needs-you"

    public var label: String {
        switch self {
        case .fix: return "fixed"
        case .alreadyDone: return "already done"
        case .disagree: return "disagreed"
        case .defer_: return "deferred"
        case .needsYou: return "needs you"
        }
    }

    public var health: Health {
        switch self {
        case .fix, .alreadyDone: return .good
        case .disagree, .defer_: return .neutral
        case .needsYou: return .attention
        }
    }

    /// Whether this thread may be closed once its reply is posted.
    ///
    /// The single most important line in this file. A thread resolved without
    /// being fixed or consciously deferred reads to every reviewer as handled,
    /// which silently drops real feedback — the one failure the whole feature
    /// exists to prevent. `needs-you` means nobody decided anything, so it
    /// stays open however confident the run sounded.
    public var mayResolve: Bool { self != .needsYou }
}

/// One row of the table.
public struct ResolveRow: Codable, Equatable, Sendable, Identifiable {
    public var threadId: String
    public var disposition: ResolveDisposition
    /// What the thread asked for, in the run's own words. Lets the row say what
    /// is being answered without re-rendering the whole conversation.
    public var ask: String?
    public var reply: String
    public var sha: String?
    public var files: [String]?
    public var verification: String?
    public var followUp: String?
    public var asanaGap: Bool?
    public var asanaNote: String?
    public var needs: String?

    /// Whether this row is going out. Ticked on arrival for everything that may
    /// be resolved, and off for `needs-you`, which is not a reply to withhold
    /// so much as a question to answer.
    public var isSelected: Bool = true
    /// Set by PR Radar, never by the run: the cited commit could not be found
    /// on the remote, so a reply claiming it would be false.
    public var shaIsUnpushed: Bool = false

    public var id: String { threadId }

    /// Whether this row may be posted and the thread then closed.
    public var mayResolve: Bool { disposition.mayResolve && !shaIsUnpushed }

    enum CodingKeys: String, CodingKey {
        case threadId, disposition, ask, reply, sha, files
        case verification, followUp, asanaGap, asanaNote, needs
        case isSelected, shaIsUnpushed
    }

    public init(threadId: String, disposition: ResolveDisposition, reply: String,
                ask: String? = nil, sha: String? = nil, files: [String]? = nil,
                verification: String? = nil, followUp: String? = nil,
                asanaGap: Bool? = nil, asanaNote: String? = nil,
                needs: String? = nil, isSelected: Bool = true,
                shaIsUnpushed: Bool = false) {
        self.threadId = threadId
        self.disposition = disposition
        self.reply = reply
        self.ask = ask
        self.sha = sha
        self.files = files
        self.verification = verification
        self.followUp = followUp
        self.asanaGap = asanaGap
        self.asanaNote = asanaNote
        self.needs = needs
        self.isSelected = isSelected
        self.shaIsUnpushed = shaIsUnpushed
    }

    /// Lenient, for the reason `AutoReviewRecord`'s decoder is: this is
    /// persisted and will gain fields, and one missing key must cost a field
    /// rather than the whole stored log.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        threadId = try container.decodeIfPresent(String.self, forKey: .threadId) ?? ""
        disposition = try container.decodeIfPresent(ResolveDisposition.self,
                                                    forKey: .disposition) ?? .needsYou
        ask = try container.decodeIfPresent(String.self, forKey: .ask)
        reply = try container.decodeIfPresent(String.self, forKey: .reply) ?? ""
        sha = try container.decodeIfPresent(String.self, forKey: .sha)
        files = try container.decodeIfPresent([String].self, forKey: .files)
        verification = try container.decodeIfPresent(String.self, forKey: .verification)
        followUp = try container.decodeIfPresent(String.self, forKey: .followUp)
        asanaGap = try container.decodeIfPresent(Bool.self, forKey: .asanaGap)
        asanaNote = try container.decodeIfPresent(String.self, forKey: .asanaNote)
        needs = try container.decodeIfPresent(String.self, forKey: .needs)
        isSelected = try container.decodeIfPresent(Bool.self, forKey: .isSelected) ?? true
        shaIsUnpushed = try container.decodeIfPresent(Bool.self,
                                                      forKey: .shaIsUnpushed) ?? false
    }
}

/// A draft review of the user's own that was never submitted.
public struct PendingReview: Codable, Equatable, Sendable {
    public var reviewId: String
    public var author: String?
    public var comments: Int

    public init(reviewId: String, author: String? = nil, comments: Int) {
        self.reviewId = reviewId
        self.author = author
        self.comments = comments
    }
}

/// What one resolve run produced.
public struct ResolveTable: Codable, Equatable, Sendable {
    public var scope: String
    public var summary: String?
    public var pushedShas: [String]
    public var checksRunning: [String]
    public var pending: PendingReview?
    /// What a conflicts run did about the merge. nil on a threads run.
    public var merge: MergeReport?
    public var threads: [ResolveRow]
    /// Threads PR Radar sent that the run did not come back with.
    ///
    /// Recorded rather than ignored, because the alternative reading of a
    /// missing thread is "nothing to do about it" — and this feature's whole
    /// premise is that a thread nobody consciously disposed of stays open. The
    /// row says "4 of 6 triaged" instead of implying six.
    public var missing: [String] = []
    /// Ids the run returned that PR Radar never sent, so it cannot post them.
    public var unknown: [String] = []

    public init(scope: String = "", summary: String? = nil,
                pushedShas: [String] = [], checksRunning: [String] = [],
                pending: PendingReview? = nil, merge: MergeReport? = nil,
                threads: [ResolveRow] = [],
                missing: [String] = [], unknown: [String] = []) {
        self.scope = scope
        self.summary = summary
        self.pushedShas = pushedShas
        self.checksRunning = checksRunning
        self.pending = pending
        self.merge = merge
        self.threads = threads
        self.missing = missing
        self.unknown = unknown
    }

    enum CodingKeys: String, CodingKey {
        case scope, summary, pushedShas, checksRunning, pending, merge, threads
        case missing, unknown
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decodeIfPresent(String.self, forKey: .scope) ?? ""
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        pushedShas = try container.decodeIfPresent([String].self, forKey: .pushedShas) ?? []
        checksRunning = try container.decodeIfPresent([String].self,
                                                      forKey: .checksRunning) ?? []
        pending = try? container.decodeIfPresent(PendingReview.self, forKey: .pending)
        merge = try? container.decodeIfPresent(MergeReport.self, forKey: .merge)
        threads = try container.decodeIfPresent([ResolveRow].self, forKey: .threads) ?? []
        missing = try container.decodeIfPresent([String].self, forKey: .missing) ?? []
        unknown = try container.decodeIfPresent([String].self, forKey: .unknown) ?? []
    }

    public func count(_ disposition: ResolveDisposition) -> Int {
        threads.filter { $0.disposition == disposition }.count
    }

    /// Rows ticked and postable.
    public var postable: [ResolveRow] {
        threads.filter { $0.isSelected && !$0.reply.isEmpty }
    }

    public var selection: (chosen: Int, total: Int) {
        (postable.count, threads.count)
    }

    /// Out-of-scope work with nothing tracking it.
    ///
    /// Surfaced on its own because it is the highest-value thing a run finds: a
    /// comment that is real, out of scope, and in nobody's backlog is work that
    /// will otherwise simply be forgotten.
    public var untrackedGaps: [ResolveRow] {
        threads.filter { $0.asanaGap == true }
    }

    // MARK: - PR Radar's own rules

    /// Applies the rules the prompt cannot be trusted with.
    ///
    /// Everything here is something a run could get wrong in a way nobody would
    /// notice: a thread closed that nobody answered, a reply posted against an
    /// id that means nothing, a sha cited that is not on the remote. The
    /// framing asks for all of it politely. This is the part that does not ask.
    public func sanitised(against known: [UnresolvedThread],
                          pushedShas: Set<String> = [],
                          scope: ResolveScope = .threads) -> ResolveTable {
        var table = self

        // A conflicts run was never asked about threads, so it has not dropped
        // any. Holding it to the threads contract would brand every successful
        // merge "6 not triaged" — a warning about work nobody requested.
        guard scope.producesReplies else {
            table.threads = []
            table.missing = []
            table.unknown = []
            return table
        }

        let ids = Set(known.map(\.id))
        let returned = Set(threads.map(\.threadId))
        table.unknown = threads.map(\.threadId).filter { !ids.contains($0) }.sorted()
        table.missing = ids.subtracting(returned).sorted()

        table.threads = threads
            .filter { ids.contains($0.threadId) }
            .map { row in
                var row = row
                // Nobody decided this one, so it is not going out ticked and
                // its thread is not closing. Whatever the run said.
                if row.disposition == .needsYou { row.isSelected = false }
                // A reply claiming a commit that is not on the remote is a
                // reply that is false the moment it lands.
                if let sha = row.sha, !sha.isEmpty, !pushedShas.isEmpty,
                   !pushedShas.contains(where: { $0.hasPrefix(sha) || sha.hasPrefix($0) }) {
                    row.shaIsUnpushed = true
                    row.isSelected = false
                }
                return row
            }
        return table
    }
}
