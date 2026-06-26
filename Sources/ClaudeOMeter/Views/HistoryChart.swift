import SwiftUI
import Charts

struct HistoryChart: View {
    enum Mode: String, CaseIterable, Identifiable {
        case daily = "Daily"
        case cumulative = "Cumulative"
        var id: String { rawValue }
    }

    let days: [DailyAggregate]   // newest first
    let todayKey: String
    let mode: Mode
    let dailyLimit: Double?
    let monthlyLimit: Double?

    @State private var selectedDay: String?
    @State private var hoverX: CGFloat?

    // MARK: - Data shapes

    private struct StackPoint: Identifiable {
        let day: String
        let model: String
        let cost: Double
        var id: String { "\(day)-\(model)" }
    }

    private struct CumulativePoint: Identifiable {
        let day: String
        let value: Double
        var id: String { day }
    }

    // MARK: - Data

    /// Full 30-day window oldest→newest, gap-filled with empty aggregates.
    private var ordered: [DailyAggregate] {
        let byDay = Dictionary(days.map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        return (0..<Persistence.displayDays).reversed().map { offset in
            let key = DayBucket.day(daysAgo: offset)
            return byDay[key] ?? DailyAggregate(day: key)
        }
    }

    /// Superset of all models with any spend in the 30-day window, in stable display order.
    private var allKnownModels: [String] {
        let all = Set(ordered.flatMap { agg in
            agg.perModel.values.filter { $0.cost > 0 }.map { $0.model }
        })
        let preferred = ["haiku", "sonnet", "opus", "synthetic", "unknown"]
        let inOrder = preferred.filter { all.contains($0) }
        let rest = all.subtracting(preferred).sorted()
        return inOrder + rest
    }

    private var activeModels: [String] { allKnownModels }

    private var stackedPoints: [StackPoint] {
        let models = allKnownModels
        guard !models.isEmpty else { return [] }
        // Full cross-product: every day × every model.
        // Epsilon floor (0.0001) ensures Swift Charts registers every day in the
        // categorical domain — zero-height bars are dropped from domain inference.
        // chartYScale pins the y-axis so the epsilon is visually undetectable.
        return ordered.flatMap { agg in
            models.map { model in
                let cost = agg.perModel[model]?.cost ?? 0
                return StackPoint(day: agg.day, model: model, cost: max(cost, 0.0001))
            }
        }
    }

    private var cumulativePoints: [CumulativePoint] {
        let monthPrefix = String(todayKey.prefix(7))
        var running = 0.0
        return ordered.map { d in
            if d.day.hasPrefix(monthPrefix) { running += d.totalCost }
            return CumulativePoint(day: d.day, value: running)
        }
    }

    /// Y-axis ceiling: max value for the current mode (or limit if higher), with 10% headroom.
    /// Pinning this via chartYScale makes the 0.0001 epsilon visually invisible.
    private var yMax: Double {
        let dataMax: Double
        if mode == .cumulative {
            dataMax = cumulativePoints.map { $0.value }.max() ?? 1.0
        } else {
            dataMax = ordered.map { $0.totalCost }.max() ?? 1.0
        }
        let limitMax = activeLimit ?? 0
        return max(dataMax, limitMax) * 1.1
    }

    private var labelDays: [String] {
        let keys = ordered.map { $0.day }
        guard keys.count > 1 else { return keys }
        let step = max(1, keys.count / 4)
        var picks = Array(stride(from: 0, to: keys.count, by: step)).map { keys[$0] }
        if let last = keys.last, picks.last != last { picks.append(last) }
        return picks
    }

    private var activeLimit: Double? { mode == .daily ? dailyLimit : monthlyLimit }

    // MARK: - Lookup helpers

    private func totalCost(for day: String) -> Double {
        ordered.first { $0.day == day }?.totalCost ?? 0
    }

    private func displayValue(for day: String) -> Double {
        if mode == .daily { return totalCost(for: day) }
        return cumulativePoints.first { $0.day == day }?.value ?? 0
    }

    /// All known models with their real cost for the day (including zero-cost ones).
    private func modelBreakdown(for day: String) -> [(model: String, cost: Double)] {
        let models = allKnownModels
        guard !models.isEmpty else { return [] }
        let agg = ordered.first(where: { $0.day == day })
        return models.map { model in
            (model, agg?.perModel[model]?.cost ?? 0)
        }
    }

    private func tooltipView(for day: String) -> some View {
        let breakdown = mode == .daily ? modelBreakdown(for: day) : []
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(Fmt.dayLabel(day))
                    .font(.system(size: 11, weight: .semibold))
                Spacer(minLength: 8)
                Text(Fmt.usd(displayValue(for: day)))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            if !breakdown.isEmpty {
                Divider().opacity(0.5)
                ForEach(breakdown, id: \.model) { item in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ModelColor.color(for: item.model))
                            .frame(width: 6, height: 6)
                        Text(item.model)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 8)
                        Text(Fmt.usd(item.cost))
                            .font(.system(size: 10, weight: .medium))
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.secondary.opacity(0.2)))
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Chart {
                if mode == .daily {
                    ForEach(stackedPoints) { p in
                        BarMark(x: .value("Day", p.day), y: .value("Cost", p.cost))
                            .foregroundStyle(by: .value("Model", p.model))
                            .opacity(selectedDay == nil || selectedDay == p.day ? 1.0 : 0.3)
                    }
                } else {
                    ForEach(cumulativePoints) { p in
                        AreaMark(x: .value("Day", p.day), y: .value("Total", p.value))
                            .foregroundStyle(Color.accentColor.opacity(0.18))
                        LineMark(x: .value("Day", p.day), y: .value("Total", p.value))
                            .foregroundStyle(Color.accentColor)
                            .interpolationMethod(.monotone)
                    }
                }

                if let limit = activeLimit, limit > 0 {
                    RuleMark(y: .value("Limit", limit))
                        .foregroundStyle(Color.red.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing, spacing: 2) {
                            Text("\(mode == .daily ? "Daily" : "Monthly") alert · \(Fmt.usd(limit))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.red.opacity(0.9)))
                        }
                }

                if let d = selectedDay {
                    RuleMark(x: .value("Day", d))
                        .foregroundStyle(.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                }
            }
            .chartForegroundStyleScale(
                domain: activeModels,
                range: activeModels.map { ModelColor.color(for: $0) }
            )
            .chartXScale(domain: ordered.map { $0.day })
            .chartYScale(domain: 0...yMax)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: labelDays) { value in
                    if let s = value.as(String.self) {
                        AxisValueLabel { Text(shortLabel(s)).font(.system(size: 11)) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let d = value.as(Double.self) {
                            Text(Fmt.usd(d)).font(.system(size: 11))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    if let plotFrame = proxy.plotFrame {
                        let rect = geo[plotFrame]
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .onContinuousHover { phase in
                                switch phase {
                                case .active(let p):
                                    if let day = proxy.value(atX: p.x - rect.minX, as: String.self),
                                       day != selectedDay {
                                        selectedDay = day
                                        hoverX = p.x
                                    }
                                case .ended:
                                    selectedDay = nil
                                    hoverX = nil
                                }
                            }
                            .gesture(
                                SpatialTapGesture().onEnded { v in
                                    selectedDay = proxy.value(atX: v.location.x - rect.minX, as: String.self)
                                    hoverX = v.location.x
                                }
                            )
                    }
                }
            }
            .overlay {
                if let d = selectedDay, let hx = hoverX {
                    GeometryReader { geo in
                        let tipW: CGFloat = 180
                        let clampedX = max(tipW / 2 + 4, min(hx, geo.size.width - tipW / 2 - 4))
                        tooltipView(for: d)
                            .frame(width: tipW)
                            .position(x: clampedX, y: 55)
                            .allowsHitTesting(false)
                    }
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 115)

            // Compact model legend (daily mode only)
            if mode == .daily, !activeModels.isEmpty {
                HStack(spacing: 10) {
                    ForEach(activeModels, id: \.self) { model in
                        HStack(spacing: 3) {
                            Circle()
                                .fill(ModelColor.color(for: model))
                                .frame(width: 6, height: 6)
                            Text(model == "unknown" ? "unknown*" : model)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
    }

    private func shortLabel(_ day: String) -> String {
        let parts = day.split(separator: "-")
        guard parts.count == 3 else { return day }
        return "\(Int(parts[1]) ?? 0)/\(Int(parts[2]) ?? 0)"
    }
}
