import Foundation
import AppKit
import UserNotifications

struct AlertNotification: Equatable, Sendable {
    let title: String
    let body: String
}

struct AlertDecision: Equatable, Sendable {
    var notifications: [AlertNotification]
    var lastAlertDay: [String: String]
}

/// Fires native notifications when daily / monthly spend crosses configured thresholds.
/// Each threshold fires at most once per local day (daily) or month (monthly).
@MainActor
final class AlertManager {
    static let shared = AlertManager()

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error { NSLog("ClaudeOMeter: notification auth error: \(error)") }
        }
    }

    /// Fire a sample notification so the user can confirm alerts work. Handles the case where
    /// permission was never granted (prompt) or was denied (open System Settings).
    func sendTest() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                Task { @MainActor in self.fireTest() }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    Task { @MainActor in granted ? self.fireTest() : self.openNotificationSettings() }
                }
            case .denied:
                Task { @MainActor in self.openNotificationSettings() }
            @unknown default:
                Task { @MainActor in self.fireTest() }
            }
        }
    }

    private func fireTest() {
        notify(title: "Test alert", body: "Claude-o-Meter notifications are working.")
    }

    /// Fire a usage-pattern tip notification.
    func sendTip(_ insight: PatternInsight) {
        notify(title: insight.title, body: insight.detail)
    }

    /// Open System Settings → Notifications so the user can enable alerts for the app.
    func openNotificationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Pure decision logic (no side effects) so it is testable without a bundle.
    nonisolated static func decide(
        todayCost: Double,
        monthCost: Double,
        settings: AlertSettings,
        lastAlertDay: [String: String],
        today: String
    ) -> AlertDecision {
        var fired = lastAlertDay
        var pending: [AlertNotification] = []

        if let limit = settings.dailyThreshold, todayCost >= limit, fired["daily"] != today {
            pending.append(AlertNotification(
                title: "Daily Claude spend over limit",
                body: "Today: \(Fmt.usd(todayCost)) (limit \(Fmt.usd(limit)))"))
            fired["daily"] = today
        }

        let monthKey = String(today.prefix(7)) // yyyy-MM
        if let limit = settings.monthlyThreshold, monthCost >= limit, fired["monthly"] != monthKey {
            pending.append(AlertNotification(
                title: "Monthly Claude spend over limit",
                body: "This month: \(Fmt.usd(monthCost)) (limit \(Fmt.usd(limit)))"))
            fired["monthly"] = monthKey
        }

        return AlertDecision(notifications: pending, lastAlertDay: fired)
    }

    /// Evaluate thresholds and dispatch any resulting notifications. Returns updated fired-map.
    func evaluate(
        todayCost: Double,
        monthCost: Double,
        settings: AlertSettings,
        lastAlertDay: [String: String],
        today: String
    ) -> [String: String] {
        let decision = Self.decide(
            todayCost: todayCost, monthCost: monthCost,
            settings: settings, lastAlertDay: lastAlertDay, today: today)
        for n in decision.notifications { notify(title: n.title, body: n.body) }
        return decision.lastAlertDay
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
