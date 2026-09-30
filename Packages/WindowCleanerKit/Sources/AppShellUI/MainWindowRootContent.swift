import AppCore
import SwiftUI

/// The wrapper View that the Scene closure instantiates. It captures the
/// `OpenWindowAction` from the environment and stores it in `LaunchState`.
/// This decouples the AppDelegate from the SwiftUI lifecycle.
public struct MainWindowRootContent: View {
    @Environment(\.openWindow) private var openWindow
    let launchState: LaunchState

    public init(launchState: LaunchState) {
        self.launchState = launchState
    }

    public var body: some View {
        MainWindowRootView(launchState: launchState)
            .onAppear {
                launchState.openAction = openWindow
            }
    }
}
