import Engine
import ServiceManagement

/// Implements `LoginItemPort` via `SMAppService.mainApp`.
public struct LiveLoginItem: LoginItemPort, Sendable {
    public init() {}

    public func isEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
