import Foundation

/// On-disk locations under Application Support, plus the persisted snapshot shape.
enum Persistence {
    static let retentionDays = 30
    /// Keep seen-ids a bit longer than the visible window to keep dedup stable near the edge.
    static let seenIDBufferDays = 7

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("ClaudeCostBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var stateURL: URL { supportDirectory.appendingPathComponent("state.json") }
    static var pricingURL: URL { supportDirectory.appendingPathComponent("pricing.json") }

    /// Everything we persist between launches.
    struct Snapshot: Codable, Sendable {
        var scanState: ScanState = ScanState()
        var aggregates: [String: DailyAggregate] = [:]   // day -> aggregate
        var settings: AlertSettings = AlertSettings()
        var lastAlertDay: [String: String] = [:]         // alert key -> day last fired
    }

    static func loadSnapshot() -> Snapshot {
        guard let data = try? Data(contentsOf: stateURL),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        else { return Snapshot() }
        return snap
    }

    static func save(_ snapshot: Snapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: stateURL, options: .atomic)
    }

    /// Load user pricing.json, seeding it from the bundled default on first run.
    static func loadPricing() -> PricingTable {
        if let data = try? Data(contentsOf: pricingURL),
           let table = try? JSONDecoder().decode(PricingTable.self, from: data) {
            return table
        }
        // Seed editable copy from bundled resource (or built-in default).
        if let bundled = Bundle.module.url(forResource: "pricing", withExtension: "json"),
           let data = try? Data(contentsOf: bundled) {
            try? data.write(to: pricingURL, options: .atomic)
            if let table = try? JSONDecoder().decode(PricingTable.self, from: data) { return table }
        }
        if let data = try? JSONEncoder().encode(PricingTable.default) {
            try? data.write(to: pricingURL, options: .atomic)
        }
        return .default
    }
}
