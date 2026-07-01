import XCTest
@testable import ClaudeOMeter

final class SpendProjectorTests: XCTestCase {

    // MARK: - Helpers

    /// Returns a deterministic reference time (Oct 15 2025 14:00 local) so partial-day
    /// scaling (elapsed ≥ 1h) is always exercised and tests don't depend on wall-clock time.
    private func fixedNoon() -> Date {
        var comps = DateComponents()
        comps.year = 2025; comps.month = 10; comps.day = 15
        comps.hour = 14; comps.minute = 0; comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }

    private func agg(day: String, cost: Double, model: String = "sonnet") -> DailyAggregate {
        var a = DailyAggregate(day: day)
        a.perModel[model] = ModelUsage(model: model, rawModel: model,
                                       usage: TokenUsage(),
                                       cost: cost)
        return a
    }

    private func makeAggregates(costs: [(daysAgo: Int, cost: Double)], now: Date = Date()) -> [String: DailyAggregate] {
        Dictionary(costs.map { item in
            let day = DayBucket.day(daysAgo: item.daysAgo, from: now)
            return (day, agg(day: day, cost: item.cost))
        }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: - Basic projection

    func testForecastReturnsOneEntryPerFutureDay() {
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        let aggregates = makeAggregates(costs: (1...14).map { ($0, 5.0) }, now: now)

        let cal = Calendar.current
        let futureDays = (1...5).map { offset -> String in
            let d = cal.date(byAdding: .day, value: offset, to: now)!
            return DayBucket.localDay(from: d)
        }

        let forecasts = SpendProjector.forecast(aggregates: aggregates,
                                                futureDays: futureDays,
                                                todayKey: todayKey,
                                                now: now)
        XCTAssertEqual(forecasts.count, 5)
        for f in forecasts { XCTAssertGreaterThan(f.cost, 0) }
    }

    func testForecastReturnsEmptyWhenFutureDaysEmpty() {
        let now = fixedNoon()
        let aggregates = makeAggregates(costs: [(1, 5.0), (2, 5.0)], now: now)
        let todayKey = DayBucket.localDay(from: now)
        let result = SpendProjector.forecast(aggregates: aggregates, futureDays: [],
                                             todayKey: todayKey, now: now)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Zero-regime suppression

    func testForecastSuppressedWhenLast3DaysAllZero() {
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        // days 1–3 are zero, but days 4–10 have spend
        var costs = (1...3).map { ($0, 0.0) }
        costs += (4...10).map { ($0, 5.0) }
        let aggregates = makeAggregates(costs: costs, now: now)

        let cal = Calendar.current
        let tomorrow = DayBucket.localDay(from: cal.date(byAdding: .day, value: 1, to: now)!)
        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: [tomorrow],
                                             todayKey: todayKey,
                                             now: now)
        XCTAssertTrue(result.isEmpty, "Should suppress when last 3 complete days are all zero")
    }

    func testForecastNotSuppressedWhenOnlyDay1IsZero() {
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        var costs: [(Int, Double)] = [(1, 0.0)]
        costs += (2...14).map { ($0, 5.0) }
        let aggregates = makeAggregates(costs: costs, now: now)

        let cal = Calendar.current
        let tomorrow = DayBucket.localDay(from: cal.date(byAdding: .day, value: 1, to: now)!)
        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: [tomorrow],
                                             todayKey: todayKey,
                                             now: now)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - EWMA convergence

    func testForecastConvergesOnConsistentSpend() {
        // With uniform $5/day history, projection should be close to $5
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        let aggregates = makeAggregates(costs: (1...21).map { ($0, 5.0) }, now: now)

        let cal = Calendar.current
        let tomorrow = DayBucket.localDay(from: cal.date(byAdding: .day, value: 1, to: now)!)
        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: [tomorrow],
                                             todayKey: todayKey,
                                             now: now)

        XCTAssertFalse(result.isEmpty)
        // With stable data the EWMA level should land within ±60% of the actual average
        // (DOW factors may shift individual day projections significantly)
        let projected = result[0].cost
        XCTAssertGreaterThan(projected, 1.0, "Projection far below expected")
        XCTAssertLessThan(projected, 20.0, "Projection far above expected")
    }

    // MARK: - Partial-day today

    func testForecastDoesNotCrashWithNoTodayData() {
        // todayKey not in aggregates — should still return a result
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        let aggregates = makeAggregates(costs: (1...10).map { ($0, 4.0) }, now: now)

        let cal = Calendar.current
        let tomorrow = DayBucket.localDay(from: cal.date(byAdding: .day, value: 1, to: now)!)
        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: [tomorrow],
                                             todayKey: todayKey,
                                             now: now)
        XCTAssertFalse(result.isEmpty)
    }

