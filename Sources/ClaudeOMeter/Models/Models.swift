import Foundation

/// Token counts for a single message or an aggregate, broken out by billing tier.
struct TokenUsage: Codable, Sendable, Equatable {
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite5m: Int = 0
    var cacheWrite1h: Int = 0

    var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h
        )
    }
}

/// A single deduplicated usage event extracted from a transcript line.
struct UsageRecord: Sendable, Equatable {
    let id: String          // message.id — global dedup key
    let day: String         // local calendar day, "yyyy-MM-dd"
    let model: String       // normalized family, e.g. "opus" / "sonnet" / "haiku"
    let rawModel: String    // original model string (for reference)
    let usage: TokenUsage
    let projectDir: String  // encoded directory name under ~/.claude/projects/
}

/// Per-model usage + computed cost within a single day.
struct ModelUsage: Codable, Sendable, Equatable {
    var model: String
    var rawModel: String = ""   // representative raw model string for exact-key pricing lookups
    var usage: TokenUsage = TokenUsage()
    var cost: Double = 0
}

/// Per-project cost + model breakdown for one day. Accumulated incrementally from scan records.
struct ProjectUsage: Codable, Sendable, Equatable {
    var cost: Double = 0
    var perModel: [String: Double] = [:]   // model family → cost
}

/// All usage for one local calendar day.
struct DailyAggregate: Codable, Sendable, Equatable {
    var day: String
    var perModel: [String: ModelUsage] = [:]
    /// Encoded project dir → usage for this day. Accumulated incrementally; not repriced on pricing changes.
    var perProject: [String: ProjectUsage] = [:]

    // Custom decoder so old state.json with perProject:[String:Double] degrades gracefully to [:].
    init(day: String) { self.day = day }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day      = try c.decode(String.self, forKey: .day)
        perModel = try c.decode([String: ModelUsage].self, forKey: .perModel)
        perProject = (try? c.decode([String: ProjectUsage].self, forKey: .perProject)) ?? [:]
    }
    private enum CodingKeys: String, CodingKey { case day, perModel, perProject }

    var totalCost: Double { perModel.values.reduce(0) { $0 + $1.cost } }
    var totalTokens: Int { perModel.values.reduce(0) { $0 + $1.usage.total } }

    var sortedModels: [ModelUsage] {
        perModel.values.sorted { $0.cost > $1.cost }
    }
}

/// User-configurable alert thresholds (USD). nil = disabled.
struct AlertSettings: Codable, Sendable, Equatable {
    var dailyThreshold: Double? = nil
    var monthlyThreshold: Double? = nil
    var tipsEnabled: Bool = true
    /// Percentage of the limit at which the "approaching" notification fires (1–99).
    var approachPercent: Int = 80
}
