import Foundation

/// When the drawer is twice its usual width.
///
/// One width suits everything the drawer normally shows: a list of pull
/// requests is a column of short lines, and 440pt is as much of one as anybody
/// wants to read down. A diff is the opposite shape. Code is wide, it cannot be
/// reflowed without ceasing to look like code, and a hunk squeezed into a
/// column is a hunk read three tokens at a time.
///
/// So the width follows what is on screen rather than being a setting. Open a
/// findings list, or a review thread on one of your own pull requests, and the
/// drawer earns the space; leave it — close it, change tab, walk into a room —
/// and it gives it straight back. Nobody has to remember to put it away, which
/// is the only reason a doubling this large is affordable at all.
///
/// A rule rather than a condition spelled out at the frame calculation, because
/// it is read in two places that must agree exactly: the panel sizes its window
/// from it and the view sizes its content from it, and a drawer whose frame and
/// contents disagree about how wide it is clips.
public enum DrawerWidth {

    /// Whether something that needs the room is open right now.
    ///
    /// Both tabs have one. On Reviews it is a findings list, and the code under
    /// a finding is what needs the width. On My PRs it is an unresolved review
    /// thread, which is somebody's prose about a line of yours — narrower than
    /// a diff, but not a chip's worth. Which tab is showing decides *which*
    /// keys are asked about; the question itself is the same one, so it is
    /// asked in one place.
    ///
    /// A room is the blanket answer: it covers the list entirely, so nothing
    /// under it can be open.
    ///
    /// `openKeys` is checked against the rows that could actually draw the
    /// thing rather than trusted on its own, and "could" is doing real work
    /// there. A row still on screen is not enough: press a decision and the row
    /// stays put saying `done` while its findings retire with the record, and
    /// the key left behind held the drawer at double width over a list that was
    /// no longer there. A row that leaves the list does the same thing more
    /// obviously. So the caller passes the rows that can expand — the same
    /// condition the row itself draws under — and the two cannot disagree.
    public static func isWide(room: DrawerRoom?,
                              openKeys: Set<String>,
                              expandable: [String]) -> Bool {
        guard room == nil, !openKeys.isEmpty else { return false }
        return expandable.contains { openKeys.contains($0) }
    }
}
