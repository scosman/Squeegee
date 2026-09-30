import AppShellUI
import Testing

@Suite("LaunchState")
@MainActor
struct LaunchStateTests {
    @Test func openWindowReturnsFalseWithNoCapturedAction() {
        let state = LaunchState()
        // No OpenWindowAction has been captured (the scene was suppressed).
        #expect(state.openWindow() == false)
    }
}
