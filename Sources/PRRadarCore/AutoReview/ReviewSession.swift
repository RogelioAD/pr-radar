import Foundation

/// An inline thread PR Radar opened and has not resolved.
public struct PostedThread: Codable, Equatable, Sendable {
    /// The review thread's node id, which `resolveReviewThread` takes.
    public let id: String
    public let path: String
    public let line: Int
    public let summary: String

    public init(id: String, path: String, line: Int, summary: String) {
        self.id = id
        self.path = path
        self.line = line
        self.summary = summary
    }
}

/// The Claude Code session behind one pull request's reviews.
///
/// Kept so a later review resumes it rather than gathering the same PR
/// context again. Keyed by pull request, not by ping: a re-request is a new
/// question about code the session has already read.
public struct ReviewSession: Codable, Equatable, Sendable {
    public var sessionID: String
    /// The head the last completed run reviewed. A re-review is due when the
    /// pull request's head differs from this.
    public var reviewedOid: String?
    public var lastRunAt: Date?
    /// The pull request, so a re-review can bring its row back after the search
    /// has stopped returning it.
    public var subject: ReviewItem
    /// The newest log record for this pull request.
    public var recordKey: String?
    /// PR Radar's threads that are still open, across every run.
    public var openThreads: [PostedThread] = []

    public init(sessionID: String, subject: ReviewItem, reviewedOid: String? = nil,
                lastRunAt: Date? = nil, recordKey: String? = nil,
                openThreads: [PostedThread] = []) {
        self.sessionID = sessionID
        self.subject = subject
        self.reviewedOid = reviewedOid
        self.lastRunAt = lastRunAt
        self.recordKey = recordKey
        self.openThreads = openThreads
    }

    /// Lenient, like `AutoReviewRecord`: a field added later must not make
    /// every stored session unreadable.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        subject = try container.decode(ReviewItem.self, forKey: .subject)
        reviewedOid = try container.decodeIfPresent(String.self, forKey: .reviewedOid)
        lastRunAt = try container.decodeIfPresent(Date.self, forKey: .lastRunAt)
        recordKey = try container.decodeIfPresent(String.self, forKey: .recordKey)
        openThreads = (try? container.decodeIfPresent([PostedThread].self,
                                                      forKey: .openThreads)) ?? []
    }

    /// The label a re-review prompt uses for an open thread, and reads back
    /// from `resolved`. Short labels rather than node ids, so the model only
    /// has to copy something it was given.
    public static func label(at index: Int) -> String { "T\(index + 1)" }

    /// The open threads' node ids for the labels a re-review returned. Unknown
    /// labels are ignored: only threads PR Radar opened can be resolved.
    public func threadIDs(forLabels labels: [String]) -> [String] {
        let wanted = Set(labels.map { $0.trimmingCharacters(in: .whitespaces).uppercased() })
        return openThreads.enumerated()
            .filter { wanted.contains(Self.label(at: $0.offset)) }
            .map(\.element.id)
    }
}

/// Every review session, as one stored blob — the same shape as `AutoReviewLog`.
public struct ReviewSessions: Codable, Equatable, Sendable {
    public var sessions: [String: ReviewSession] = [:]

    public init() {}

    /// By `repo#number`.
    public subscript(pullRequest: String) -> ReviewSession? {
        get { sessions[pullRequest] }
        set { sessions[pullRequest] = newValue }
    }

    /// Pull requests whose head has moved since their last run and which are
    /// not already being reviewed again.
    ///
    /// `heads` is `repo#number` → head oid, for the pull requests this round
    /// could see. One it could not see is left alone: not knowing is not a
    /// push. Only a run that was posted, dismissed or is waiting to be picked
    /// over is restarted — queued and running ones are already on their way,
    /// and a failed one retries through the queue's own backoff.
    public func rereviewsDue(heads: [String: String], log: AutoReviewLog) -> [String] {
        sessions.compactMap { id, session -> String? in
            guard let reviewed = session.reviewedOid,
                  let head = heads[id], head != reviewed
            else { return nil }
            guard let key = session.recordKey, let record = log[key] else { return id }
            switch record.status {
            case .posted, .dismissed, .ready: return id
            case .queued, .running, .failed, .skipped: return nil
            }
        }
        .sorted()
    }

    /// Node ids to ask GitHub about for one account.
    public func nodeIDs(account: String) -> [String] {
        sessions.values
            .filter { $0.subject.account == account }
            .compactMap(\.subject.nodeID)
    }

    /// Drops sessions for pull requests that have closed or merged.
    public mutating func retire(closed: Set<String>) {
        guard !closed.isEmpty else { return }
        sessions = sessions.filter { _, session in
            guard let node = session.subject.nodeID else { return true }
            return !closed.contains(node)
        }
    }

    /// Keeps the most recently run sessions under a ceiling.
    public mutating func trim(limit: Int = 100) {
        guard sessions.count > limit else { return }
        let oldest = sessions
            .sorted { ($0.value.lastRunAt ?? .distantPast) < ($1.value.lastRunAt ?? .distantPast) }
            .prefix(sessions.count - limit)
        for (key, _) in oldest { sessions[key] = nil }
    }

    /// A corrupt or absent value reads as no sessions; the next review then
    /// simply starts a fresh one.
    public static func decoded(from data: Data?) -> ReviewSessions {
        guard let data,
              let sessions = try? JSONDecoder().decode(ReviewSessions.self, from: data)
        else { return ReviewSessions() }
        return sessions
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
