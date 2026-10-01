# Background / Menu Bar App Setup — Deep Dive

## Menu Bar Only App with SwiftUI

### `MenuBarExtra` Scene

SwiftUI provides `MenuBarExtra` (macOS 13+) as a first-class scene type for menu bar apps. It replaces the older `NSStatusItem` approach with a declarative API.

```swift
@main
struct SqueegeeApp: App {
    var body: some Scene {
        MenuBarExtra("Squeegee", systemImage: "xmark.circle") {
            ContentView()
                .frame(width: 350, height: 500)
        }
        .menuBarExtraStyle(.window)
    }
}
```

**Two styles available:**
- `.menu` (default) — Renders as a standard dropdown menu. Works well for simple button lists. Does not support sliders, toggles, or complex views reliably.
- `.window` — Renders as a floating window attached to the menu bar icon. Supports any SwiftUI view. Best for Squeegee since it needs to show lists of windows, timers, and settings controls.

Source: [Nil Coalescing — Build a macOS menu bar utility in SwiftUI (Feb 2025)](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)

### Hiding the Dock Icon (`LSUIElement`)

Set `LSUIElement` to `YES` in Info.plist (or the equivalent "Application is agent (UIElement)" key). This:

- Hides the app from the Dock
- Hides the app from the Cmd-Tab app switcher
- Removes the app's own menu bar (File, Edit, etc.)
- The app runs purely as a background agent with only the `MenuBarExtra` icon visible

```xml
<!-- Info.plist -->
<key>LSUIElement</key>
<true/>
```

**Important consequence:** With no Dock icon, the user cannot right-click > Quit from the Dock. The app **must** provide its own Quit mechanism — typically a "Quit Squeegee" button at the bottom of the `MenuBarExtra` panel.

```swift
Button("Quit Squeegee") {
    NSApp.terminate(nil)
}
```

Source: [Sarunw — Create a Mac menu bar app with MenuBarExtra (Jun 2022)](https://sarunw.com/posts/swiftui-menu-bar-app/), [Nil Coalescing — Build a macOS menu bar utility in SwiftUI (Feb 2025)](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)

## Launch at Login with `SMAppService`

### The Modern API

`SMAppService` (macOS 13.0+, ServiceManagement framework) replaces the deprecated `SMLoginItemSetEnabled`. It registers the app as a login item so it starts automatically when the user logs in.

```swift
import ServiceManagement

// Register
try SMAppService.mainApp.register()

// Unregister
try SMAppService.mainApp.unregister()

// Check status
let status = SMAppService.mainApp.status  // .enabled, .notRegistered, .requiresApproval, .notFound
```

### UI Implementation

```swift
struct SettingsView: View {
    @State private var launchAtLogin = false

    var body: some View {
        Toggle("Launch at login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { _, newValue in
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Failed to update login item: \(error)")
                    launchAtLogin = !newValue  // revert toggle on failure
                }
            }
            .onAppear {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
    }
}
```

### Key Requirements

- **Default must be off.** Apple's App Review Guidelines require that apps not auto-launch without user consent. The toggle must default to `false`.
- **Check status on appear.** The user can change login items directly in System Settings > General > Login Items. Query `SMAppService.mainApp.status` when the settings view appears to stay in sync.
- **Works with both App Store and direct distribution.** Unlike the old `SMLoginItemSetEnabled` which required a helper bundle, `SMAppService.mainApp` works directly with the main app.

Source: [Nil Coalescing — Add launch at login setting to a macOS app (Jan 2025)](https://nilcoalescing.com/blog/LaunchAtLoginSetting/)

## The "Hide Menu Bar Icon" Problem

Some users want to hide the menu bar icon entirely (to reduce clutter, especially on MacBooks with the notch). This creates a UX challenge: if the app has no Dock icon (`LSUIElement`) AND no menu bar icon, how does the user access settings or quit the app?

### Approaches

1. **Don't offer this option.** Simplest. Most menu bar utilities (Bartender, iStat Menus, Rectangle) keep the icon always visible. This is the safest choice for Squeegee v1.

2. **Global keyboard shortcut.** Register a global hotkey (e.g., Cmd+Shift+W) that opens the settings panel. The user can then show/hide the menu bar icon from settings. Requires Accessibility permission (which Squeegee already has).

3. **Relaunch to show settings.** If the user launches the app again from Finder/Spotlight while it is already running, detect the relaunch and show the settings panel. Implement via `NSApplication.delegate` method `applicationShouldHandleReopen(_:hasVisibleWindows:)`.

   ```swift
   func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
       // Show settings window
       showSettingsPanel()
       return true
   }
   ```

4. **Provide a separate "Show Settings" app/shortcut.** Overkill for most cases.

### Recommendation for Squeegee

**Keep the menu bar icon always visible for v1.** The icon serves as the primary UI and status indicator. If a "hide icon" option is added later, use approach #3 (relaunch detection) combined with #2 (global hotkey) as the recovery path.

## Combining MenuBarExtra with a Settings Window

Squeegee needs both a menu bar panel (quick status view) and a full Settings window (per-app rules, timing configuration). SwiftUI supports multiple scenes:

```swift
@main
struct SqueegeeApp: App {
    var body: some Scene {
        MenuBarExtra("Squeegee", systemImage: "xmark.circle") {
            QuickStatusView()
                .frame(width: 350, height: 500)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
        }
    }
}
```

The `Settings` scene provides a standard macOS preferences window, accessible via the menu bar panel (a "Settings..." button) or via Cmd+, when the app is frontmost. With `LSUIElement`, there is no app menu bar, so the Cmd+, shortcut may not work unless a custom key handler is set up. The practical approach is a "Settings..." button in the `MenuBarExtra` panel that opens the Settings window.

Source: [TechConcepts — macOS Menu Bar App Complete Guide (May 2026)](https://techconcepts.org/blog/macos-menu-bar-guide), [Level Up Coding — SwiftUI macOS Menu Bar Apps (Nov 2024)](https://levelup.gitconnected.com/swiftui-macos-menu-bar-apps-eecad19e749d)
