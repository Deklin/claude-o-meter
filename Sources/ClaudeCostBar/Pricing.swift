import Foundation

/// Prices are USD per **one million** tokens.
struct ModelPrice: Codable, Sendable, Equatable {
    var input: Double
    var output: Double
    var cacheRead: Double
    var cacheWrite5m: Double
    var cacheWrite1h: Double
}

/// Pricing table keyed by normalized model *family* ("opus"/"sonnet"/"haiku"),
/// with optional exact-key overrides and a fallback for unknown models.
struct PricingTable: Codable, Sendable, Equatable {
    /// Keyed by family or exact normalized model name.
    var models: [String: ModelPrice]
    var fallback: ModelPrice?

    static let `default` = PricingTable(
        models: [
            // Anthropic standard tiers. Cache read ≈ 0.1× input, 5m write ≈ 1.25× input,
            // 1h write ≈ 2× input. Edit pricing.json to match your exact contract / Bedrock rates.
            "opus":   ModelPrice(input: 15,  output: 75, cacheRead: 1.50, cacheWrite5m: 18.75, cacheWrite1h: 30),
            "sonnet": ModelPrice(input: 3,   output: 15, cacheRead: 0.30, cacheWrite5m: 3.75,  cacheWrite1h: 6),
            "haiku":  ModelPrice(input: 1,   output: 5,  cacheRead: 0.10, cacheWrite5m: 1.25,  cacheWrite1h: 2),
        ],
        fallback: ModelPrice(input: 15, output: 75, cacheRead: 1.50, cacheWrite5m: 18.75, cacheWrite1h: 30)
    )

    func price(forFamily family: String, rawModel: String) -> ModelPrice? {
        if let exact = models[rawModel.lowercased()] { return exact }
        if let fam = models[family] { return fam }
        return fallback
    }

    /// Cost in USD for a usage bundle attributed to a model family.
    func cost(of usage: TokenUsage, family: String, rawModel: String) -> Double {
        guard family != ModelNormalizer.syntheticFamily,
              let p = price(forFamily: family, rawModel: rawModel) else { return 0 }
        let m = 1_000_000.0
        return Double(usage.input)        / m * p.input
             + Double(usage.output)       / m * p.output
             + Double(usage.cacheRead)    / m * p.cacheRead
             + Double(usage.cacheWrite5m) / m * p.cacheWrite5m
             + Double(usage.cacheWrite1h) / m * p.cacheWrite1h
    }
}

/// Maps raw model strings (incl. Bedrock/Vertex prefixes & version suffixes) to a stable family.
enum ModelNormalizer {
    static let syntheticFamily = "synthetic"

    static func family(for rawModel: String) -> String {
        let m = rawModel.lowercased()
        if m.contains("synthetic") { return syntheticFamily }
        if m.contains("opus") { return "opus" }
        if m.contains("sonnet") { return "sonnet" }
        if m.contains("haiku") { return "haiku" }
        return "unknown"
    }
}
