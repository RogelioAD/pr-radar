import Foundation

/// The command a row would run, if the row ran commands.
///
/// Rebasing and merging are not offered from the widget, and the reasons stand:
/// a force-push behind a one-click button in a floating panel is a lot of risk
/// for something the terminal does better, and the one time it was built it
/// took a local clone, `git worktree list` parsing, five safety guards and a
/// force-push to save a command.
///
/// None of that is an argument for making you *type* it. The annoying half of
/// "go and rebase it" is getting a branch name with four slashes in it right,
/// and that half is pure transcription — so the row writes it down and the
/// terminal still runs it. Nothing here executes anything.
public enum BranchCommand {

    /// Bring the branch up to date with its base.
    ///
    /// `fetch` then `rebase` as two commands joined by `&&`, rather than
    /// `git pull --rebase`: pull's behaviour depends on `pull.rebase`,
    /// `pull.ff` and the branch's own upstream, so the same line does
    /// different things in different checkouts. These two do not.
    public static func rebase(onto base: String, remote: String = "origin") -> String {
        "git fetch \(remote) && git rebase \(remote)/\(base)"
    }

    /// Check the branch out, for the conflicted case where the fix is manual.
    ///
    /// Named `switch` rather than `checkout` because that is what it does and
    /// what git has recommended since 2.23 — and because a reader who pastes
    /// this is about to be in the middle of a merge and should not also be
    /// wondering whether the command they ran could have discarded something.
    public static func checkout(_ head: String) -> String {
        "git switch \(head)"
    }

    /// Both, for a branch that conflicts: get onto it, then rebase it.
    public static func resolve(head: String, base: String,
                               remote: String = "origin") -> String {
        "\(checkout(head)) && \(rebase(onto: base, remote: remote))"
    }
}
