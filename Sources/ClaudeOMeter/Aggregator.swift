import Foundation

/// Pure folding of usage records into per-day aggregates. Kept separate from the store
/// so it is trivially testable.
enum Aggregator {
    /// Fold new records into `aggregates`, recomputing per-model cost with `pricing`.
    static func fold(
        records: [UsageRecord],
        into aggregates: inout [String: DailyAggregate],
        pricing: PricingTable
    ) {
        for rec in records {
            var day = aggregates[rec.day] ?? DailyAggregate(day: rec.day)
            var model = day.perModel[rec.model] ?? ModelUsage(model: rec.model, rawModel: rec.rawModel)
            model.usage = model.usage + rec.usage
            model.rawModel = rec.rawModel   // always use the latest rawModel seen for this family/day
            model.cost = pricing.cost(of: model.usage, family: rec.model, rawModel: rec.rawModel)
            day.perModel[rec.model] = model
            aggregates[rec.day] = day
        }
    }

    /// Recompute all costs (used when pricing.json changes).
    static func recost(_ aggregates: inout [String: DailyAggregate], pricing: PricingTable) {
        for (day, agg) in aggregates {
            var newAgg = agg
            for (key, var model) in agg.perModel {
                model.cost = pricing.cost(of: model.usage, family: model.model, rawModel: model.rawModel)
                newAgg.perModel[key] = model
            }
            aggregates[day] = newAgg
        }
    }

    /// Drop aggregates older than the retention cutoff day (inclusive lower bound).
    static func prune(_ aggregates: inout [String: DailyAggregate], onOrAfter cutoffDay: String) {
        aggregates = aggregates.filter { $0.key >= cutoffDay }
    }
}
