import XCTest
@testable import ClaudeCostBar

final class ClaudeCostBarTests: XCTestCase {

    // MARK: Model normalization

    func testNormalizationHandlesBedrockAndVersions() {
        XCTAssertEqual(ModelNormalizer.family(for: "claude-opus-4-8"), "opus")
        XCTAssertEqual(ModelNormalizer.family(for: "bedrock/us.anthropic.claude-opus-4-8"), "opus")
        XCTAssertEqual(ModelNormalizer.family(for: "claude-sonnet-4-5-20250929"), "sonnet")
        XCTAssertEqual(ModelNormalizer.family(for: "bedrock/us.anthropic.claude-sonnet-4-5-20250929-v1:0"), "sonnet")
        XCTAssertEqual(ModelNormalizer.family(for: "claude-haiku-4-5-20251001"), "haiku")
        XCTAssertEqual(ModelNormalizer.family(for: "<synthetic>"), "synthetic")
    }

    // MARK: Cost calculation

    func testCostUsesPerMillionPricing() {
        let pricing = PricingTable.default
        let usage = TokenUsage(input: 1_000_000, output: 0, cacheRead: 0, cacheWrite5m: 0, cacheWrite1h: 0)
        XCTAssertEqual(pricing.cost(of: usage, family: "opus", rawModel: "claude-opus-4-8"), 15.0, accuracy: 1e-9)
    }

    func testCostSumsAllTiers() {
        let pricing = PricingTable.default
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000, cacheRead: 1_000_000,
                               cacheWrite5m: 1_000_000, cacheWrite1h: 1_000_000)
        // opus: 15 + 75 + 1.5 + 18.75 + 30
        XCTAssertEqual(pricing.cost(of: usage, family: "opus", rawModel: "x"), 140.25, accuracy: 1e-9)
    }

    func testSyntheticCostsZero() {
        let pricing = PricingTable.default
        let usage = TokenUsage(input: 1_000_000, output: 1_000_000)
        XCTAssertEqual(pricing.cost(of: usage, family: "synthetic", rawModel: "<synthetic>"), 0)
    }

    // MARK: Dedup

    func testParseLineDedupsByMessageID() {
        var state = ScanState()
        let line = #"{"type":"assistant","timestamp":"2026-06-18T13:23:34.197Z","message":{"id":"msg_1","model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":925,"cache_read_input_tokens":0,"cache_creation_input_tokens":83074}}}"#
        let data = Data(line.utf8)

        let first = TranscriptScanner.parseLine(data, state: &state)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.usage.input, 10)
        XCTAssertEqual(first?.usage.output, 925)
        XCTAssertEqual(first?.model, "opus")

        // Same id again (e.g. copied into a resumed session) must be ignored.
        let second = TranscriptScanner.parseLine(data, state: &state)
        XCTAssertNil(second)
    }

    func testParseUsagePrefersCacheBreakdown() {
        let u: [String: Any] = [
            "input_tokens": 5,
            "output_tokens": 6,
            "cache_read_input_tokens": 7,
            "cache_creation_input_tokens": 100,
            "cache_creation": ["ephemeral_5m_input_tokens": 60, "ephemeral_1h_input_tokens": 40],
        ]
        let usage = TranscriptScanner.parseUsage(u)
        XCTAssertEqual(usage.cacheWrite5m, 60)
        XCTAssertEqual(usage.cacheWrite1h, 40)
        XCTAssertEqual(usage.cacheRead, 7)
    }

    func testParseUsageFallsBackWhenNoBreakdown() {
        let u: [String: Any] = ["cache_creation_input_tokens": 100]
        let usage = TranscriptScanner.parseUsage(u)
        XCTAssertEqual(usage.cacheWrite5m, 100)
        XCTAssertEqual(usage.cacheWrite1h, 0)
    }

    // MARK: Aggregation

    func testFoldAccumulatesPerModelAndDay() {
        var aggs: [String: DailyAggregate] = [:]
        let r1 = UsageRecord(id: "a", day: "2026-06-20", model: "opus", rawModel: "claude-opus-4-8",
                             usage: TokenUsage(input: 1_000_000))
        let r2 = UsageRecord(id: "b", day: "2026-06-20", model: "opus", rawModel: "claude-opus-4-8",
                             usage: TokenUsage(output: 1_000_000))
        Aggregator.fold(records: [r1, r2], into: &aggs, pricing: .default)

        let day = aggs["2026-06-20"]
        XCTAssertNotNil(day)
        XCTAssertEqual(day?.perModel["opus"]?.usage.input, 1_000_000)
        XCTAssertEqual(day?.perModel["opus"]?.usage.output, 1_000_000)
        // 15 (input) + 75 (output)
        XCTAssertEqual(day?.totalCost ?? 0, 90.0, accuracy: 1e-9)
    }

    func testPruneDropsOldDays() {
        var aggs: [String: DailyAggregate] = [
            "2026-05-01": DailyAggregate(day: "2026-05-01"),
            "2026-06-20": DailyAggregate(day: "2026-06-20"),
        ]
        Aggregator.prune(&aggs, onOrAfter: "2026-06-01")
        XCTAssertNil(aggs["2026-05-01"])
        XCTAssertNotNil(aggs["2026-06-20"])
    }

    // MARK: Day bucketing

    func testLocalDayParsesISO() {
        XCTAssertNotNil(DayBucket.localDay(fromISO: "2026-06-18T13:23:34.197Z"))
        XCTAssertNotNil(DayBucket.localDay(fromISO: "2026-06-18T13:23:34Z"))
    }

    // MARK: Alerts

    func testDailyAlertFiresOncePerDay() {
        let settings = AlertSettings(dailyThreshold: 10, monthlyThreshold: nil)
        let first = AlertManager.decide(
            todayCost: 12, monthCost: 12, settings: settings, lastAlertDay: [:], today: "2026-06-20")
        XCTAssertEqual(first.notifications.count, 1)
        XCTAssertEqual(first.lastAlertDay["daily"], "2026-06-20")

        // Already fired today -> no new notification.
        let second = AlertManager.decide(
            todayCost: 20, monthCost: 20, settings: settings, lastAlertDay: first.lastAlertDay, today: "2026-06-20")
        XCTAssertTrue(second.notifications.isEmpty)
        XCTAssertEqual(second.lastAlertDay["daily"], "2026-06-20")
    }

    func testNoAlertBelowThreshold() {
        let settings = AlertSettings(dailyThreshold: 50, monthlyThreshold: 100)
        let d = AlertManager.decide(
            todayCost: 10, monthCost: 30, settings: settings, lastAlertDay: [:], today: "2026-06-20")
        XCTAssertTrue(d.notifications.isEmpty)
    }

    func testScanStatePrunes() {
        var state = ScanState()
        state.cursors = ["/exists.jsonl": 10, "/gone.jsonl": 5]
        state.seenIDs = ["old": "2026-05-01", "new": "2026-06-20"]
        state.prune(existingPaths: ["/exists.jsonl"], retainSeenIDsOnOrAfter: "2026-06-01")
        XCTAssertEqual(Array(state.cursors.keys), ["/exists.jsonl"])
        XCTAssertNil(state.seenIDs["old"])
        XCTAssertNotNil(state.seenIDs["new"])
    }
}
