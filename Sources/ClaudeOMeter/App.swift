import SwiftUI
import AppKit
import UserNotifications

@main
struct ClaudeOMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
        } label: {
            // Collapsed menu-bar content. MenuBarExtra labels reliably render only
            // SF Symbols + Text, so use a symbol here (the drawn mark lives in the popover).
            BundleImage(name: "claude-code-icon", size: 14, template: true, fallback: "sparkles")
            Text(store.todayCostString)
                .foregroundStyle(store.isOverDailyBudget ? Color.red : Color.primary)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Hides the Dock icon, sets up notifications. Periodic refresh lives in UsageStore.
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        UNUserNotificationCenter.current().delegate = self
        AlertManager.shared.requestAuthorization()
    }

    /// Without this, banners are suppressed while the app is "active" (e.g. popover open),
    /// which makes the test alert appear to do nothing. Force banner + sound + list.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }
}
