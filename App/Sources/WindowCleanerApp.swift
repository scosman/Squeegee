import AppShellUI
import SwiftUI

@main
struct WindowCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // The scene is suppressed: the main window is managed by AppDelegate
        // via NSWindow + NSHostingView (see showMainWindowDirectly). This
        // avoids a chicken-and-egg with OpenWindowAction — the suppressed
        // scene never instantiates its content, so the environment action
        // is never captured. The scene declaration is kept as a dormant
        // fallback in case the action is captured through another path.
        Window("WindowCleaner", id: "main") {
            MainWindowRootContent(launchState: delegate.launchState)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 540)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