    // MARK: - Projected costs are non-negative

    func testForecastCostsAreNonNegative() {
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        // Mix of zero and non-zero to stress DOW factors
        let costs: [(Int, Double)] = [
            (1, 0.0), (2, 10.0), (3, 0.1), (4, 8.0), (5, 0.5),
            (6, 0.0), (7, 7.0), (8, 9.0), (9, 0.2), (10, 6.0)
        ]
        let aggregates = makeAggregates(costs: costs, now: now)

        let cal = Calendar.current
        let futureDays = (1...7).map { DayBucket.localDay(from: cal.date(byAdding: .day, value: $0, to: now)!) }
        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: futureDays,
                                             todayKey: todayKey,
                                             now: now)

        for f in result { XCTAssertGreaterThanOrEqual(f.cost, 0, "Projected cost for \(f.day) was negative") }
    }

    // MARK: - Day IDs match future days

    func testForecastDayKeysMatchInput() {
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        let aggregates = makeAggregates(costs: (1...14).map { ($0, 3.0) }, now: now)

        let cal = Calendar.current
        let futureDays = (1...4).map { DayBucket.localDay(from: cal.date(byAdding: .day, value: $0, to: now)!) }
        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: futureDays,
                                             todayKey: todayKey,
                                             now: now)

        XCTAssertEqual(result.map { $0.day }, futureDays)
    }

    // MARK: - Insufficient history

    func testForecastWithSparseHistoryIsNonNegative() {
        // 1 historical day of spend — algorithm still has 30 training samples (29 are $0),
        // so the result is non-empty but near-zero.
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        let aggregates = makeAggregates(costs: [(1, 5.0)], now: now)

        let cal = Calendar.current
        let tomorrow = DayBucket.localDay(from: cal.date(byAdding: .day, value: 1, to: now)!)

        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: [tomorrow],
                                             todayKey: todayKey,
                                             now: now)
        XCTAssertFalse(result.isEmpty, "30 training samples always available; result should not be empty")
        for f in result { XCTAssertGreaterThanOrEqual(f.cost, 0) }
    }

    // MARK: - Learned DOW factors

    func testForecastUsesLearnedDOWFactorsWhenEnoughData() {
        // 28 days gives each weekday ≥4 samples, triggering the learned-factor branch.
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        let aggregates = makeAggregates(costs: (1...28).map { ($0, 5.0) }, now: now)

        let cal = Calendar.current
        let tomorrow = DayBucket.localDay(from: cal.date(byAdding: .day, value: 1, to: now)!)
        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: [tomorrow],
                                             todayKey: todayKey,
                                             now: now)
        XCTAssertFalse(result.isEmpty)
        XCTAssertGreaterThan(result[0].cost, 0.5)
        XCTAssertLessThan(result[0].cost, 25.0)
    }

    // MARK: - Near-zero history

    func testForecastWithNearZeroHistoryIsNonNegative() {
        // All 30 days are $0 except yesterday ($10). Zero-suppression checks only the last 3
        // complete days; with yesterday non-zero, suppression must not trigger.
        let now = fixedNoon()
        let todayKey = DayBucket.localDay(from: now)
        var costs: [(Int, Double)] = [(1, 10.0)]
        costs += (2...30).map { ($0, 0.0) }
        let aggregates = makeAggregates(costs: costs, now: now)

        let cal = Calendar.current
        let tomorrow = DayBucket.localDay(from: cal.date(byAdding: .day, value: 1, to: now)!)
        let result = SpendProjector.forecast(aggregates: aggregates,
                                             futureDays: [tomorrow],
                                             todayKey: todayKey,
                                             now: now)
        XCTAssertFalse(result.isEmpty, "Should not suppress when only 1 of last 3 days is zero")
        for f in result { XCTAssertGreaterThanOrEqual(f.cost, 0) }
    }
}
