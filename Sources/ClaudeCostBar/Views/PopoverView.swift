import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore
    @State private var showSettings = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            HistoryChart(days: store.days, todayKey: store.todayKey)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(store.days, id: \.day) { day in
                        DayRow(day: day)
                        Divider().opacity(0.4)
                    }
                    if store.days.isEmpty {
                        Text("No usage recorded yet.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    }
                }
            }
            .frame(maxHeight: 260)

            Divider()
            if showSettings { settingsSection }
            footer
        }
        .padding(12)
        .frame(width: 340)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            ClaudeMark(size: 16, color: .accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text("Claude Code Cost").font(.system(size: 13, weight: .semibold))
                Text("Today").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.usd(store.todayCost))
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("30-day total: \(Fmt.usd(store.windowTotalCost))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                Text("This month: \(Fmt.usd(store.monthCost))")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            Button { showSettings.toggle() } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }.buttonStyle(.plain)
            Button { store.refresh() } label: {
                Image(systemName: "arrow.clockwise").font(.system(size: 12))
            }.buttonStyle(.plain)
            Button { NSApp.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 12))
            }.buttonStyle(.plain)
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alerts").font(.system(size: 12, weight: .semibold))
            ThresholdField(label: "Daily limit",
                           value: Binding(
                            get: { store.settings.dailyThreshold },
                            set: { store.settings.dailyThreshold = $0 }))
            ThresholdField(label: "Monthly limit",
                           value: Binding(
                            get: { store.settings.monthlyThreshold },
                            set: { store.settings.monthlyThreshold = $0 }))
            HStack {
                Button("Edit pricing.json") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: store.pricingFilePath))
                }.font(.system(size: 11))
                Button("Reload pricing") { store.reloadPricing() }
                    .font(.system(size: 11))
            }
            Text("Tip: thresholds are in USD; leave blank to disable. Prices are editable.")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
            Divider()
        }
    }
}

/// USD threshold input that maps blank -> nil.
private struct ThresholdField: View {
    let label: String
    @Binding var value: Double?
    @State private var text: String = ""

    var body: some View {
        HStack {
            Text(label).font(.system(size: 11)).frame(width: 90, alignment: .leading)
            Text("$").foregroundStyle(.secondary)
            TextField("none", text: $text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(width: 80)
                .onSubmit { commit() }
                .onChange(of: text) { _, _ in commit() }
        }
        .onAppear { text = value.map { String(format: "%g", $0) } ?? "" }
    }

    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        value = trimmed.isEmpty ? nil : Double(trimmed)
    }
}
