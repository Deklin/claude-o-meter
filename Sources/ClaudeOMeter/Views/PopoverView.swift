import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore
    @State private var showSettings = false
    @State private var draftSettings = AlertSettings()
    @State private var chartMode: HistoryChart.Mode = .daily
    @State private var launchAtLogin = false
    @State private var loginItemNeedsApproval = false
    @State private var showTrendTooltip = false

    var body: some View {
        Group {
            if showSettings {
                settingsPanel
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else {
                mainPanel
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
            }
        }
        .frame(width: 340)
        .animation(.easeInOut(duration: 0.18), value: showSettings)
    }

    // MARK: - Main panel

    private var mainPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            HStack(spacing: 8) {
                Picker("", selection: $chartMode) {
                    ForEach(HistoryChart.Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                if let trend = store.spendTrend {
                    spendTrendBadge(trend)
                        .onHover { showTrendTooltip = $0 }
                        .overlay(alignment: .topTrailing) {
                            if showTrendTooltip {
                                Text(trendTooltip(trend))
                                    .font(.system(size: 11))
                                    .multilineTextAlignment(.leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .frame(width: 220, alignment: .leading)
                                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(.secondary.opacity(0.2)))
                                    .offset(y: 30)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }
            .zIndex(1)
            HistoryChart(
                days: store.days,
                todayKey: store.todayKey,
                mode: chartMode,
                dailyLimit: store.settings.dailyThreshold,
                monthlyLimit: store.settings.monthlyThreshold
            )

            if !store.tips.isEmpty {
                tipsSection
            }

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

            if hasUnknown {
                Text("Unknown* models are priced with the fallback rate — add their exact key to pricing.json.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }

            Divider()
            mainFooter
        }
        .padding(12)
    }

    // MARK: - Settings panel

    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Settings")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            Divider()

            Text("Budgets & Alerts")
                .font(.system(size: 12, weight: .semibold))

            ThresholdField(label: "Daily limit",
                           value: Binding(
                            get: { draftSettings.dailyThreshold },
                            set: { draftSettings.dailyThreshold = $0 }))
            ThresholdField(label: "Monthly limit",
                           value: Binding(
                            get: { draftSettings.monthlyThreshold },
                            set: { draftSettings.monthlyThreshold = $0 }))

            Button {
                AlertManager.shared.sendTest()
            } label: {
                Label("Send test alert", systemImage: "bell.badge")
            }
            .font(.system(size: 11))

            Toggle(isOn: Binding(
                get: { draftSettings.tipsEnabled },
                set: { draftSettings.tipsEnabled = $0 }
            )) {
                Text("Show usage tips")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: $launchAtLogin) {
                Text("Start at login")
                    .font(.system(size: 11))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .onChange(of: launchAtLogin) { _, newValue in
                LoginItemManager.shared.setEnabled(newValue)
                loginItemNeedsApproval = LoginItemManager.shared.requiresApproval
            }

            if loginItemNeedsApproval {
                Button("Approve in System Settings →") {
                    LoginItemManager.shared.openSystemSettings()
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.orange)
            }

            Text("Alerts fire when you cross a limit (once/day, once/month). Tips notify at most weekly/monthly. USD; leave blank to disable.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            Divider()

            Text("Pricing")
                .font(.system(size: 12, weight: .semibold))

            HStack {
                Button("Edit pricing.json") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: store.pricingFilePath))
                }.font(.system(size: 11))
                Button("Reload pricing") { store.reloadPricing() }
                    .font(.system(size: 11))
            }
            Text("Set discountPercent in pricing.json for enterprise discounts, then Reload.")
                .font(.system(size: 11)).foregroundStyle(.secondary)

            Spacer()

            Divider()

            HStack {
                Button("Cancel") {
                    showSettings = false
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Save") {
                    store.settings = draftSettings
                    showSettings = false
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: [])
            }
            .font(.system(size: 12))
        }
        .padding(12)
    }

    // MARK: - Helpers

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(store.tips) { tip in
                HStack(alignment: .top, spacing: 6) {
                    Circle()
                        .fill(tip.kind == .bad ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tip.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(tip.kind == .bad ? Color.orange : Color.green)
                        Text(tip.detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tip.kind == .bad
                              ? Color.orange.opacity(0.08)
                              : Color.green.opacity(0.08))
                )
            }
        }
    }

    private func trendTooltip(_ trend: Double) -> String {
        let pct = String(format: "%.0f%%", abs(trend * 100))
        let direction = trend > 0 ? "up \(pct)" : "down \(pct)"
        return "Spend is \(direction) — avg of last 7 days vs prior 7 days (today excluded)"
    }

    private func spendTrendBadge(_ trend: Double) -> some View {
        let up = trend > 0
        let color: Color = up ? .orange : .green
        return HStack(spacing: 3) {
            Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                .font(.system(size: 9, weight: .bold))
            Text(String(format: "%.0f%%", abs(trend * 100)))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.12)))
    }

    private var hasUnknown: Bool {
        store.days.contains { $0.perModel.keys.contains("unknown") }
    }

    private static let relativeFmt: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private var updatedLabel: String {
        if store.isRefreshing { return "Updating…" }
        guard let t = store.lastRefresh else { return "Not yet updated" }
        return "Updated " + Self.relativeFmt.localizedString(for: t, relativeTo: Date())
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }

    private func confirmAndInstall(update: String) {
        let alert = NSAlert()
        alert.messageText = "Install Update?"
        alert.informativeText = "Claude-o-Meter \(update) is available. The app will quit, update, and relaunch automatically."
        alert.addButton(withTitle: "Install & Relaunch")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        store.installUpdate()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ClaudeMark(size: 16, color: .accentColor)
                Text("Claude-o-Meter")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if store.isInstalling {
                    HStack(spacing: 4) {
                        ProgressView().controlSize(.mini).scaleEffect(0.7)
                        Text("Installing…")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else if let update = store.availableUpdate {
                    Button { confirmAndInstall(update: update.version) } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 9))
                            Text("v\(update.version)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .help("Update available — click to install")
                } else {
                    Text(appVersion)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.5)
                    Text(Fmt.usd(store.todayCost))
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(store.isOverDailyBudget ? Color.red : Color.primary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 30)
                    .padding(.horizontal, 10)

                VStack(alignment: .center, spacing: 2) {
                    Text("MONTH")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.5)
                    Text(Fmt.usd(store.monthCost))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity)

                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 30)
                    .padding(.horizontal, 10)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("30 DAYS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .kerning(0.5)
                    Text(Fmt.usd(store.windowTotalCost))
                        .font(.system(size: 13, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
        }
    }

    private var mainFooter: some View {
        HStack {
            Text(updatedLabel)
                .font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button {
                draftSettings = store.settings
                launchAtLogin = LoginItemManager.shared.isEnabled
                loginItemNeedsApproval = LoginItemManager.shared.requiresApproval
                showSettings = true
            } label: {
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
