import AppShellUI
import SwiftUI

@main
struct WindowCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("WindowCleaner", id: "main") {
            MainWindowRootContent(launchState: delegate.launchState)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 540)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
