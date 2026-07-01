import Foundation

/// Projects future daily spend using EWMA smoothing over deseasonalized costs
/// with day-of-week (DOW) seasonality factors.
///
/// Algorithm:
///  1. Winsorize historical days at 3× median to clip outliers.
///  2. Compute per-weekday factors from observed data (≥4 samples) or fixed priors.
///  3. Deseasonalize each training sample by dividing by its weekday factor.
///  4. Run EWMA (α=0.25) on the deseasonalized series, oldest→newest.
///     Today's partial spend is scaled to a 24-hour equivalent and appended last.
///  5. Re-seasonalize the EWMA level for each future day using that day's factor.
///  6. Suppress projection entirely when the last 3 complete days are all zero.
enum SpendProjector {

    struct DayForecast: Identifiable {
        let day: String   // "yyyy-MM-dd"
        let cost: Double  // projected spend
        var id: String { day }
    }

    /// Day-of-week spend priors (0=Sunday … 6=Saturday), normalized around 1.0.
    /// Applied until a weekday accumulates ≥4 observed days.
    /// Values derived from observed developer-tool usage patterns: weekdays elevated, weekends depressed.
    private static let dowPriors: [Int: Double] = [
        0: 0.40,  // Sunday
        1: 1.30,  // Monday
        2: 1.40,  // Tuesday
        3: 1.30,  // Wednesday
        4: 1.20,  // Thursday
        5: 1.10,  // Friday
        6: 0.50,  // Saturday
    ]

    private static let ewmaAlpha = 0.25

    /// Returns per-day spend forecasts for each day in `futureDays`.
    /// Returns `[]` when projection should be suppressed.
    static func forecast(
        aggregates: [String: DailyAggregate],
        futureDays: [String],
        todayKey: String,
        now: Date = Date()
    ) -> [DayForecast] {
        guard !futureDays.isEmpty else { return [] }

        let historical = (1...30).map { DayBucket.day(daysAgo: $0, from: now) }

        // Zero-regime suppression
        let last3 = historical.prefix(3).map { aggregates[$0]?.totalCost ?? 0 }
        guard !last3.allSatisfy({ $0 == 0 }) else { return [] }

        let dowFactors = computeDOWFactors(historicalDays: historical, aggregates: aggregates)

        // Build training samples oldest→newest; include today scaled for partial elapsed time
        var samples: [(day: String, cost: Double)] = historical.reversed().map { day in
            (day, aggregates[day]?.totalCost ?? 0)
        }
        let cal = Calendar.current
        let elapsed = Double(cal.component(.hour, from: now)) +
                      Double(cal.component(.minute, from: now)) / 60.0
        if elapsed >= 1.0 {
            let scaled = (aggregates[todayKey]?.totalCost ?? 0) * (24.0 / elapsed)
            samples.append((todayKey, scaled))
        }

        // Deseasonalize and run EWMA
        var level: Double?
        for (day, cost) in samples {
            let factor = dowFactor(for: day, factors: dowFactors)
            let deseas = factor > 0 ? cost / factor : cost
            level = level.map { ewmaAlpha * deseas + (1 - ewmaAlpha) * $0 } ?? deseas
        }

        guard let ewmaLevel = level, ewmaLevel > 0 else { return [] }

        return futureDays.map { day in
            let factor = dowFactor(for: day, factors: dowFactors)
            return DayForecast(day: day, cost: max(0, ewmaLevel * factor))
        }
    }

    // MARK: - Helpers

    private static func computeDOWFactors(
        historicalDays: [String],
        aggregates: [String: DailyAggregate]
    ) -> [Int: Double] {
        var byWeekday: [Int: [Double]] = [:]
        for day in historicalDays {
            let wd = weekday(of: day)
            byWeekday[wd, default: []].append(aggregates[day]?.totalCost ?? 0)
        }

        let allCosts = historicalDays.compactMap { aggregates[$0]?.totalCost }.filter { $0 > 0 }
        let cap = allCosts.isEmpty ? Double.infinity : 3.0 * median(allCosts)

        var rawAvg: [Int: Double] = [:]
        for (wd, costs) in byWeekday where costs.count >= 4 {
            let winsorized = costs.map { min($0, cap) }
            rawAvg[wd] = winsorized.reduce(0, +) / Double(winsorized.count)
        }

        guard rawAvg.count >= 5 else { return dowPriors }

        let overall = rawAvg.values.reduce(0, +) / Double(rawAvg.count)
        guard overall > 0 else { return dowPriors }

        var factors = rawAvg.mapValues { $0 / overall }
        for (wd, prior) in dowPriors where factors[wd] == nil {
            factors[wd] = prior
        }
        return factors
    }

    private static func dowFactor(for dayString: String, factors: [Int: Double]) -> Double {
        factors[weekday(of: dayString)] ?? 1.0
    }

    private static func weekday(of dayString: String) -> Int {
        guard let date = DayBucket.date(fromDay: dayString) else { return 1 }
        return Calendar.current.component(.weekday, from: date) - 1  // 0=Sunday
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2.0 : sorted[mid]
    }
}
