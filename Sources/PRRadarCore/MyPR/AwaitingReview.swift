import Foundation

/// How long your own pull request has been sitting with somebody else.
///
/// The app could say to the hour what you owe other people, and nothing at all
/// about the other direction. Your own row carried `awaitingReviewers` since
/// the tab was built and never drew it, so a pull request you asked three
/// people to look at four days ago looked exactly like one you opened this
/// morning.
///
/// It is the same clock the Reviews tab runs, pointed the other way, and it
/// uses the same ladder — under a day, one to three, beyond three — so the two
/// tabs cannot come to mean different things by the same colour.
public struct AwaitingReview: Equatable, Sendable {
    /// Who is still being waited on. Logins, or team slugs for a team request.
    public let reviewers: [String]

    /// When the longest-outstanding of them was asked.
    ///
    /// nil means the timeline did not say — a request older than the page the
    /// query reads, or one GitHub records some other way. The row still names
    /// who it is waiting on and simply does not claim a duration, which is the
    /// same shape `needs rebase` takes when the count is unavailable.
    public let since: Date?

    /// The reviewer `since` belongs to.
    public let longest: String?

    public init(reviewers: [String], since: Date?, longest: String?) {
        self.reviewers = reviewers
        self.since = since
        self.longest = longest
    }

    /// Builds the view from the outstanding reviewers and when each was last
    /// asked.
    ///
    /// *Last* asked, per reviewer: being re-requested restarts that person's
    /// clock, exactly as a re-request restarts yours on the other tab. The
    /// oldest of those is the one the row reports, because the question the
    /// chip answers is how long this has been waiting on somebody — and the
    /// answer is the longest anybody has had it.
    public static func make(reviewers: [String],
                            askedAt: [String: Date]) -> AwaitingReview? {
        guard !reviewers.isEmpty else { return nil }
        let dated = reviewers.compactMap { reviewer -> (String, Date)? in
            askedAt[reviewer].map { (reviewer, $0) }
        }
        let oldest = dated.min { $0.1 < $1.1 }
        return AwaitingReview(reviewers: reviewers.sorted(),
                              since: oldest?.1,
                              longest: oldest?.0)
    }

    /// `waiting 4d · alice`, or `waiting 4d · 3 reviewers` where more than one
    /// is outstanding. The name is the one who has had it longest, which is
    /// the one worth naming.
    public func label(now: Date = Date()) -> String {
        let who = reviewers.count == 1
            ? Leads.shortName(for: reviewers[0])
            : "\(reviewers.count) reviewers"
        guard let since else { return "waiting on \(who)" }
        return "waiting \(TimeAgo.short(since: since, now: now)) · \(who)"
    }

    /// Grey until it is known. A duration that was never read must not be
    /// painted as though it were fresh — the one actively misleading answer
    /// available here, and the same one `base state unknown` exists to avoid.
    public func health(now: Date = Date()) -> Health {
        guard let since else { return .neutral }
        return Staleness.of(since, now: now).health
    }

    public func help(now: Date = Date()) -> String {
        let names = reviewers.map { Leads.shortName(for: $0) }.joined(separator: ", ")
        guard let since, let longest else {
            return "Waiting on \(names). When they were asked is not in the "
                 + "timeline this reads."
        }
        let who = Leads.shortName(for: longest)
        return "Waiting on \(names).\n"
             + "\(who) was asked \(TimeAgo.long(since: since, now: now))."
    }
}
