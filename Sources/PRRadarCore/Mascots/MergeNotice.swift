import Foundation

/// What the banner says, and the glyph it says it beside, when something lands
/// in one of the repositories you work in.
///
/// Sized by `Achievement`, which owns the arithmetic for anything that drops in
/// from the top of the screen. Only the words and the drawing are here.
///
/// Green, and the same green — `Health.good`, through `.accent`, exactly as the
/// trophy star. GitHub's own colour for a merge is purple and this deliberately
/// is not it: the app has one semantic scale, `good` already means *nothing is
/// in your way*, and a merge is the purest case of that there is. A second idea
/// of "landed" in a colour nothing else in the app uses would be a palette
/// growing a dialect. What tells the two banners apart is the picture and the
/// sentence, which is what tells them apart on a trophy shelf too.
public enum MergeNotice {

    /// The small standing line: who landed it.
    ///
    /// The *person* goes on the quiet line and the *pull request* on the loud
    /// one, which is the opposite of the obvious arrangement and the right way
    /// round. "Alice" is the part you read without meaning to; "mobile #412" is
    /// the part you might act on, and it is the part you have to be able to
    /// read from across a desk.
    public static func headline(author: String) -> String {
        let name = clipped(author, to: nameLimit)
        return name.isEmpty ? "MERGED" : "\(name) MERGED"
    }

    /// The loud line: which pull request, in which repository.
    public static func title(repo: String, number: Int) -> String {
        "\(clipped(RepoScope.shortName(repo), to: repoLimit)) #\(number)"
    }

    public static func title(_ merge: MergedPR) -> String {
        title(repo: merge.repo, number: merge.number)
    }

    /// What a burst says instead of holding the screen one merge at a time.
    /// Past `MergeWatch.maximumInARow` the names stop being the point — the
    /// news is that a batch went in.
    public static let manyHeadline = "MERGED"

    public static func manyTitle(_ count: Int) -> String {
        "\(count) PULL REQUESTS"
    }

    /// How much of a login and a repository name the banner will carry.
    ///
    /// The banner is 12% of the screen's width and the font is fixed-width, so
    /// length is not a styling question here — it is the difference between a
    /// nod and a wall. `elevation-church-mobile-rust` alone is wider than the
    /// whole banner is allowed to be at 3x, and the part of it that identifies
    /// anything is over by the eighth character.
    ///
    /// Cut rather than ellipsised: the font has no ellipsis and three full
    /// stops cost three characters to say that characters were cut, which is a
    /// bad trade when there are only sixteen of them.
    static let nameLimit = 14
    static let repoLimit = 16

    /// Shouted here rather than left to `BannerFont.render`, which uppercases
    /// anything it is given anyway. The font having the last word is what makes
    /// it safe; these functions returning what the banner will actually show is
    /// what makes them testable, and what keeps `Achievement.headline` — a
    /// literal in capitals — and these two the same kind of thing.
    static func clipped(_ text: String, to limit: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces).uppercased()
        return trimmed.count <= limit ? trimmed : String(trimmed.prefix(limit))
    }

    /// The git merge glyph: a branch curving into a trunk.
    ///
    /// Eleven cells square, matching the achievement star, so both banners put
    /// the same weight of drawing beside the same two lines of type —
    /// `Achievement.emblemScale` sizes it against the text either way, but two
    /// emblems of wildly different footprints would still give the two banners
    /// different shapes for no reason the reader could name.
    ///
    /// Entirely `accent`, like the star, so the one green is resolved live
    /// rather than written down a second time.
    public static let emblem = Sprite([
        ".aaa...aaa.",
        ".aaa...aaa.",
        ".aaa...aaa.",
        "..a.....a..",
        "..a.....a..",
        "..a....a...",
        "..a..aa....",
        "..aaa......",
        ".aaa.......",
        ".aaa.......",
        ".aaa.......",
    ])
}

extension SpriteLayout {
    /// The merge glyph, tinted by the one health that means "clear" — the same
    /// one the trophy star takes, and the same one the ready-to-merge count on
    /// the badge already wears.
    public static func mergeEmblem() -> SpriteLayout {
        single(MergeNotice.emblem, accent: .good)
    }
}
