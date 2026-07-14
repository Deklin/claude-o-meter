import Foundation

/// Projects the remaining hours of *today* by blending two signals:
///
///  1. **History expectation** — what a full day like today typically costs, from
///     `SpendProjector` (30-day EWMA with day-of-week seasonality, outlier-winsorized).
///  2. **Today's pace** — today's spend so far, extrapolated to a full 24h.
///
/// The two are blended by how far into the day we are (`w = elapsedFraction`): early in
/// the day history dominates (today is weak evidence); late in the day today's actuals
/// dominate. This is a simple Kalman-style nowcast — trust the prior until observations
/// accumulate.
///
/// The remaining budget (`target − spentSoFar`) is then distributed across the remaining
/// hours using a fixed intra-day shape prior, so the projected cumulative line bends with
/// the typical work rhythm (tapering into the evening) instead of running flat into midnight.
///
/// Suppressed (returns `[]`) when the viewed day isn't today, the day is over (hour 23),
/// or there is no basis to project (no spend yet *and* no history expectation).
enum HourlyProjector {

    struct HourForecast: Identifiable {
        let hour: Int      // 0-23
        let cost: Double   // projected spend for that hour
        var id: Int { hour }
    }

    /// Relative intra-day spend weights (hour 0–23), reflecting a typical developer rhythm:
    /// quiet overnight, ramp through the morning, midday peak with a slight lunch dip, a
    /// strong afternoon, then a taper through the evening. Only *ratios* matter — the weights
    /// are normalized over whatever hours remain.
    private static let hourShape: [Double] = [
        0.20, 0.10, 0.10, 0.10, 0.10, 0.15,   // 0–5   overnight
        0.30, 0.60, 1.00, 1.50, 1.60, 1.50,   // 6–11  morning ramp → peak
        1.00, 1.40, 1.60, 1.50, 1.40, 1.10,   // 12–17 lunch dip → afternoon peak
        0.80, 0.70, 0.70, 0.60, 0.40, 0.30,   // 18–23 evening taper
    ]

    /// - Parameters:
    ///   - slices: today's per-hour actuals (only `hour`/`cost` are read).
    ///   - aggregates: full daily history, for the day-of-week expectation.
    ///   - todayKey: today's "yyyy-MM-dd".
    ///   - isToday: whether the viewed day is the current day.
    ///   - now: reference time (injectable for tests); drives current hour + elapsed fraction.
    /// - Returns: one forecast per remaining hour `(currentHour+1)…23`, or `[]` when suppressed.
    static func forecast(
        slices: [HourlySlice],
        aggregates: [String: DailyAggregate],
        todayKey: String,
        isToday: Bool,
        now: Date = Date()
    ) -> [HourForecast] {
        guard isToday else { return [] }

        let cal = Calendar.current
        let currentHour = cal.component(.hour, from: now)
        guard currentHour < 23 else { return [] }

        let spentSoFar = slices.filter { $0.hour <= currentHour }.reduce(0) { $0 + $1.cost }

        // Fraction of the day elapsed (clamped away from zero so the pace extrapolation is stable).
        let elapsed = Double(currentHour) + Double(cal.component(.minute, from: now)) / 60.0
        let safeElapsed = max(elapsed, 0.5)
        let elapsedFraction = min(1.0, safeElapsed / 24.0)

        // History-based full-day expectation for today (0 when suppressed / no history).
        let historyExpectation = SpendProjector.forecast(
            aggregates: aggregates,
            futureDays: [todayKey],
            todayKey: todayKey,
            now: now
        ).first?.cost ?? 0

        // Today's pace extrapolated to a full day.
        let todayExtrapolation = spentSoFar * (24.0 / safeElapsed)

        // Blend two full-day estimates: history when early, today's actuals when late.
        // A zero history expectation means "no usable prior" (no history or zero-regime
        // suppression), not "the prior predicts $0" — so don't average against it; lean
        // entirely on today's pace instead.
        let target: Double
        if historyExpectation > 0 {
            target = (1 - elapsedFraction) * historyExpectation + elapsedFraction * todayExtrapolation
        } else {
            target = todayExtrapolation
        }

        let remainingBudget = max(0, target - spentSoFar)
        guard remainingBudget > 0 else { return [] }

        let remainingHours = Array((currentHour + 1)...23)
        let weights = remainingHours.map { hourShape[$0] }
        let weightSum = weights.reduce(0, +)

        return zip(remainingHours, weights).map { hour, w in
            // Fall back to an even split if the shape weights degenerate to zero.
            let share = weightSum > 0 ? w / weightSum : 1.0 / Double(remainingHours.count)
            return HourForecast(hour: hour, cost: remainingBudget * share)
        }
    }
}
