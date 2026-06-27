import SwiftUI

// MARK: - Supporting types

fileprivate struct ProjectAggregate: Identifiable {
    let dir: String
    let name: String
    let cost: Double
    let perModel: [ModelEntry]
    var id: String { dir }

    struct ModelEntry: Identifiable {
        let model: String
        let cost: Double
        var id: String { model }
    }
}

// MARK: - Panel

struct ProjectsPanel: View {
    @EnvironmentObject var store: UsageStore
    let onBack: () -> Void

    enum Period: String, CaseIterable, Identifiable {
        case today = "Today"
        case week  = "7d"
        case month = "30d"
        var id: String { rawValue }

        var dayCount: Int {
            switch self {
            case .today: return 1
            case .week:  return 7
            case .month: return 30
            }
        }
    }

    @State private var period: Period = .month

    // MARK: - Computed data

    private var window: [DailyAggregate] {
        Array(store.days.prefix(period.dayCount))
    }

    private var projects: [ProjectAggregate] {
        var costTotals:  [String: Double] = [:]
        var modelTotals: [String: [String: Double]] = [:]

        for agg in window {
            for (dir, pu) in agg.perProject {
                costTotals[dir, default: 0] += pu.cost
                for (model, cost) in pu.perModel {
                    modelTotals[dir, default: [:]][model, default: 0] += cost
                }
            }
        }

        return costTotals
            .filter { $0.value > 0 }
            .sorted { $0.value > $1.value }
            .map { dir, cost in
                let models = (modelTotals[dir] ?? [:])
                    .map { ProjectAggregate.ModelEntry(model: $0.key, cost: $0.value) }
                    .filter { $0.cost > 0 }
                    .sorted { $0.cost > $1.cost }

                return ProjectAggregate(
                    dir: dir,
                    name: TranscriptScanner.projectDisplayName(from: dir),
                    cost: cost,
                    perModel: models
                )
            }
    }

    private var windowTotal: Double { projects.reduce(0) { $0 + $1.cost } }

    private var dateRangeLabel: String {
        let days = window.map(\.day).sorted()
        guard let first = days.first, let last = days.last else { return "" }
        if period == .today { return Fmt.dayLabel(last) }
        return "\(Fmt.shortDate(first)) – \(Fmt.shortDate(last))"
    }

    // MARK: - Body

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
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Projects")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
            Spacer()
            Picker("", selection: $period) {
                ForEach(Period.allCases) { Text($0.rawValue).tag($0) }
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
            if !projects.isEmpty {
                Text("\(projects.count) project\(projects.count == 1 ? "" : "s")")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var content: some View {
        Group {
            if projects.isEmpty {
                Text("No project data for this period.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(projects) { project in
                            ProjectRow(project: project, totalCost: windowTotal)
                            Divider().opacity(0.4)
                        }
                    }
                }
                .frame(maxHeight: 310)
            }
        }
    }
}

// MARK: - Row

private struct ProjectRow: View {
    let project: ProjectAggregate
    let totalCost: Double

    @State private var expanded = false

    private var fraction: Double {
        totalCost > 0 ? min(project.cost / totalCost, 1) : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.14)) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 10)
                        Text(project.name)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(Fmt.usd(project.cost))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.07))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.accentColor.opacity(0.6))
                                .frame(width: geo.size.width * fraction, height: 3)
                        }
                    }
                    .frame(height: 3)
                    .padding(.leading, 14)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 7)

            if expanded && !project.perModel.isEmpty {
                modelSection
                    .padding(.leading, 14)
                    .padding(.bottom, 8)
            }
        }
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MODELS")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .kerning(0.3)

            ForEach(project.perModel) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(ModelColor.color(for: item.model))
                        .frame(width: 6, height: 6)
                    Text(item.model.capitalized)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 52, alignment: .leading)
                    GeometryReader { geo in
                        let frac = project.cost > 0 ? min(item.cost / project.cost, 1) : 0
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.primary.opacity(0.07))
                                .frame(height: 3)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(ModelColor.color(for: item.model).opacity(0.7))
                                .frame(width: geo.size.width * frac, height: 3)
                        }
                    }
                    .frame(height: 3)
                    Text(Fmt.usd(item.cost))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: 72, alignment: .trailing)
                }
            }
        }
    }
}
