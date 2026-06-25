import Foundation
import Combine

/// Central observable state for the menu bar UI. Owns persistence, scanning, aggregation, alerts.
@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var days: [DailyAggregate] = []     // most-recent first, within retention
    @Published private(set) var lastRefresh: Date?
    @Published private(set) var isRefreshing = false
    @Published var settings: AlertSettings {
        didSet { snapshot.settings = settings; persist() }
    }

    private var snapshot: Persistence.Snapshot
    private var pricing: PricingTable
    private let scanner = TranscriptScanner()
    private var timer: Timer?

    init() {
        self.snapshot = Persistence.loadSnapshot()
        self.pricing = Persistence.loadPricing()
        self.settings = snapshot.settings
        rebuildPublished()
        startAutoRefresh()
    }

    /// Refresh now and then on a fixed interval so the menu-bar total stays current
    /// even while the popover is closed.
    func startAutoRefresh(interval: TimeInterval = 60) {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }

    // MARK: - Derived values

    var todayKey: String { DayBucket.localDay(from: Date()) }

    var todayCost: Double { snapshot.aggregates[todayKey]?.totalCost ?? 0 }

    var todayCostString: String { String(format: "$%.2f", todayCost) }

    var monthCost: Double {
        let prefix = String(todayKey.prefix(7))
        return snapshot.aggregates.values
            .filter { $0.day.hasPrefix(prefix) }
            .reduce(0) { $0 + $1.totalCost }
    }

    var windowTotalCost: Double { days.reduce(0) { $0 + $1.totalCost } }

    var pricingFilePath: String { Persistence.pricingURL.path }

    // MARK: - Refresh

    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        let currentState = snapshot.scanState

        Task {
            // Scan off the main actor; value types cross the boundary safely.
            let result = await Task.detached(priority: .utility) { [scanner] in
                scanner.scan(state: currentState)
            }.value

            self.apply(result)
            self.isRefreshing = false
            self.lastRefresh = Date()
        }
    }

    private func apply(_ result: TranscriptScanner.Result) {
        var state = result.state
        Aggregator.fold(records: result.records, into: &snapshot.aggregates, pricing: pricing)

        let cutoff = DayBucket.day(daysAgo: Persistence.retentionDays - 1)
        Aggregator.prune(&snapshot.aggregates, onOrAfter: cutoff)

        let seenCutoff = DayBucket.day(daysAgo: Persistence.retentionDays - 1 + Persistence.seenIDBufferDays)
        state.prune(existingPaths: result.existingPaths, retainSeenIDsOnOrAfter: seenCutoff)
        snapshot.scanState = state

        rebuildPublished()
        runAlerts()
        persist()
    }

    /// Reload pricing.json from disk and recompute all costs.
    func reloadPricing() {
        pricing = Persistence.loadPricing()
        Aggregator.recost(&snapshot.aggregates, pricing: pricing)
        rebuildPublished()
        persist()
    }

    private func runAlerts() {
        let fired = AlertManager.shared.evaluate(
            todayCost: todayCost,
            monthCost: monthCost,
            settings: settings,
            lastAlertDay: snapshot.lastAlertDay,
            today: todayKey
        )
        snapshot.lastAlertDay = fired
    }

    private func rebuildPublished() {
        let cutoff = DayBucket.day(daysAgo: Persistence.retentionDays - 1)
        days = snapshot.aggregates.values
            .filter { $0.day >= cutoff }
            .sorted { $0.day > $1.day }
    }

    private func persist() {
        Persistence.save(snapshot)
    }
}
