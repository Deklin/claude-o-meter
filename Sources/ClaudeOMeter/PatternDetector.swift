import Foundation

struct PatternInsight: Equatable, Sendable, Identifiable {
    enum Kind: Equatable, Sendable { case good, bad }
    let id: String
    let kind: Kind
    let title: String
    let detail: String

    // Minimum days between notifications for each bad-pattern tip.
    static let notificationCadence: [String: Int] = [
        "opus_heavy":     7,
        "cache_miss":     30,
        "spend_spike":    7,
        "context_bloat":  7,
        "burnrate":       7,
        "claudemd_bloat": 30,
    ]
}

/// Pure pattern-detection logic over the persisted daily aggregates.
enum PatternDetector {

    // MARK: - Detection

    static func detect(
        aggregates: [String: DailyAggregate],
        settings: AlertSettings = AlertSettings()
    ) -> [PatternInsight] {
        var insights: [PatternInsight] = []

        let last7  = window(aggregates, from: 1, count: 7)
        let prior7 = window(aggregates, from: 8, count: 7)

        let last7Cost = last7.reduce(0.0) { $0 + $1.totalCost }
        guard last7Cost >= 0.50 else { return [] }

        // --- Cache efficiency ---
        let allUsage = last7.flatMap { $0.perModel.values.map { $0.usage } }
        let totalInput     = allUsage.reduce(0) { $0 + $1.input }
        let totalCacheRead = allUsage.reduce(0) { $0 + $1.cacheRead }
        let cacheable = totalInput + totalCacheRead

        if cacheable > 50_000 {
            let hitRate = Double(totalCacheRead) / Double(cacheable)
            if hitRate < 0.15 {
                insights.append(PatternInsight(
                    id: "cache_miss", kind: .bad,
                    title: "Low cache hit rate (\(Int(hitRate * 100))%)",
                    detail: "Add a CLAUDE.md in your project root — it primes the cache on every session start, making subsequent turns up to 10× cheaper."
                ))
            } else if hitRate >= 0.50 {
                insights.append(PatternInsight(
                    id: "cache_high", kind: .good,
                    title: "Cache efficiency at \(Int(hitRate * 100))%",
                    detail: "Cached tokens cost ~10× less than fresh input — your workflow is well optimised."
                ))
            }
        }

        // --- Model selection ---
        let opusCost = last7.reduce(0.0) { $0 + ($1.perModel["opus"]?.cost ?? 0) }
        if last7Cost >= 1.0 {
            let opusFraction = opusCost / last7Cost
            if opusFraction > 0.60 {
                insights.append(PatternInsight(
                    id: "opus_heavy", kind: .bad,
                    title: "Opus is \(Int(opusFraction * 100))% of 7-day spend",
                    detail: "For everyday coding, Sonnet delivers comparable results at ~6× lower cost. Run `/model sonnet` to switch."
                ))
            } else if opusFraction < 0.40 && last7Cost >= 2.0 {
                insights.append(PatternInsight(
                    id: "model_efficient", kind: .good,
                    title: "Good model selection",
                    detail: "Using lighter models for routine tasks is keeping your costs down efficiently."
                ))
            }
        }

        // --- Spend trend ---
        let prior7Cost = prior7.reduce(0.0) { $0 + $1.totalCost }
        let prior7Avg  = prior7Cost / 7.0
        let last7Avg   = last7Cost / 7.0

        if prior7Avg >= 0.10 {
            if last7Avg >= prior7Avg * 1.60 {
                let pct = Int((last7Avg / prior7Avg - 1) * 100)
                insights.append(PatternInsight(
                    id: "spend_spike", kind: .bad,
                    title: "Spending up \(pct)% vs last week",
                    detail: "Daily average rose from \(Fmt.usd(prior7Avg)) to \(Fmt.usd(last7Avg)). Review model selection or prompt patterns."
                ))
            } else if last7Avg <= prior7Avg * 0.70 {
                let pct = Int((1 - last7Avg / prior7Avg) * 100)
                insights.append(PatternInsight(
                    id: "spend_down", kind: .good,
                    title: "Spending down \(pct)% vs last week",
                    detail: "Daily average dropped from \(Fmt.usd(prior7Avg)) to \(Fmt.usd(last7Avg)) — great efficiency improvement."
                ))
            }
        }

        // --- Context bloat: high input-to-output ratio ---
        let totalInput7  = last7.flatMap { $0.perModel.values }.reduce(0) { $0 + $1.usage.input }
        let totalOutput7 = last7.flatMap { $0.perModel.values }.reduce(0) { $0 + $1.usage.output }
        if totalInput7 >= 100_000, totalOutput7 > 0 {
            let ratio = Double(totalInput7) / Double(totalOutput7)
            if ratio >= 25 {
                insights.append(PatternInsight(
                    id: "context_bloat", kind: .bad,
                    title: "Context-to-output ratio is \(Int(ratio)):1",
                    detail: "You're sending \(Int(ratio))× more tokens than you receive — a sign of stale context carryover. Use /compact or start fresh sessions more often."
                ))
            }
        }

        // --- Month-end burn rate projection ---
        let today = DayBucket.day(daysAgo: 0)
        let todayParts = today.split(separator: "-")
        if todayParts.count == 3, let dayOfMonth = Int(todayParts[2]) {
            let monthPrefix = "\(todayParts[0])-\(todayParts[1])"
            let monthToDate = aggregates.values
                .filter { $0.day.hasPrefix(monthPrefix) }
                .reduce(0.0) { $0 + $1.totalCost }
            let daysInMonth = Calendar.current.range(of: .day, in: .month, for: Date())?.count ?? 30
            let daysRemaining = max(0, daysInMonth - dayOfMonth)
            let sorted7 = (1...7).map { aggregates[DayBucket.day(daysAgo: $0)]?.totalCost ?? 0 }.sorted()
            let medianDaily = sorted7[3]
            let projected = monthToDate + Double(daysRemaining) * medianDaily

            if medianDaily >= 0.20 && projected >= 10.0 {
                let detail: String
                if let limit = settings.monthlyThreshold {
                    let pct = Int((projected / limit) * 100)
                    detail = "At \(Fmt.usd(medianDaily))/day median, you're on pace for \(pct)% of your \(Fmt.usd(limit)) monthly budget."
                } else {
                    detail = "At \(Fmt.usd(medianDaily))/day median. Set a monthly budget in Settings to get an alert when you're close."
                }
                insights.append(PatternInsight(
                    id: "burnrate", kind: .bad,
                    title: "On pace for ~\(Fmt.usd(projected)) this month",
                    detail: detail
                ))
            }
        }

        // --- Global CLAUDE.md length (including @-imported files) ---
        if let (lineCount, hasImports) = claudeMdTotalLines(), lineCount > 200 {
            let subject = hasImports ? "Global CLAUDE.md + imports" : "Global CLAUDE.md"
            insights.append(PatternInsight(
                id: "claudemd_bloat", kind: .bad,
                title: "\(subject) has \(lineCount) lines",
                detail: "Your global CLAUDE.md loads on every API call across all projects. Trim to under 200 lines by removing rules Claude can infer from code."
            ))
        }

        return insights
    }

