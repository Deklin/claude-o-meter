import Foundation

/// On-disk locations under Application Support, plus the persisted snapshot shape.
enum Persistence {
    /// Days the history list / chart shows.
    static let displayDays = 30
    /// Days of aggregates retained on disk. One more than `displayDays` so month-to-date
    /// stays accurate on the last day of a 31-day month.
    static let retentionDays = 31
    /// Keep seen-ids a bit longer than the retention window to keep dedup stable near the edge.
    static let seenIDBufferDays = 7

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("ClaudeOMeter", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            NSLog("ClaudeOMeter: failed to create support directory: \(error)")
        }
        return dir
    }()

    static var stateURL: URL { supportDirectory.appendingPathComponent("state.json") }
    static var pricingURL: URL { supportDirectory.appendingPathComponent("pricing.json") }

    /// Everything we persist between launches.
    struct Snapshot: Codable, Sendable {
        var scanState: ScanState = ScanState()
        var aggregates: [String: DailyAggregate] = [:]   // day -> aggregate
        var settings: AlertSettings = AlertSettings()
        var lastAlertDay: [String: String] = [:]         // alert key -> day last fired
        var lastTipDay: [String: String] = [:]           // tip id -> day last notified
        /// The pricing table version used when the aggregates were last costed.
        /// 0 means unknown (pre-versioning). When this is less than the loaded
        /// pricing version, UsageStore.init() calls Aggregator.recost() to
        /// reapply current rates before the first display pass.
        var pricingVersion: Int = 0
    }

    static func loadSnapshot() -> Snapshot {
        guard let data = try? Data(contentsOf: stateURL) else { return Snapshot() }
        do {
            return try JSONDecoder().decode(Snapshot.self, from: data)
        } catch {
            NSLog("ClaudeOMeter: state.json decode failed (schema change or corruption?): \(error)")
            return Snapshot()
        }
    }

    static func save(_ snapshot: Snapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: stateURL, options: .atomic)
        } catch {
            NSLog("ClaudeOMeter: failed to save state: \(error)")
        }
    }

    /// Load user pricing.json, seeding or auto-upgrading from the bundled copy when needed.
    ///
    /// Auto-upgrade: if the bundled `version` field is higher than the installed one, the
    /// installed file is replaced with the bundled rates — preserving `discountPercent` so
    /// enterprise users don't lose their discount. Bump `PricingTable.default.version` (and
    /// the `version` field in Resources/pricing.json) whenever rates change.
    static func loadPricing() -> PricingTable {
        // Use Bundle.main.url(forResource:subdirectory:) so the lookup works from
        // Contents/Resources/ where the bundle is placed by build_app.sh (codesign requires
        // resources inside Contents/, not at the .app root where Bundle.module would look).
        let bundledURL = Bundle.main.url(forResource: "pricing", withExtension: "json",
                                         subdirectory: "ClaudeOMeter_ClaudeOMeter.bundle")
                      ?? Bundle.module.url(forResource: "pricing", withExtension: "json")

        let bundledData = bundledURL.flatMap { try? Data(contentsOf: $0) }
        let bundled = bundledData.flatMap { try? JSONDecoder().decode(PricingTable.self, from: $0) }
            ?? PricingTable.default

        let installedData = try? Data(contentsOf: pricingURL)
        let installed = installedData.flatMap { try? JSONDecoder().decode(PricingTable.self, from: $0) }

        if installed == nil {
            // First run: seed editable copy from bundled.
            if let data = bundledData ?? (try? JSONEncoder().encode(PricingTable.default)) {
                try? data.write(to: pricingURL, options: .atomic)
            }
            return bundled
        }

        // Auto-upgrade: bundled version is newer → replace rates, keep user's discount.
        if (bundled.version ?? 0) > (installed!.version ?? 0) {
            var upgraded = bundled
            upgraded.discountPercent = installed!.discountPercent
            if let data = try? JSONEncoder().encode(upgraded) {
                try? data.write(to: pricingURL, options: .atomic)
            }
            return upgraded
        }

        return installed!
    }
}
