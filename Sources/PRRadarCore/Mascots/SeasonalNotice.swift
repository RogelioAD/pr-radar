import Foundation

/// The one-off announcement that a seasonal cast has arrived.
///
/// Its whole job is to be seen once and then stop. A banner that comes back
/// every time the drawer opens is not an announcement, it is an advert — and
/// this one sits above the list somebody opened the drawer to read.
///
/// Everything here is derived from what the cast declares rather than written
/// down a second time. Give a character `.month(12)` and December starts
/// announcing itself, with the right names in it, and no code here changes.
public enum SeasonalNotice {

    /// The season in progress, as the key the acknowledgement is stored under,
    /// or nil on a day no cast is visiting.
    ///
    /// Keyed by year as well as month so it comes round again: the news in
    /// October 2027 is not the news somebody dismissed in October 2026.
    public static func season(on date: Date, calendar: Calendar = .current) -> String? {
        let month = calendar.component(.month, from: date)
        guard MascotID.allCases.contains(where: { $0.season == .month(month) }) else {
            return nil
        }
        return String(format: "%04d-%02d", calendar.component(.year, from: date), month)
    }

    /// Who is visiting today, in the cast's own order.
    public static func visitors(on date: Date, calendar: Calendar = .current) -> [MascotID] {
        let month = calendar.component(.month, from: date)
        return MascotID.allCases.filter { $0.season == .month(month) }
    }

    /// Whether to show it.
    ///
    /// Tied to the month rather than to the roster, which is the one judgement
    /// call in here. Somebody running with the keep-them-on toggle has their
    /// roster full of visitors in July, and telling them in July that the
    /// October cast has arrived would be announcing a thing they did
    /// themselves, months ago.
    public static func shouldShow(on date: Date,
                                  calendar: Calendar = .current,
                                  acknowledged: String?) -> Bool {
        guard let season = season(on: date, calendar: calendar) else { return false }
        return season != acknowledged
    }

    /// "Boo, Flit, Gourd and Rattle" — an Oxford-less list, because it is a
    /// caption rather than prose.
    public static func names(_ ids: [MascotID]) -> String {
        let names = ids.map { Mascot.named($0).name }
        guard let last = names.last else { return "" }
        guard names.count > 1 else { return last }
        return names.dropLast().joined(separator: ", ") + " and " + last
    }

    /// The month, for the headline.
    public static func monthName(on date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        return formatter.string(from: date)
    }
}
