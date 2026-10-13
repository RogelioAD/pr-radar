import Foundation

/// Whether a checkout can be brought up to its branch without losing anything.
///
/// Asked at the start of every resolve run, and the reason that step is a
/// fast-forward rather than `git reset --hard`: a reset is the command that
/// always works and sometimes silently destroys commits nobody else has. A
/// fast-forward moves the branch pointer forward over commits the remote
/// already has, and cannot.
///
/// This began as a button of its own — *Catch up* — sitting beside the refusal
/// it answered. Two buttons to press in a fixed order is a worse answer than
/// one that knows the order, especially when the first has no decision in it:
/// a checkout that is simply behind is a fetch and a pointer move. So the run
/// does it for itself, and the only case that still stops and asks is the one
/// below that cannot be done safely.
///
/// Pure, over the two numbers `git rev-list --left-right --count` gives, so the
/// rule that decides whether to touch somebody's working tree is a thing a test
/// can argue with rather than a shell exit code read in passing.
public enum FastForward {

    public enum Verdict: Equatable, Sendable {
        /// Already there. The button should not have been offered.
        case upToDate
        /// The remote is strictly ahead: moving is safe and loses nothing.
        case canFastForward(behind: Int)
        /// There are local commits the remote does not have. Fast-forwarding is
        /// impossible and resetting would throw them away, so this stops and
        /// says so — the choice between rebasing, pushing and discarding is the
        /// developer's, and it is not one to make on their behalf at a poll.
        case diverged(ahead: Int, behind: Int)
    }

    public static func verdict(ahead: Int, behind: Int) -> Verdict {
        if ahead > 0 { return .diverged(ahead: ahead, behind: behind) }
        if behind > 0 { return .canFastForward(behind: behind) }
        return .upToDate
    }

    /// `git rev-list --left-right --count HEAD...<ref>` prints "<ahead>\t<behind>".
    ///
    /// nil when it printed something else, which is treated as "do not touch
    /// the tree" rather than as zeroes — reading a failure as "up to date"
    /// would leave the row insisting the checkout is behind while the button
    /// that fixes it says there is nothing to do.
    public static func counts(fromRevList output: String) -> (ahead: Int, behind: Int)? {
        let fields = output
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0 == "\t" || $0 == " " })
        guard fields.count == 2,
              let ahead = Int(fields[0]), let behind = Int(fields[1]),
              ahead >= 0, behind >= 0
        else { return nil }
        return (ahead, behind)
    }
}
