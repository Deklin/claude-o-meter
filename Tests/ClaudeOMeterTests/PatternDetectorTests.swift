import XCTest
@testable import ClaudeOMeter

final class PatternDetectorTests: XCTestCase {

    // MARK: - Helpers

    /// Build an aggregate for the given day with specified per-model costs and usage.
    private func agg(day: String, model: String = "sonnet", rawModel: String = "claude-sonnet-4-6",
                     input: Int = 0, output: Int = 0,
                     cacheRead: Int = 0, cacheWrite5m: Int = 0) -> (String, DailyAggregate) {
        let usage = TokenUsage(input: input, output: output, cacheRead: cacheRead, cacheWrite5m: cacheWrite5m)
        let pricing = PricingTable.default
        let cost = pricing.cost(of: usage, family: model, rawModel: rawModel)
        var agg = DailyAggregate(day: day)
        agg.perModel[model] = ModelUsage(model: model, rawModel: rawModel, usage: usage, cost: cost)
        return (day, agg)
    }

    /// Fake aggregates with uniform $1/day spend across `n` days ending `endDaysAgo` (exclusive today = 0).
    private func uniformAggs(perDay: Double = 1.0, from startDaysAgo: Int = 1, count: Int = 14, now: Date = Date()) -> [String: DailyAggregate] {
        var result: [String: DailyAggregate] = [:]
        for offset in startDaysAgo..<(startDaysAgo + count) {
            let day = DayBucket.day(daysAgo: offset, from: now)
            var dailyAgg = DailyAggregate(day: day)
            dailyAgg.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                                      usage: TokenUsage(), cost: perDay)
            result[day] = dailyAgg
        }
        return result
    }

    // MARK: - Guard: returns empty when total < $0.50

    func testDetectReturnsEmptyWhenSpendTooLow() {
        var aggs: [String: DailyAggregate] = [:]
        for i in 1...7 {
            let day = DayBucket.day(daysAgo: i)
            var d = DailyAggregate(day: day)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                              usage: TokenUsage(), cost: 0.02)
            aggs[day] = d
        }
        let insights = PatternDetector.detect(aggregates: aggs)
        XCTAssertTrue(insights.isEmpty, "Expected empty insights when 7-day spend < $0.50")
    }

    // MARK: - Cache efficiency

    func testCacheMissDetected() {
        // 100K input, zero cache read → hitRate = 0% < 15%
        var aggs = uniformAggs(perDay: 1.0)
        let day = DayBucket.day(daysAgo: 1)
        var d = DailyAggregate(day: day)
        d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                           usage: TokenUsage(input: 100_000), cost: 1.0)
        aggs[day] = d
        let insights = PatternDetector.detect(aggregates: aggs)
        XCTAssertTrue(insights.contains { $0.id == "cache_miss" })
    }

    func testHighCacheHitRateDetected() {
        // 10K input + 90K cacheRead → hitRate = 90% ≥ 50%
        let now = Date()
        var aggs = uniformAggs(perDay: 1.0, now: now)
        let day = DayBucket.day(daysAgo: 1, from: now)
        var d = DailyAggregate(day: day)
        d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                           usage: TokenUsage(input: 10_000, cacheRead: 90_000), cost: 1.0)
        aggs[day] = d
        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertTrue(insights.contains { $0.id == "cache_high" })
    }

    func testCacheEfficiencyNotFiredWhenCacheableBelowThreshold() {
        // cacheable = 30K < 50K threshold → neither cache insight fires
        let now = Date()
        var aggs = uniformAggs(perDay: 1.0, now: now)
        let day = DayBucket.day(daysAgo: 1, from: now)
        var d = DailyAggregate(day: day)
        d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                           usage: TokenUsage(input: 30_000), cost: 1.0)
        aggs[day] = d
        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertFalse(insights.contains { $0.id == "cache_miss" })
        XCTAssertFalse(insights.contains { $0.id == "cache_high" })
    }

    // MARK: - Model selection

    func testOpusHeavyDetected() {
        // 7-day spend ≥ $1 and opus > 60% of it
        let now = Date()
        var aggs: [String: DailyAggregate] = [:]
        for i in 1...7 {
            let day = DayBucket.day(daysAgo: i, from: now)
            var d = DailyAggregate(day: day)
            d.perModel["opus"] = ModelUsage(model: "opus", rawModel: "claude-opus-4-8",
                                             usage: TokenUsage(), cost: 0.80)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                               usage: TokenUsage(), cost: 0.20)
            aggs[day] = d
        }
        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertTrue(insights.contains { $0.id == "opus_heavy" })
    }

    func testModelEfficientDetected() {
        // 7-day spend ≥ $2 and opus < 40% of it
        let now = Date()
        var aggs: [String: DailyAggregate] = [:]
        for i in 1...7 {
            let day = DayBucket.day(daysAgo: i, from: now)
            var d = DailyAggregate(day: day)
            d.perModel["opus"] = ModelUsage(model: "opus", rawModel: "claude-opus-4-8",
                                             usage: TokenUsage(), cost: 0.20)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                               usage: TokenUsage(), cost: 0.80)
            aggs[day] = d
        }
        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertTrue(insights.contains { $0.id == "model_efficient" })
    }

    // MARK: - Spend trend

    func testSpendSpikeDetected() {
        // last7 avg = $2/day, prior7 avg = $1/day → 100% increase ≥ 60% threshold
        let now = Date()
        var aggs: [String: DailyAggregate] = [:]
        for i in 1...7 {
            let day = DayBucket.day(daysAgo: i, from: now)
            var d = DailyAggregate(day: day)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                               usage: TokenUsage(), cost: 2.0)
            aggs[day] = d
        }
        for i in 8...14 {
            let day = DayBucket.day(daysAgo: i, from: now)
            var d = DailyAggregate(day: day)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                               usage: TokenUsage(), cost: 1.0)
            aggs[day] = d
        }
        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertTrue(insights.contains { $0.id == "spend_spike" })
    }

    func testSpendDownDetected() {
        // last7 avg = $0.50/day, prior7 avg = $2/day → 75% decrease ≥ 30% threshold
        let now = Date()
        var aggs: [String: DailyAggregate] = [:]
        for i in 1...7 {
            let day = DayBucket.day(daysAgo: i, from: now)
            var d = DailyAggregate(day: day)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                               usage: TokenUsage(), cost: 0.50)
            aggs[day] = d
        }
        for i in 8...14 {
            let day = DayBucket.day(daysAgo: i, from: now)
            var d = DailyAggregate(day: day)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                               usage: TokenUsage(), cost: 2.0)
            aggs[day] = d
        }
        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertTrue(insights.contains { $0.id == "spend_down" })
    }

    // MARK: - Context bloat

    func testContextBloatDetected() {
        // input = 10M, output = 100K → ratio = 100 ≥ 25
        let now = Date()
        var aggs = uniformAggs(perDay: 1.0, now: now)
        let day = DayBucket.day(daysAgo: 1, from: now)
        var d = DailyAggregate(day: day)
        d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                           usage: TokenUsage(input: 10_000_000, output: 100_000), cost: 1.0)
        aggs[day] = d
        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertTrue(insights.contains { $0.id == "context_bloat" })
    }

    func testContextBloatNotFiredWhenOutputIsZero() {
        // output = 0 → division guard prevents context_bloat
        let now = Date()
        var aggs = uniformAggs(perDay: 1.0, now: now)
        let day = DayBucket.day(daysAgo: 1, from: now)
        var d = DailyAggregate(day: day)
        d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                           usage: TokenUsage(input: 1_000_000, output: 0), cost: 1.0)
        aggs[day] = d
        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertFalse(insights.contains { $0.id == "context_bloat" })
    }

    // MARK: - Burnrate projection

    func testBurnrateDetectedWhenProjectedHighEnough() {
        // Use a fixed reference date well inside a month so we can control day-of-month.
        // 2026-06-15 = day 15 of June (30-day month), 15 days remaining.
        // medianDaily = $0.50/day → projected = MTD + 15*0.50
        // We set MTD = $7.50 → projected = $7.50 + $7.50 = $15 ≥ $10 threshold.
        var components = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        components.year = 2026
        components.month = 6
        components.day = 15
        let now = Calendar.current.date(from: components) ?? Date()

        var aggs: [String: DailyAggregate] = [:]
        // 7 days of history (days 8–14 ago in terms of offset but let's use daysAgo from now)
        for i in 1...7 {
            let day = DayBucket.day(daysAgo: i, from: now)
            var d = DailyAggregate(day: day)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                               usage: TokenUsage(), cost: 0.50)
            aggs[day] = d
        }
        // MTD spend (days 1–14 of June 2026 = 14 days before "today" of June 15)
        // Already covered by the 7-day history above (days 1..7). Add days 8..14:
        for i in 8...14 {
            let day = DayBucket.day(daysAgo: i, from: now)
            var d = DailyAggregate(day: day)
            d.perModel["sonnet"] = ModelUsage(model: "sonnet", rawModel: "claude-sonnet-4-6",
                                               usage: TokenUsage(), cost: 0.50)
            aggs[day] = d
        }

        let insights = PatternDetector.detect(aggregates: aggs, now: now)
        XCTAssertTrue(insights.contains { $0.id == "burnrate" }, "Expected burnrate insight at $0.50/day median")
    }

    // MARK: - tipsToNotify

    func testTipsToNotifyFiresOnFirstOccurrence() {
        let insights = [PatternInsight(id: "opus_heavy", kind: .bad, title: "", detail: "")]
        let ids = PatternDetector.tipsToNotify(insights: insights, lastTipDay: [:], today: "2026-06-20")
        XCTAssertEqual(ids, ["opus_heavy"])
    }

    func testTipsToNotifyRespectsCadence() {
        // opus_heavy cadence = 7 days; last fired 3 days ago → should NOT fire
        let insights = [PatternInsight(id: "opus_heavy", kind: .bad, title: "", detail: "")]
        let now = Calendar.current.date(byAdding: .day, value: -3, to: Date()) ?? Date()
        let lastDay = DayBucket.localDay(from: now)
        let ids = PatternDetector.tipsToNotify(
            insights: insights, lastTipDay: ["opus_heavy": lastDay], today: "2026-06-20")
        XCTAssertTrue(ids.isEmpty, "Should not re-fire within cadence window")
    }

    func testTipsToNotifyFiresAfterCadence() {
        // opus_heavy cadence = 7 days; last fired 8 days ago → should fire
        let insights = [PatternInsight(id: "opus_heavy", kind: .bad, title: "", detail: "")]
        let now = Date()
        let eightDaysAgo = DayBucket.day(daysAgo: 8, from: now)
        let ids = PatternDetector.tipsToNotify(
            insights: insights, lastTipDay: ["opus_heavy": eightDaysAgo], today: "2026-06-20", now: now)
        XCTAssertEqual(ids, ["opus_heavy"])
    }

    func testTipsToNotifyIgnoresGoodInsights() {
        let insights = [PatternInsight(id: "cache_high", kind: .good, title: "", detail: "")]
        let ids = PatternDetector.tipsToNotify(insights: insights, lastTipDay: [:], today: "2026-06-20")
        XCTAssertTrue(ids.isEmpty)
    }

    func testTipsToNotifyHandlesUnknownIdGracefully() {
        // An insight with an ID not in notificationCadence should be silently suppressed (MISS-2 guard).
        let insights = [PatternInsight(id: "future_pattern_xyz", kind: .bad, title: "", detail: "")]
        let ids = PatternDetector.tipsToNotify(insights: insights, lastTipDay: [:], today: "2026-06-20")
        XCTAssertTrue(ids.isEmpty, "Unknown cadence IDs should be suppressed, not crash or fire unbounded")
    }
}
