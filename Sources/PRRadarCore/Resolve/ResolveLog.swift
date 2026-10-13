import Foundation

/// Where a resolve run has got to.
///
/// Deliberately **without a `queued` case**. Resolve is never automatic — bot
/// reviewers re-comment after every push, so a resolver on a timer would chase
/// its own tail — and a queue state that nothing can reach is a state something
/// will eventually be made to reach.
///
/// The terminal states at the bottom are the ones automatic review has no
/// equivalent of, and they exist because an interrupted resolve is not an
/// interrupted review. A review that died had read some code; running it again
/// costs money and nothing else. A resolve that died may have edited files,
/// committed through a pre-commit hook, and pushed — and nothing can tell from
/// the outside which of those it got to.
public enum ResolveStatus: String, Codable, Sendable {
    case running
    /// Finished, with a table waiting to be picked over.
    case ready
    /// Finished and everything decided has been posted.
    case posted
    /// Looked at and put away.
    case dismissed
    /// Refused before it started. Carries the reason.
    case blocked
    case failed
    /// Asked to stop, by somebody who was watching it.
    ///
    /// Its own state rather than a flavour of `failed`, because the two mean
    /// opposite things to the person reading the row: a failure is the feature
    /// not working, and this is the feature doing as it was told. It also
    /// re-runs freely — nothing is wrong, the run was simply not wanted.
    case stopped
    /// The app died while this was running, and nothing had landed.
    case interrupted
    /// The app died while this was running, and something *had* landed.
    /// Never pruned by age: it is the only record that code reached a branch
    /// without anybody reading the table that explains it.
    case landedUnreported
    /// A run from a previous launch is still going, outside this app.
    case orphaned

    /// Whether the row is finished with, one way or another.
    public var isTerminal: Bool {
        switch self {
        case .running, .ready: return false
        default: return true
        }
    }

    /// Whether pressing Resolve again is a safe thing to offer.
    ///
    /// Not after anything that may have left work half-done in the user's
    /// tree. A second run would layer fixes on top of a first set nobody has
    /// read, on a branch other people are looking at.
    public var mayRerun: Bool {
        switch self {
        case .posted, .dismissed, .blocked, .failed, .stopped, .interrupted: return true
        case .running, .ready, .landedUnreported, .orphaned: return false
        }
    }
}

/// One resolve run, remembered.
public struct ResolveRecord: Codable, Equatable, Sendable {
    public var status: ResolveStatus = .running
    public var mode: ResolveMode = .curated
    /// Which of the two jobs this run was. The row reads differently for each:
    /// a threads run finishes with replies to tick, a conflicts run with a
    /// merge that either happened or did not.
    public var scope: ResolveScope = .threads
    public var startedAt: Date?
    public var finishedAt: Date?
    public var runSeconds: TimeInterval?
    /// The tree it ran in, so a row that has to say "go and look" can say where.
    public var treePath: String?
    /// What the branch was at before anything ran.
    ///
    /// The most valuable field here. It is what makes an interrupted run
    /// diagnosable at all: whatever is between this and HEAD is what the dead
    /// run did, and `git log <preRunOid>..HEAD` is a sentence the row can hand
    /// the user.
    public var preRunOid: String?
    public var table: ResolveTable?
    public var pushedShas: [String] = []
    /// Threads replied to and closed, so a row can say what went out.
    public var postedThreadIDs: [String] = []
    public var failure: String?
    /// Why it would not start, when that is the answer.
    public var block: ResolveBlock?

    public init(status: ResolveStatus = .running, mode: ResolveMode = .curated,
                scope: ResolveScope = .threads) {
        self.status = status
        self.mode = mode
        self.scope = scope
    }

    enum CodingKeys: String, CodingKey {
        case status, mode, scope, startedAt, finishedAt, runSeconds, treePath
        case preRunOid, table, pushedShas, postedThreadIDs, failure
    }

