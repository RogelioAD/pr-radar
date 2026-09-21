import Foundation

/// A trophy's permanent name.
///
/// These raw values are written into `UserDefaults` the moment a trophy is
/// earned, so they are the one part of this feature that can never be edited:
/// renaming a case does not rename what is already on somebody's shelf, it
/// takes the trophy away from them. Remove a trophy from `Trophy.all` if it
/// stops earning its place — the stored id simply stops being read — but do
/// not reuse the spelling for something else.
public enum TrophyID: String, CaseIterable, Sendable {

    // The review queue.
    case inboxZero
    case backToZero
    case cleanSweep
    case swamped
    case inDemand

    // Your own pull requests.
    case juggler
    case greenLight
    case allClear
    case shortStack
    case tallStack
    case branchingOut
    case rubberStamp

    // What time you did it at.
    case nightWatch
    case weekendWork

    // The app itself.
    case meetTheCast
    case bigBadge
    case tinyBadge
    case pancakePress
    case regular
    case veteran
    case upToDate

    // The long count.
    case fiftyMerged
    case century

    // Hidden.
    case homeTeam
    case peerReview
    case fullCircle
    case palindrome
    case zeroSum
    case carousel
    case fourCorners
}

/// One trophy: what it is called, what earns it, and what it looks like.
public struct Trophy: Identifiable, Sendable {
    public let id: TrophyID
    public let name: String
    /// How to get it, in one sentence, written as an instruction. This is the
    /// tooltip, so it is the only explanation a trophy ever gets.
    public let hint: String
    /// Hidden trophies keep both their name and their hint back until earned.
    public let isHidden: Bool
    public let art: Sprite

    init(_ id: TrophyID, _ name: String, _ hint: String,
         hidden: Bool = false, art: Sprite) {
        self.id = id
        self.name = name
        self.hint = hint
        self.isHidden = hidden
        self.art = art
    }
}

extension Trophy {

    /// What the grid draws for this trophy, given whether it has been earned.
    ///
    /// The locked *colour* is not decided here — that is one flag on the
    /// canvas, so an unlock is the same drawing gaining its hue. What is
    /// decided here is whether it is the same drawing at all: a hidden trophy
    /// is a question mark until the moment it is not.
    public func art(unlocked: Bool) -> Sprite {
        isHidden && !unlocked ? Self.mystery : art
    }

    public func name(unlocked: Bool) -> String {
        isHidden && !unlocked ? Self.redacted : name
    }

    /// The hover text.
    ///
    /// Name and hint together, earned or not: knowing what a locked trophy
    /// wants is the whole reason to look at a locked trophy, and knowing what
    /// an earned one *was* for is the whole reason to look at it afterwards.
    public func tooltip(unlocked: Bool) -> String {
        guard !(isHidden && !unlocked) else { return Self.redacted }
        return "\(name) — \(hint)"
    }

    /// What a hidden trophy says for itself. Three characters, and no promise
    /// about how many there are or how close you are to one.
    public static let redacted = "???"

    /// The stand-in art for a hidden trophy, and the only drawing in the set
    /// used more than once.
    public static let mystery = TrophyArt.badge(.plaque,
                                                motif: TrophyMotif.mystery,
                                                tier: .bronze)
}

extension SpriteLayout {
    /// One trophy, ready for `SpriteCanvas`.
    ///
    /// A layout rather than a bare `Sprite` for the same reason
    /// `pancakeStack` is one: the canvas draws layouts, and `Layer`'s init is
    /// internal to this module.
    public static func trophy(_ sprite: Sprite) -> SpriteLayout {
        single(sprite)
    }
}

extension Trophy {

