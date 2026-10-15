import Foundation

/// Reads `git merge-tree --write-tree --name-only <head> <base>`.
///
/// **Why this exists at all: GitHub will not tell you.** `mergeStateStatus`
/// reports `DIRTY` — that the branch conflicts — and nothing about what or how
/// much. There is no field for it, so a row that wants to say `4 files` has to
/// work it out locally, the same way the resolve skill's own conflicted-files
/// pass does.
///
/// It is also the only honest way to ask. GitHub's flag goes stale, and reads
/// `CONFLICTING` on a stacked pull request whose base is a strict ancestor of
/// its head — which is the commonest shape in a repository that stacks.
/// `merge-tree` computes the real answer without touching the working tree,
/// writing an index, or needing a checkout to be clean.
///
/// The output: the first line is the written tree's oid, then — when there are
/// conflicts — one path per line, then a blank line and whatever informational
/// messages git felt like adding. Exit 0 means it merged cleanly and there is
/// nothing after the oid.
public enum MergeTree {

    /// What a merge of base into head would conflict on.
    ///
    /// nil when the question could not be answered — a base ref the clone has
    /// never fetched, a git too old for `--write-tree`, a repository that is
    /// not there. nil is **not** "no conflicts": the row shows a count only
    /// when it has one, and falls back to the wording it used before anybody
    /// could count, for the same reason `behindBy` leaves "behind ?" rather
    /// than claiming "behind 0".
    ///
    /// **The exit code is not enough to tell a conflict from a failure**, which
    /// was worth finding out against a real git rather than assuming: asking
    /// about a ref the clone does not have exits **1**, exactly as a genuine
    /// conflict does, and says why on stderr where this never sees it. So the
    /// empty-names rule below is not a tidy edge case, it is the whole guard —
    /// without it, every unfetched base would be reported as a conflict in zero
    /// files.
    public static func conflictedPaths(exitCode: Int32, output: String) -> [String]? {
        guard exitCode == 0 || exitCode == 1 else { return nil }
        guard exitCode == 1 else { return [] }

        var lines = output.replacingOccurrences(of: "\r\n", with: "\n")
                          .components(separatedBy: "\n")
        // The tree oid, which is not a path.
        guard !lines.isEmpty else { return nil }
        lines.removeFirst()

        var paths: [String] = []
        for line in lines {
            // The blank line ends the file list; everything after it is prose
            // about the conflicts rather than more of them.
            if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
            paths.append(line)
        }
        // Exit 1 having named nothing is the failure case, not a conflict in
        // no files: an unfetched base ref lands here, and so does any other
        // complaint git makes on stderr. Reported as unknown, because
        // "conflicts · 0 files" is a row contradicting itself.
        return paths.isEmpty ? nil : paths
    }

    /// The arguments that ask the question.
    ///
    /// `--name-only` keeps the output to paths instead of the full conflicted
    /// blobs, which on a real conflict is the difference between a line and a
    /// megabyte.
    public static func arguments(head: String, base: String) -> [String] {
        ["merge-tree", "--write-tree", "--name-only", head, base]
    }
}
