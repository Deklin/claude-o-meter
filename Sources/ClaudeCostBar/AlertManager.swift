import Foundation
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
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
                body: String(format: "Today: $%.2f (limit $%.2f)", todayCost, limit)))
            fired["daily"] = today
        }

        let monthKey = String(today.prefix(7)) // yyyy-MM
        if let limit = settings.monthlyThreshold, monthCost >= limit, fired["monthly"] != monthKey {
            pending.append(AlertNotification(
                title: "Monthly Claude spend over limit",
                body: String(format: "This month: $%.2f (limit $%.2f)", monthCost, limit)))
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
