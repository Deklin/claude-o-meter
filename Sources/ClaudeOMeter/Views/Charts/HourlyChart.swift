import SwiftUI
import Charts

/// Bar chart showing per-hour spend for a single day, stacked by model family.
struct HourlyChart: View {
    let slices: [HourlySlice]
    var chartHeight: CGFloat = 70

    @State private var selectedHour: Int?
    @State private var hoverX: CGFloat?

    private struct StackPoint: Identifiable {
        let hour: Int
        let model: String
        let cost: Double
        var id: String { "\(hour)-\(model)" }
    }

    private var allModels: [String] {
        let all = Set(slices.flatMap { $0.perModel.keys.filter { $0 != "" } })
        let preferred = ["haiku", "sonnet", "opus", "synthetic", "unknown"]
        return preferred.filter { all.contains($0) } + all.subtracting(preferred).sorted()
    }

    private var stackedPoints: [StackPoint] {
        let models = allModels
        guard !models.isEmpty else { return [] }
        return slices.flatMap { s in
            models.map { model in
                StackPoint(hour: s.hour, model: model, cost: max(s.perModel[model] ?? 0, 0))
            }
        }
    }

    private var totalCost: Double { slices.reduce(0) { $0 + $1.cost } }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topLeading) {
                chart
                if let h = selectedHour, let slice = slices.first(where: { $0.hour == h }), slice.cost > 0 {
                    tooltip(slice: slice)
                }
            }
            axisLabels
        }
    }

    private var chart: some View {
        Chart(stackedPoints) { pt in
            BarMark(
                x: .value("Hour", pt.hour),
                y: .value("Cost", pt.cost),
                width: .ratio(0.85)
            )
            .foregroundStyle(by: .value("Model", pt.model))
            .cornerRadius(2)
        }
        .chartForegroundStyleScale(
            domain: allModels,
            range: allModels.map { ModelColor.color(for: $0) }
        )
        .chartLegend(.hidden)
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXScale(domain: -0.5...23.5)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onContinuousHover { phase in
                        switch phase {
                        case .active(let loc):
                            hoverX = loc.x
                            if let hour: Int = proxy.value(atX: loc.x - geo.frame(in: .local).minX) {
                                selectedHour = max(0, min(23, hour))
                            }
                        case .ended:
                            hoverX = nil
                            selectedHour = nil
                        }
                    }
            }
        }
        .frame(height: chartHeight)
    }

    private var axisLabels: some View {
        HStack(spacing: 0) {
            ForEach([0, 6, 12, 18, 23], id: \.self) { h in
                if h == 0 {
                    Text(hourLabel(h))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else if h == 23 {
                    Spacer()
                    Text(hourLabel(h))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                } else {
                    Spacer()
                    Text(hourLabel(h))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            }
        }
    }

    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "12a" : h < 12 ? "\(h)a" : h == 12 ? "12p" : "\(h - 12)p"
    }

    private func tooltip(slice: HourlySlice) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hourLabel(slice.hour))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(Fmt.usd(slice.cost))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
            ForEach(allModels.filter { (slice.perModel[$0] ?? 0) > 0 }, id: \.self) { m in
                HStack(spacing: 4) {
                    Circle().fill(ModelColor.color(for: m)).frame(width: 5, height: 5)
                    Text(m.capitalized).font(.system(size: 9)).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Text(Fmt.usd(slice.perModel[m] ?? 0))
                        .font(.system(size: 9)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.secondary.opacity(0.2)))
        .fixedSize()
        .allowsHitTesting(false)
    }
}
