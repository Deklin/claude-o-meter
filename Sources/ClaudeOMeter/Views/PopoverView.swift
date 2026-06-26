import SwiftUI
import AppKit

struct PopoverView: View {
    @EnvironmentObject var store: UsageStore
    @State private var showSettings = false
    @State private var showAbout = false
    @State private var draftSettings = AlertSettings()
    @State private var chartMode: HistoryChart.Mode = .daily
    @State private var launchAtLogin = false
    @State private var loginItemNeedsApproval = false
    @State private var showTrendTooltip = false

    var body: some View {
        Group {
            if showAbout {
                aboutPanel
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            } else if showSettings {
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
        .animation(.easeInOut(duration: 0.18), value: showAbout)
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

            Text("Spend Alerts")
                .font(.system(size: 12, weight: .semibold))

            ThresholdField(label: "Daily alert",
                           value: Binding(
                            get: { draftSettings.dailyThreshold },
                            set: { draftSettings.dailyThreshold = $0 }))
            ThresholdField(label: "Monthly alert",
                           value: Binding(
                            get: { draftSettings.monthlyThreshold },
                            set: { draftSettings.monthlyThreshold = $0 }))

            HStack(spacing: 6) {
                Text("Warn at")
                    .font(.system(size: 11))
                    .frame(width: 90, alignment: .leading)
                Stepper(
                    value: Binding(
                        get: { draftSettings.approachPercent },
                        set: { draftSettings.approachPercent = $0 }
                    ),
                    in: 50...99, step: 5
                ) {
                    Text("\(draftSettings.approachPercent)%")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .frame(width: 36, alignment: .trailing)
                }
                .controlSize(.small)
            }

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

            Text("Fires when spend hits the alert (once/day or once/month) and again when approaching it. Leave blank to disable. USD.")
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

            Divider()

            Text("Diagnostics")
                .font(.system(size: 12, weight: .semibold))

            Button {
                AppLog.shared.copyToPasteboard()
            } label: {
                Label("Copy Diagnostic Logs", systemImage: "doc.on.clipboard")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 11))

            Text("Copies the in-memory log to your clipboard. Useful when filing a bug report.")
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

    // MARK: - About panel

    private var aboutPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("About")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button("Done") { showAbout = false }
                    .font(.system(size: 12))
            }

            Divider()

            // Identity
            HStack(spacing: 10) {
                ClaudeMark(size: 28, color: .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Claude-o-Meter")
                        .font(.system(size: 15, weight: .bold))
                    Text(appVersion == "dev" ? "Development build" : "Version \(appVersion)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Text("Real-time Claude Code spend tracker. Reads ~/.claude/projects/**/*.jsonl locally — nothing leaves your machine.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Updates
            VStack(alignment: .leading, spacing: 6) {
                Text("Updates")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Group {
                    if let update = store.availableUpdate {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Version \(update.version) available")
                                .font(.system(size: 11))
                            Spacer()
                            Button("Install") { confirmAndInstall(update: update.version) }
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                        .transition(.opacity)
                    } else if store.isCheckingForUpdate {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(360))
                                .animation(.linear(duration: 0.8).repeatForever(autoreverses: false),
                                           value: store.isCheckingForUpdate)
                            Text("Checking for updates…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        .transition(.opacity)
                    } else if store.updateCheckOutcome == .upToDate {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("You're up to date")
                                .font(.system(size: 11))
                            Spacer()
                            Button {
                                store.forceCheckForUpdate()
                            } label: {
                                Text("Check again")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .transition(.opacity)
                    } else {
                        Button {
                            store.forceCheckForUpdate()
                        } label: {
                            Label("Check for Updates", systemImage: "arrow.clockwise")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                        .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: store.isCheckingForUpdate)
                .animation(.easeInOut(duration: 0.2), value: store.updateCheckOutcome)
                .animation(.easeInOut(duration: 0.2), value: store.availableUpdate?.version)
            }

            Divider()

            // Links
            VStack(alignment: .leading, spacing: 6) {
                Text("Links")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Button {
                    NSWorkspace.shared.open(UpdateChecker.projectPageURL)
                } label: {
                    HStack(spacing: 5) {
                        GitHubMark().frame(width: 11, height: 11)
                        Text("Open on GitHub")
                    }
                }
                .font(.system(size: 11))

                Button {
                    NSWorkspace.shared.open(UpdateChecker.releasesPageURL)
                } label: {
                    Label("Releases & Changelog", systemImage: "tag")
                }
                .font(.system(size: 11))
            }

            Divider()

            // Diagnostics
            VStack(alignment: .leading, spacing: 6) {
                Text("Diagnostics")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Button {
                    AppLog.shared.copyToPasteboard()
                } label: {
                    Label("Copy Diagnostic Logs", systemImage: "doc.on.clipboard")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 11))

                Text("Includes app version and session activity — no personal data.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
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

    @ViewBuilder
    private var headerUpdateArea: some View {
        if store.isInstalling {
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini).scaleEffect(0.7)
                Text("Installing…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else if let update = store.availableUpdate {
            Button { confirmAndInstall(update: update.version) } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 9))
                    Text("v\(update.version)").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor))
            }
            .buttonStyle(.plain)
            .help("Update available — click to install")
            .transition(.opacity)
        } else if store.isCheckingForUpdate {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .light))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(360))
                    .animation(.linear(duration: 0.8).repeatForever(autoreverses: false),
                               value: store.isCheckingForUpdate)
                Text("Checking…")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .transition(.opacity)
        } else if store.updateCheckOutcome == .upToDate {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.green)
                Text("Up to date")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Button {
                    store.forceCheckForUpdate()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Check again")
            }
            .transition(.opacity)
        } else {
            HStack(spacing: 4) {
                Button { showAbout = true } label: {
                    Text(appVersion)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
                .help("About Claude-o-Meter")

                Button { store.forceCheckForUpdate() } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9, weight: .light))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Check for updates")
            }
            .transition(.opacity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ClaudeMark(size: 16, color: .accentColor)
                Text("Claude-o-Meter")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                headerUpdateArea
            }
            .animation(.easeInOut(duration: 0.2), value: store.isCheckingForUpdate)
            .animation(.easeInOut(duration: 0.2), value: store.updateCheckOutcome)
            .animation(.easeInOut(duration: 0.2), value: store.availableUpdate?.version)

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
                NSWorkspace.shared.open(UpdateChecker.projectPageURL)
            } label: {
                GitHubMark()
                    .frame(width: 13, height: 13)
            }
            .buttonStyle(.plain)
            .help("Open on GitHub")
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

