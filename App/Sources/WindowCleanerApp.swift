import SwiftUI

@main
struct WindowCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        Window("WindowCleaner", id: "main") {
            Text("WindowCleaner")
        }
        .defaultLaunchBehavior(.suppressed)
        .commands { CommandGroup(replacing: .newItem) {} }
    }
}
