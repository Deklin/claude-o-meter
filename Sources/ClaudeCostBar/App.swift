import SwiftUI
import AppKit

@main
struct ClaudeCostBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environmentObject(store)
        } label: {
            // Collapsed menu-bar content: Claude mark + today's total.
            HStack(spacing: 4) {
                ClaudeMark(size: 13)
                Text(store.todayCostString)
            }
            .onAppear { store.refresh() }
        }
        .menuBarExtraStyle(.window)
    }
}

/// Hides the Dock icon and requests notification permission. Periodic refresh lives in UsageStore.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AlertManager.shared.requestAuthorization()
    }
}