    /// The shelf, in the order it is shown.
    ///
    /// Grouped by what earns them rather than by difficulty, because the room
    /// is read as a map of what the app can notice about you — and hidden ones
    /// last, so the run of question marks at the end is the one thing you
    /// cannot help seeing.
    public static let all: [Trophy] = [

        // MARK: The review queue

        Trophy(.inboxZero, "Inbox Zero",
               "Clear your review queue.",
               art: TrophyArt.badge(.medal, motif: TrophyMotif.inboxZero, tier: .gold)),
        Trophy(.backToZero, "Back to Zero",
               "Clear your review queue five times.",
               art: TrophyArt.badge(.medal, motif: TrophyMotif.backToZero, tier: .silver)),
        Trophy(.cleanSweep, "Clean Sweep",
               "Go from ten or more reviews waiting to none in one go.",
               art: TrophyArt.badge(.shield, motif: TrophyMotif.cleanSweep, tier: .gold)),
        Trophy(.swamped, "Swamped",
               "Have ten reviews waiting on you at once.",
               art: TrophyArt.badge(.shield, motif: TrophyMotif.swamped, tier: .bronze)),
        Trophy(.inDemand, "In Demand",
               "Have reviews waiting from five different people at once.",
               art: TrophyArt.badge(.medal, motif: TrophyMotif.inDemand, tier: .bronze)),

        // MARK: Your own pull requests

        Trophy(.juggler, "Juggler",
               "Have five of your own pull requests open at once.",
               art: TrophyArt.badge(.cup, motif: TrophyMotif.juggler, tier: .bronze)),
        Trophy(.greenLight, "Green Light",
               "Have one of your pull requests ready to merge.",
               art: TrophyArt.badge(.medal, motif: TrophyMotif.greenLight, tier: .silver)),
        Trophy(.allClear, "All Clear",
               "Have three or more pull requests open, with every one ready to merge.",
               art: TrophyArt.badge(.cup, motif: TrophyMotif.allClear, tier: .gold)),
        Trophy(.shortStack, "Short Stack",
               "Have a stack two pull requests deep.",
               art: TrophyArt.badge(.plaque, motif: TrophyMotif.shortStack, tier: .bronze)),
        Trophy(.tallStack, "Tall Stack",
               "Have a stack four pull requests deep.",
               art: TrophyArt.badge(.plaque, motif: TrophyMotif.tallStack, tier: .silver)),
        Trophy(.branchingOut, "Branching Out",
               "Have two pull requests stacked on the same parent.",
               art: TrophyArt.badge(.shield, motif: TrophyMotif.branchingOut, tier: .silver)),
        Trophy(.rubberStamp, "Rubber Stamp",
               "Collect three approvals on one pull request.",
               art: TrophyArt.badge(.plaque, motif: TrophyMotif.rubberStamp, tier: .bronze)),

        // MARK: What time you did it at

        Trophy(.nightWatch, "Night Watch",
               "Clear your review queue between 10pm and 4am.",
               art: TrophyArt.badge(.medal, motif: TrophyMotif.nightWatch, tier: .silver)),
        Trophy(.weekendWork, "Weekend Work",
               "Clear your review queue on a Saturday or a Sunday.",
               art: TrophyArt.badge(.medal, motif: TrophyMotif.weekendWork, tier: .bronze)),

        // MARK: The app itself

        Trophy(.meetTheCast, "Meet the Cast",
               "Show every mascot at least once.",
               art: TrophyArt.badge(.plaque, motif: TrophyMotif.meetTheCast, tier: .silver)),
        Trophy(.bigBadge, "Big Badge",
               "Drag the badge to its largest size.",
               art: TrophyArt.badge(.plaque, motif: TrophyMotif.bigBadge, tier: .bronze)),
        Trophy(.tinyBadge, "Tiny Badge",
               "Drag the badge to its smallest size.",
               art: TrophyArt.badge(.plaque, motif: TrophyMotif.tinyBadge, tier: .bronze)),
        Trophy(.pancakePress, "Pancake Press",
               "Turn on the stacked-only filter.",
               art: TrophyArt.badge(.shield, motif: TrophyMotif.pancakePress, tier: .gold)),
        Trophy(.regular, "Regular",
               "Keep PR Radar running for seven days.",
               art: TrophyArt.badge(.shield, motif: TrophyMotif.regular, tier: .bronze)),
        Trophy(.veteran, "Veteran",
               "Keep PR Radar running for thirty days.",
               art: TrophyArt.badge(.shield, motif: TrophyMotif.veteran, tier: .gold)),
        Trophy(.upToDate, "Up to Date",
               "Install a release the update chip offered you.",
               art: TrophyArt.badge(.medal, motif: TrophyMotif.upToDate, tier: .bronze)),

        // MARK: The long count

        Trophy(.fiftyMerged, "Fifty Merged",
               "Merge fifty pull requests.",
               art: TrophyArt.badge(.cup, motif: TrophyMotif.fiftyMerged, tier: .silver)),
        Trophy(.century, "Century",
               "Merge a hundred pull requests.",
               art: TrophyArt.badge(.cup, motif: TrophyMotif.century, tier: .gold)),

        // MARK: Hidden

        Trophy(.homeTeam, "Home Team",
               "Open a pull request on PR Radar itself.",
               hidden: true, art: TrophyArtHidden.homeTeam),
        Trophy(.peerReview, "Peer Review",
               "Be asked to review a pull request on PR Radar itself.",
               hidden: true, art: TrophyArtHidden.peerReview),
        Trophy(.fullCircle, "Full Circle",
               "Have PR Radar's own repository in both tabs at once.",
               hidden: true, art: TrophyArtHidden.fullCircle),
        Trophy(.palindrome, "Palindrome",
               "Open a pull request whose number reads the same backwards.",
               hidden: true, art: TrophyArtHidden.palindrome),
        Trophy(.zeroSum, "Zero Sum",
               "Open a pull request that adds exactly as many lines as it takes away.",
               hidden: true, art: TrophyArtHidden.zeroSum),
        Trophy(.carousel, "Carousel",
               "Cycle the mascot ten times without closing the drawer.",
               hidden: true, art: TrophyArtHidden.carousel),
        Trophy(.fourCorners, "Four Corners",
               "Park the badge in all four corners of a screen.",
               hidden: true, art: TrophyArtHidden.fourCorners),
    ]

    private static let byID: [TrophyID: Trophy] =
        Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    /// Traps on an id with no trophy, which can only mean `all` and `TrophyID`
    /// have drifted apart — a mistake in this file, not a state the app can
    /// reach at runtime. The test suite walks every case.
    public static func named(_ id: TrophyID) -> Trophy {
        guard let trophy = byID[id] else {
            preconditionFailure("no trophy for \(id.rawValue)")
        }
        return trophy
    }

    public static var hidden: [Trophy] { all.filter(\.isHidden) }
}