    /// Lenient field by field, for the reason `AutoReviewRecord`'s decoder is:
    /// Swift's synthesized decoder ignores default values, so one property
    /// added in a later build makes every record an older one wrote unreadable
    /// and the whole log comes back empty. That is not hypothetical — adding
    /// `threads` to the review record did exactly that once.
    ///
    /// `block` is deliberately not persisted. It is recomputed on every press
    /// from the state of the tree, and a stored one would insist on a condition
    /// that stopped being true the moment somebody committed their changes.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Absent reads as dismissed: neither a row claiming to be running nor
        // one offering a table this build cannot read.
        status = try container.decodeIfPresent(ResolveStatus.self, forKey: .status) ?? .dismissed
        mode = try container.decodeIfPresent(ResolveMode.self, forKey: .mode) ?? .curated
        scope = try container.decodeIfPresent(ResolveScope.self, forKey: .scope) ?? .threads
        startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        runSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .runSeconds)
        treePath = try container.decodeIfPresent(String.self, forKey: .treePath)
        preRunOid = try container.decodeIfPresent(String.self, forKey: .preRunOid)
        table = try? container.decodeIfPresent(ResolveTable.self, forKey: .table)
        pushedShas = try container.decodeIfPresent([String].self, forKey: .pushedShas) ?? []
        postedThreadIDs = try container.decodeIfPresent([String].self,
                                                        forKey: .postedThreadIDs) ?? []
        failure = try container.decodeIfPresent(String.self, forKey: .failure)
        block = nil
    }

    public func runTime(now: Date) -> TimeInterval? {
        if status == .running {
            return RunTime.elapsed(startedAt: startedAt, finishedAt: nil, now: now)
        }
        if let runSeconds { return runSeconds }
        return RunTime.elapsed(startedAt: startedAt, finishedAt: finishedAt, now: now)
    }

    /// Whether this run is waiting to be picked over rather than finished.
    ///
    /// Only a threads run ever is. A conflicts run produces a merge, not a set
    /// of drafts, so there is nothing to tick and the row says what it did.
    public var isAwaitingSelection: Bool {
        status == .ready && scope.producesReplies && !(table?.threads.isEmpty ?? true)
    }

    /// The command that shows what a dead run actually did.
    ///
    /// Offered rather than run. Undoing it would need a force-push, and that is
    /// the user's call to make about their own branch, not an app's.
    public var forensics: String? {
        guard let treePath, let preRunOid else { return nil }
        return "git -C \(treePath) log --oneline \(preRunOid)..HEAD"
    }
}

/// Every resolve run the app remembers, keyed by `MyPullRequest.id`.
///
/// Keyed by pull request rather than by ping, which is what separates this from
/// `AutoReviewLog`: there is no ping here. A pull request is resolved, then
/// pushed to, then resolved again — the same subject, repeatedly, which is
/// exactly what a ping key is built *not* to be.
public struct ResolveLog: Codable, Equatable, Sendable {
    public private(set) var records: [String: ResolveRecord]

    public init(records: [String: ResolveRecord] = [:]) {
        self.records = records
    }

    public subscript(key: String) -> ResolveRecord? {
        get { records[key] }
        set { records[key] = newValue }
    }

    public static func decoded(from data: Data?) -> ResolveLog {
        guard let data, let log = try? JSONDecoder().decode(ResolveLog.self, from: data)
        else { return ResolveLog() }
        return log
    }

    public func encoded() -> Data? { try? JSONEncoder().encode(self) }

    /// What a run that did not finish becomes at the next launch.
    ///
    /// **Deliberately not `AutoReviewLog.reconcileInterrupted`'s answer**, and
    /// the difference is the whole reason this is a separate type rather than
    /// another status on that one. There, an interrupted run goes back in the
    /// queue, because a review that was cut off produced nothing and asking
    /// again is both safe and kind. Here there is no queue to go back into and
    /// re-running would be neither: the run may have edited files, committed
    /// and pushed, and a second run would layer a second set of fixes on top of
    /// a half-finished first set, on a branch other people are reading.
    ///
    /// So the record goes to a terminal state that offers diagnosis and never
    /// a retry. Which terminal state depends on the one thing worth knowing:
    /// whether anything landed.
    @discardableResult
    public mutating func reconcileAbandoned(
        headOf: (String) -> String?,
        isAlive: (ResolveRecord) -> Bool = { _ in false }
    ) -> [String] {
        let running = records.compactMap { $0.value.status == .running ? $0.key : nil }
        for key in running {
            guard var record = records[key] else { continue }
            if isAlive(record) {
                record.status = .orphaned
            } else if let tree = record.treePath,
                      let head = headOf(tree),
                      let before = record.preRunOid,
                      head != before {
                // Commits exist that nobody has read a table about.
                record.status = .landedUnreported
                record.failure = "Interrupted after it had already committed."
            } else {
                record.status = .interrupted
                record.failure = "Interrupted before anything landed."
            }
            record.finishedAt = Date()
            records[key] = record
        }
        return running.sorted()
    }

    /// Housekeeping, with one carve-out that is the point of having it.
    ///
    /// `landedUnreported` and `orphaned` are **never dropped by age**. Every
    /// other record is a convenience; those two are the only evidence that code
    /// reached somebody's branch without a table to explain it, and a record
    /// that quietly expires takes the evidence with it.
    public mutating func prune(liveKeys: Set<String>,
                               now: Date,
                               maxAge: TimeInterval = 14 * 24 * 3_600,
                               limit: Int = 200) {
        records = records.filter { key, record in
            if record.status == .landedUnreported || record.status == .orphaned {
                return true
            }
            if liveKeys.contains(key) { return true }
            guard let finishedAt = record.finishedAt else { return true }
            return now.timeIntervalSince(finishedAt) < maxAge
        }

        guard records.count > limit else { return }
        let keep = records
            .sorted { lhs, rhs in
                // Keeping the evidence first, then the most recent.
                let lhsKept = lhs.value.status == .landedUnreported
                    || lhs.value.status == .orphaned
                let rhsKept = rhs.value.status == .landedUnreported
                    || rhs.value.status == .orphaned
                if lhsKept != rhsKept { return lhsKept }
                return (lhs.value.finishedAt ?? .distantPast)
                     > (rhs.value.finishedAt ?? .distantPast)
            }
            .prefix(limit)
        records = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
    }
}
