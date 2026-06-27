import SwiftUI

struct ProjectsPanel: View {
    @EnvironmentObject var store: UsageStore
    let onBack: () -> Void

    enum Range: String, CaseIterable, Identifiable {
        case day  = "24h"
        case week = "7d"
        case month = "30d"
        var id: String { rawValue }

        var dayCount: Int {
            switch self {
            case .day:   return 1
            case .week:  return 7
            case .month: return 30
            }
        }
    }

    @State private var range: Range = .month

    private var window: [DailyAggregate] {
        Array(store.days.prefix(range.dayCount))
    }

    private var projectTotals: [(dir: String, name: String, cost: Double)] {
        var totals: [String: Double] = [:]
        for agg in window {
            for (dir, cost) in agg.perProject {
                totals[dir, default: 0] += cost
            }
        }
        return totals
            .map { (dir: $0.key, name: TranscriptScanner.projectDisplayName(from: $0.key), cost: $0.value) }
            .filter { $0.cost > 0 }
            .sorted { $0.cost > $1.cost }
    }

    private var windowTotal: Double {
        projectTotals.reduce(0) { $0 + $1.cost }
    }

    private var dateRangeLabel: String {
        let days = window.compactMap { $0.day }.sorted()
        guard let first = days.first, let last = days.last else { return "" }
        if range == .day { return Fmt.dayLabel(last) }
        return "\(Fmt.shortDate(first)) – \(Fmt.shortDate(last))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            summary
            Divider().opacity(0.5).padding(.vertical, 8)
            content
            Spacer()
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            Text("Projects")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Picker("", selection: $range) {
                ForEach(Range.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
        }
        .padding(.bottom, 10)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.usd(windowTotal))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                Text(dateRangeLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !projectTotals.isEmpty {
                Text("\(projectTotals.count) project\(projectTotals.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var content: some View {
        Group {
            if projectTotals.isEmpty {
                Text("No project data for this period.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(projectTotals, id: \.dir) { project in
                            ProjectRow(project: project, totalCost: windowTotal)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }
}

private struct ProjectRow: View {
    let project: (dir: String, name: String, cost: Double)
    let totalCost: Double

    private var fraction: Double {
        totalCost > 0 ? project.cost / totalCost : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(project.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(Fmt.usd(project.cost))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.07))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.accentColor.opacity(0.7))
                        .frame(width: geo.size.width * fraction, height: 4)
                }
            }
            .frame(height: 4)
        }
        .padding(.vertical, 7)
    }
}
