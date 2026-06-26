import ServiceManagement

final class LoginItemManager {
    static let shared = LoginItemManager()
    private init() {}

    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Status reflects reality; UI re-reads on next appear
        }
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