// MARK: - GitHub icon (rendered via Canvas for crisp Retina output)

struct GitHubMark: View {
    var body: some View {
        Canvas { ctx, size in
            let s = size.width / 16
            var p = Path()
            // Simplified Invertocat silhouette — bold enough to read at 13 px
            p.move(to:    CGPoint(x: 8*s, y: 0))
            p.addCurve(to: CGPoint(x: 0, y: 8*s),
                       control1: CGPoint(x: 3.58*s, y: 0),
                       control2: CGPoint(x: 0, y: 3.58*s))
            p.addCurve(to: CGPoint(x: 5.47*s, y: 15.53*s),
                       control1: CGPoint(x: 0, y: 11.54*s),
                       control2: CGPoint(x: 2.29*s, y: 14.5*s))
            p.addCurve(to: CGPoint(x: 6*s, y: 15.24*s),
                       control1: CGPoint(x: 5.86*s, y: 15.57*s),
                       control2: CGPoint(x: 6*s, y: 15.42*s))
            p.addLine(to:  CGPoint(x: 6*s, y: 13.77*s))
            p.addCurve(to: CGPoint(x: 3.31*s, y: 12.74*s),
                       control1: CGPoint(x: 3.77*s, y: 14.19*s),
                       control2: CGPoint(x: 3.31*s, y: 12.74*s))
            p.addCurve(to: CGPoint(x: 2.42*s, y: 11.6*s),
                       control1: CGPoint(x: 2.95*s, y: 11.85*s),
                       control2: CGPoint(x: 2.42*s, y: 11.6*s))
            p.addCurve(to: CGPoint(x: 3.71*s, y: 11.94*s),
                       control1: CGPoint(x: 1.7*s, y: 11.11*s),
                       control2: CGPoint(x: 3.71*s, y: 11.94*s))
            p.addCurve(to: CGPoint(x: 6.03*s, y: 12.61*s),
                       control1: CGPoint(x: 4.42*s, y: 13.16*s),
                       control2: CGPoint(x: 5.57*s, y: 12.81*s))
            p.addCurve(to: CGPoint(x: 6.54*s, y: 11.54*s),
                       control1: CGPoint(x: 6.1*s, y: 12.09*s),
                       control2: CGPoint(x: 6.31*s, y: 11.74*s))
            p.addCurve(to: CGPoint(x: 2.9*s, y: 7.58*s),
                       control1: CGPoint(x: 4.76*s, y: 11.33*s),
                       control2: CGPoint(x: 2.9*s, y: 10.65*s))
            p.addCurve(to: CGPoint(x: 3.72*s, y: 5.43*s),
                       control1: CGPoint(x: 2.9*s, y: 6.71*s),
                       control2: CGPoint(x: 3.21*s, y: 5.99*s))
            p.addCurve(to: CGPoint(x: 3.8*s, y: 3.32*s),
                       control1: CGPoint(x: 3.64*s, y: 5.23*s),
                       control2: CGPoint(x: 3.36*s, y: 4.42*s))
            p.addCurve(to: CGPoint(x: 6.0*s, y: 4.14*s),
                       control1: CGPoint(x: 3.8*s, y: 3.32*s),
                       control2: CGPoint(x: 4.47*s, y: 3.1*s))
            p.addCurve(to: CGPoint(x: 8*s, y: 3.87*s),
                       control1: CGPoint(x: 6.67*s, y: 3.93*s),
                       control2: CGPoint(x: 7.33*s, y: 3.85*s))
            p.addCurve(to: CGPoint(x: 10*s, y: 4.14*s),
                       control1: CGPoint(x: 8.68*s, y: 3.87*s),
                       control2: CGPoint(x: 9.36*s, y: 3.96*s))
            p.addCurve(to: CGPoint(x: 12.2*s, y: 3.32*s),
                       control1: CGPoint(x: 11.53*s, y: 3.1*s),
                       control2: CGPoint(x: 12.2*s, y: 3.32*s))
            p.addCurve(to: CGPoint(x: 12.28*s, y: 5.43*s),
                       control1: CGPoint(x: 12.64*s, y: 4.42*s),
                       control2: CGPoint(x: 12.36*s, y: 5.23*s))
            p.addCurve(to: CGPoint(x: 13.1*s, y: 7.58*s),
                       control1: CGPoint(x: 12.79*s, y: 5.99*s),
                       control2: CGPoint(x: 13.1*s, y: 6.71*s))
            p.addCurve(to: CGPoint(x: 9.45*s, y: 11.53*s),
                       control1: CGPoint(x: 13.1*s, y: 10.65*s),
                       control2: CGPoint(x: 11.23*s, y: 11.32*s))
            p.addCurve(to: CGPoint(x: 10*s, y: 13.01*s),
                       control1: CGPoint(x: 9.74*s, y: 11.77*s),
                       control2: CGPoint(x: 10*s, y: 12.26*s))
            p.addLine(to:  CGPoint(x: 10*s, y: 15.24*s))
            p.addCurve(to: CGPoint(x: 10.53*s, y: 15.53*s),
                       control1: CGPoint(x: 10*s, y: 15.42*s),
                       control2: CGPoint(x: 10.13*s, y: 15.57*s))
            p.addCurve(to: CGPoint(x: 16*s, y: 8*s),
                       control1: CGPoint(x: 13.71*s, y: 14.5*s),
                       control2: CGPoint(x: 16*s, y: 11.54*s))
            p.addCurve(to: CGPoint(x: 8*s, y: 0),
                       control1: CGPoint(x: 16*s, y: 3.58*s),
                       control2: CGPoint(x: 12.42*s, y: 0))
            p.closeSubpath()
            ctx.fill(p, with: .foreground)
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
