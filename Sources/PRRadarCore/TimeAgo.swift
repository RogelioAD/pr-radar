import Foundation

public enum TimeAgo {
    /// Compact, narrow-row-friendly age: "now", "14m", "3h", "13d".
    public static func short(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3_600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    /// Spoken form for notifications and tooltips.
    public static func long(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 {
            let m = Int(seconds / 60)
            return "\(m) minute\(m == 1 ? "" : "s") ago"
        }
        if seconds < 86_400 {
            let h = Int(seconds / 3_600)
            return "\(h) hour\(h == 1 ? "" : "s") ago"
        }
        let d = Int(seconds / 86_400)
        return "\(d) day\(d == 1 ? "" : "s") ago"
    }
}
