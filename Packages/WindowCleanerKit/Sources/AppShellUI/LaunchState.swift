import AppCore
import SwiftUI

/// Captures the `OpenWindowAction` from the SwiftUI environment so the
/// AppDelegate can open the main window from outside a `View` body.
///
/// This is the Biscotti workaround: Scene closures do not reliably track
/// `@Observable` objects, so we use a wrapper View that stores the
/// `OpenWindowAction` and passes it into `LaunchState` during its body
/// evaluation. The AppDelegate then calls `openWindow()` on LaunchState.
@MainActor
@Observable
public final class LaunchState {
    public var core: AppCore?

    /// The open-window action captured from the SwiftUI environment.
    var openAction: OpenWindowAction?

    public init() {}

    /// Opens the main window via the captured SwiftUI action.
    public func openWindow() {
        openAction?(id: "main")
    }
}
