import Foundation

/// The one-off strip that says a cohort of characters has arrived.
///
/// Its whole job is to be seen once and then stop. A banner that comes back
/// every time the drawer opens is not an announcement, it is an advert — and
/// this one sits above the list somebody opened the drawer to read.
///
/// It was tied to October when the Halloween four were seasonal. They are
/// permanent now, so the month has nothing to do with it: what it announces
/// is the newest cohort this build ships, once, to whoever has not seen it.
/// Adding a fifth cohort makes it news again with no code here changing.
public enum NewCastNotice {

    /// The cohort a build announces: the last built-in one the cast declares.
    ///
    /// Read off `MascotCohort.ordered` rather than written down, so the day a
    /// cohort is appended this follows it. `custom` is never announced — a
    /// fork's own characters are not news to the fork that wrote them.
    public static var cohort: MascotCohort? {
        MascotCohort.ordered.last { $0 != .custom && !Mascot.cohort($0).isEmpty }
    }

    /// Who the banner is showing.
    public static var visitors: [MascotID] {
        guard let cohort else { return [] }
        return Mascot.cohort(cohort).map(\.id)
    }

    /// Whether to show it. `acknowledged` is the cohort already dismissed.
    public static func shouldShow(acknowledged: String?) -> Bool {
        guard let cohort else { return false }
        return cohort.rawValue != acknowledged
    }

    /// What dismissing it records.
    public static var acknowledgement: String? { cohort?.rawValue }

    /// The heading. The cohort's own title, which is what the room calls it,
    /// so the banner and the shelf it points at agree.
    public static var headline: String {
        cohort?.title ?? "New mascots"
    }

    /// "Boo, Flit, Gourd and Rattle" — an Oxford-less list, because it is a
    /// caption rather than prose.
    public static func names(_ ids: [MascotID]) -> String {
        let names = ids.map { Mascot.named($0).name }
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }
}
