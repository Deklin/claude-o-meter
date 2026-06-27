import Foundation

/// Locale-aware formatting. Amounts are USD (what Anthropic/Bedrock bills), but grouping and
/// decimal separators follow the user's region (e.g. "$1,234.56" vs "1.234,56 $US").
enum Fmt {
    private static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = .current
        return f
    }()

    /// For abbreviated values like "1.2M" — uses the region's decimal separator.
    private static let abbrev: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    /// Grouped integers like "12,345" / "12.345".
    private static let grouped: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = .current
        f.maximumFractionDigits = 0
        return f
    }()

    static func usd(_ v: Double) -> String {
        currency.string(from: NSNumber(value: v)) ?? String(format: "$%.2f", v)
    }

    static func tokens(_ n: Int) -> String {
        switch n {
        case 1_000_000...:
            let s = abbrev.string(from: NSNumber(value: Double(n) / 1_000_000)) ?? "\(n / 1_000_000)"
            return s + "M"
        case 1_000...:
            let s = abbrev.string(from: NSNumber(value: Double(n) / 1_000)) ?? "\(n / 1_000)"
            return s + "K"
        default:
            return grouped.string(from: NSNumber(value: n)) ?? "\(n)"
        }
    }

    private static let dayIn: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let dayOut: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return f
    }()

    private static let shortDateOut: DateFormatter = {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("MMM d")
        return f
    }()

    /// "yyyy-MM-dd" -> short display like "Mon Jun 23".
    static func dayLabel(_ day: String) -> String {
        guard let d = dayIn.date(from: day) else { return day }
        return dayOut.string(from: d)
    }

    /// "yyyy-MM-dd" -> compact display like "Jun 20".
    static func shortDate(_ day: String) -> String {
        guard let d = dayIn.date(from: day) else { return day }
        return shortDateOut.string(from: d)
    }
}
