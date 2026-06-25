import SwiftUI
import Charts

/// 30-day daily cost bar chart. Today is highlighted.
struct HistoryChart: View {
    let days: [DailyAggregate]   // newest first
    let todayKey: String

    private var ordered: [DailyAggregate] { days.sorted { $0.day < $1.day } }

    var body: some View {
        Chart(ordered, id: \.day) { day in
            BarMark(
                x: .value("Day", day.day),
                y: .value("Cost", day.totalCost)
            )
            .foregroundStyle(day.day == todayKey ? Color.accentColor : Color.accentColor.opacity(0.45))
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let d = value.as(Double.self) {
                        Text(Fmt.usd(d)).font(.system(size: 8))
                    }
                }
            }
        }
        .frame(height: 80)
    }
}
