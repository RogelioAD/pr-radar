import Foundation

/// How much of a resolve run happens without being looked at.
///
/// Three, where automatic review has two, and the extra one is not symmetry for
/// its own sake. Curated *review* is a clean promise: the tools that write are
/// denied outright, so nothing has happened by the time you tick a box. Curated
/// *resolve* cannot promise that. A reply saying "fixed in `a1b2c3d`" is false
/// until that sha is pushed, so a run which drafts replies but does not fix,
/// commit and push produces a table of lies. Curated resolve therefore means
/// *the code has already landed; you choose the sentences* — a much weaker
/// guarantee, and one a label reading "let me choose" would quietly oversell.
///
/// So there is a third mode that makes the strong promise, and the labels say
/// which is which rather than leaving it to be discovered.
public enum ResolveMode: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Read, judge, report. Nothing is edited, committed, pushed or posted.
    case triage
    /// Fix, commit and push — then stop, and let the replies be picked over.
    case curated
    /// The skill's own behaviour: fix, push, reply and resolve.
    case automatic

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .triage: return "Just tell me"
        case .curated: return "Fix it, then let me post"
        case .automatic: return "Fix it and post it"
        }
    }

    /// One line each, for the reason `AutoReviewMode.detail` gives. The
    /// *reasoning* — why a curated resolve cannot promise what a curated review
    /// does — belongs in the type's own documentation and in the warning the
    /// room shows under the two modes that write, not under the picker on
    /// every glance.
    public var detail: String {
        switch self {
        case .triage:
            return "Reads and reports. Your checkout is left exactly as it was."
        case .curated:
            return "Fixes and pushes, then stops. You tick the replies."
        case .automatic:
            return "Fixes, pushes, replies and resolves, on its own."
        }
    }

    public var symbol: String {
        switch self {
        case .triage: return "eye"
        case .curated: return "checklist"
        case .automatic: return "paperplane"
        }
    }

    /// Whether this mode may change files in the user's checkout.
    public var writesCode: Bool { self != .triage }

    /// Whether the skill posts its own replies and resolutions.
    public var postsWithoutAsking: Bool { self == .automatic }
}

/// What a resolve run does with a comment asking for work outside the pull
/// request's stated job.
///
/// The skill stops and asks here, offering a menu. There is nobody to answer,
/// so the answer is a setting — and the options are the skill's own menu minus
/// the one that cannot be taken unattended.
public enum ResolveOutOfScope: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Say so in the thread, name no ticket, and flag it as untracked.
    case deferWithReasoning
    /// Treat the scope call as advisory and fix it anyway.
    case fixAnyway
    /// Draft a line for the PR's own follow-ups list, for PR Radar to add.
    case followUps
    /// Leave the thread open and bring it back for a human to decide.
    case leaveOpen

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .deferWithReasoning: return "Defer it, with reasons"
        case .fixAnyway: return "Fix it anyway"
        case .followUps: return "Add to the PR's follow-ups"
        case .leaveOpen: return "Leave it for me"
        }
    }

    public var detail: String {
        switch self {
        case .deferWithReasoning:
            return "Replies with the reason and resolves. Untracked gaps are flagged."
        case .fixAnyway:
            return "Treats the scope call as advice. The diff grows."
        case .followUps:
            return "Drafts a line for the PR's Follow Ups section."
        case .leaveOpen:
            return "Resolves nothing and brings it back to you."
        }
    }

    /// The same choice, in the words the skill's own menu uses.
    public var instruction: String {
        switch self {
        case .deferWithReasoning:
            return "defer it in-thread with your reasoning and no ticket, and "
                 + "set `asanaGap` so the gap is visible"
        case .fixAnyway:
            return "fix it in this pull request, through the same gates as any "
                 + "other fix, and say in the reply that it was out of the "
                 + "stated scope and was fixed anyway"
        case .followUps:
            return "do not edit the pull request yourself — set `followUp` on "
                 + "that row with the line you would have added, and PR Radar "
                 + "will add it"
        case .leaveOpen:
            return "leave the thread open as needs-you, and say what you need "
                 + "in order to close it"
        }
    }
}

/// What to do about a draft review of the user's own that has never been
/// submitted.
///
/// Its own setting because publishing one is not posting this run's replies —
/// it releases every comment in somebody's unsent draft at once, however old.
/// The skill asks about this even when it asks about nothing else, and the
/// honest default here is to leave it alone.
public enum ResolvePendingPolicy: String, Codable, CaseIterable, Sendable, Identifiable {
    case leave
    case publish

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leave: return "Leave it alone"
        case .publish: return "Publish it"
        }
    }

    public var detail: String {
        switch self {
        case .leave:
            return "Reported and left. Replies stay invisible until you submit it."
        case .publish:
            return "Releases every comment in the draft, however old."
        }
    }
}


/// How much of the repository's own checking a run does before it commits.
///
/// The setting that decides whether a run takes five minutes or fifty, and it
/// exists because of a real one: a conflict in a single Kotlin test fixture
/// took sixteen minutes, almost all of it `./gradlew testDevelopmentDebugUnitTest
/// lintDevelopmentDebug` followed by a pre-commit hook running the whole Rust
/// workspace again. Both ran because the skill says to run the whole suite, and
/// that is right when nobody is watching — but a developer *was* watching, and
/// in a terminal they would have said "it is a fixture, build the test module".
/// This is how they say that without being there.
///
/// It scopes what the **session** runs. It does not and must not reach the
/// repository's own hooks: a pre-commit hook that runs the full pass still
/// runs it, because the way to skip one is `--no-verify` and that is a
/// quality-gate bypass this feature will not perform at any setting.
public enum ResolveGates: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Everything, for the platform the change touched.
    case full
    /// Only what covers the change.
    case touched
    /// None. Push, and let the pull request's own checks judge it.
    case ci

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .full: return "Run the full suite"
        case .touched: return "Only what it touched"
        case .ci: return "Leave it to CI"
        }
    }

    public var detail: String {
        switch self {
        case .full:
            return "Thorough and slow. Minutes, not seconds, on a big repo."
        case .touched:
            return "Runs the crate or module the change is in. Much faster, and "
                 + "blind to what it broke elsewhere."
        case .ci:
            return "Commits and pushes without running anything. Fastest, and "
                 + "your pull request's checks are the only thing judging it."
        }
    }

    /// What the session is told, in the skill's own vocabulary.
    public var instruction: String {
        switch self {
        case .full:
            return "Run the repository's full gates for the platform you touched "
                 + "before committing, as the skill describes."
        case .touched:
            return "Run only the gates that cover what you changed — the crate, "
                 + "module or test target the diff actually touches — not the "
                 + "whole workspace. Name in `verification` what you ran and, "
                 + "just as plainly, what you did not."
        case .ci:
            return "Do not run build, test or lint gates yourself. Commit and "
                 + "push, name the checks that will judge it in `checksRunning`, "
                 + "and say in `verification` that nothing was run locally. Your "
                 + "repository's own commit hooks still run — do not try to skip "
                 + "them, and never pass `--no-verify`."
        }
    }

    /// Whether the row should say out loud that nothing was checked.
    public var isUnverified: Bool { self == .ci }
}
