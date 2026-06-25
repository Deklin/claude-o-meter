import Foundation

enum Fmt {
    static func usd(_ v: Double) -> String { String(format: "$%.2f", v) }

    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...: return String(format: "%.1fM", Double(n) / 1_000_000)
        case 1_000...:     return String(format: "%.1fK", Double(n) / 1_000)
        default:           return "\(n)"
        }
    }

    /// "yyyy-MM-dd" -> short display like "Mon Jun 23".
    static func dayLabel(_ day: String) -> String {
        let inF = DateFormatter()
        inF.locale = Locale(identifier: "en_US_POSIX")
        inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: day) else { return day }
        let outF = DateFormatter()
        outF.dateFormat = "EEE MMM d"
        return outF.string(from: d)
    }
}