    // MARK: - Notification scheduling

    /// Returns the IDs of bad tips that should fire a notification today.
    static func tipsToNotify(
        insights: [PatternInsight],
        lastTipDay: [String: String],
        today: String
    ) -> [String] {
        insights
            .filter { $0.kind == .bad }
            .compactMap { insight -> String? in
                guard let cadence = PatternInsight.notificationCadence[insight.id] else { return nil }
                guard let lastStr = lastTipDay[insight.id] else { return insight.id }
                return daysSince(lastStr) >= cadence ? insight.id : nil
            }
    }

    // MARK: - Private helpers

    private static func window(_ aggs: [String: DailyAggregate], from start: Int, count: Int) -> [DailyAggregate] {
        (start..<(start + count)).compactMap { aggs[DayBucket.day(daysAgo: $0)] }
    }

    /// Count lines in ~/.claude/CLAUDE.md plus any @-imported files (Claude Code import syntax).
    /// Returns nil if the file doesn't exist.
    private static func claudeMdTotalLines() -> (count: Int, hasImports: Bool)? {
        let rootURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/CLAUDE.md")
        guard let content = try? String(contentsOf: rootURL, encoding: .utf8) else { return nil }

        let lines = content.components(separatedBy: .newlines)
        var total = lines.count
        var importCount = 0
        var seen: Set<String> = [rootURL.path]
        let dir = rootURL.deletingLastPathComponent()

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("@") else { continue }
            let ref = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
            guard !ref.isEmpty else { continue }

            let resolved: URL
            if ref.hasPrefix("/") {
                resolved = URL(fileURLWithPath: ref)
            } else if ref.hasPrefix("~") {
                resolved = URL(fileURLWithPath: (ref as NSString).expandingTildeInPath)
            } else {
                resolved = dir.appendingPathComponent(ref)
            }

            guard !seen.contains(resolved.path) else { continue }
            seen.insert(resolved.path)
            if let imported = try? String(contentsOf: resolved, encoding: .utf8) {
                total += imported.components(separatedBy: .newlines).count
                importCount += 1
            }
        }

        return (total, importCount > 0)
    }

    private static let dayFmt: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static func daysSince(_ dayString: String) -> Int {
        guard let past = dayFmt.date(from: dayString) else { return Int.max }
        return Calendar.current.dateComponents([.day], from: past, to: Date()).day ?? Int.max
    }
}
