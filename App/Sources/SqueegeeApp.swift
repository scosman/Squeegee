import AppKit
import SwiftUI

@main
struct SqueegeeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        // This scene exists solely to host the command overrides below.
        // The window is suppressed; AppDelegate manages the window directly
        // via NSWindow + NSHostingView (architecture section 6).
        Window("Squeegee", id: "unused") {
            EmptyView()
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // Override Cmd-Q: close the window instead of quitting.
            // Quitting is only via the menu bar "Quit Squeegee" item.
            CommandGroup(replacing: .appTermination) {
                Button("Close Window") {
                    NSApp.keyWindow?.performClose(nil)
                }
                .keyboardShortcut("q")
            }
        }
    }
}
