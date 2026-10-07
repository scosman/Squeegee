import Engine
import ServiceManagement

/// Implements `LoginItemPort` via `SMAppService.mainApp`.
///
/// `SMAppService` calls are synchronous XPC to the background task daemon and
/// can be slow, so they run on a detached task, never on the caller's actor.
public struct LiveLoginItem: LoginItemPort, Sendable {
    public init() {}

    public func isEnabled() async -> Bool {
        await Task.detached {
            SMAppService.mainApp.status == .enabled
        }.value
    }

    public func setEnabled(_ enabled: Bool) async throws {
        try await Task.detached {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }.value
    }
}
