# Close vs. Quit: Approaches to Dismissing Windows and Apps

## Key Distinction on macOS

On macOS, closing a window and quitting an app are separate operations. Closing the last window of an app does **not** quit it (unlike Windows). This means WindowCleaner has three distinct operations available:

1. **Close a specific window** — the app keeps running
2. **Quit the app** — all windows close, the process exits
3. **Force-quit the app** — immediate termination, no save dialogs

Source: [MacMost: Why Does Closing Windows on a Mac not Quit the Application?](https://macmost.com/why-does-closing-windows-on-a-mac-not-quit-the-application.html)

## Method 1: Accessibility API — AXPress on Close Button

This is the **recommended approach** for WindowCleaner's per-window close.

### How It Works

```swift
// Get the close button from window AXUIElement
var closeButtonRef: CFTypeRef?
AXUIElementCopyAttributeValue(windowElement, kAXCloseButtonAttribute as CFString, &closeButtonRef)

// Press it
AXUIElementPerformAction(closeButtonRef as! AXUIElement, kAXPressAction as CFString)
```

### Behavior

- **Equivalent to the user clicking the red close button.** The app receives a standard close request.
- **Unsaved changes:** The app shows its normal dialog ("Save / Don't Save / Cancel"). The close is not forced. If the user clicks Cancel (or ignores the dialog), the window stays open.
- **App keeps running** after the window closes.
- **Works on:** Any app that uses standard NSWindow close buttons (nearly all native Mac apps).
- **Does not work on:** Windows without a close button (utility panels, sheets); some non-standard window implementations.
- **Permission required:** Accessibility (TCC)

### Unsaved Changes Handling

When AXPress closes a window with unsaved changes, the app's standard dialog appears. WindowCleaner should:
- Consider this acceptable — the user sees the dialog and decides
- Not attempt to dismiss the dialog automatically (that would risk data loss)
- Possibly detect that the window is still open after a timeout and mark it as "close blocked"

Source: [macOS behavior](https://soporte.colineal.com/article/the-essential-macbook-guide-how-to-close-windows-on-a-macbook-and-why-it-matters) ("Some apps (like TextEdit) close immediately, while others (like Preview) may prompt for unsaved changes.")

## Method 2: NSRunningApplication.terminate()

### How It Works

```swift
let app = NSRunningApplication(processIdentifier: pid)
app?.terminate()
```

### Behavior

- Sends a **normal quit request** to the entire application (equivalent to Cmd+Q or the Quit menu item)
- The app may show unsaved-changes dialogs for any open documents
- Returns `true` if the request was sent, `false` if not (e.g., app already terminated)
- **Returns before the app exits.** Observe the `isTerminated` property or listen for notifications to detect completion.
- **Closes all windows** of the app, then quits

Source: [objc2-app-kit docs](https://docs.rs/objc2-app-kit/latest/x86_64-unknown-linux-gnu/objc2_app_kit/struct.NSRunningApplication.html) ("Attempts to quit the receiver normally.")

### NSRunningApplication.forceTerminate()

```swift
app?.forceTerminate()
```

- **Forcefully kills the process** — equivalent to `kill -9`
- No save dialogs, no cleanup
- **Data loss risk:** Any unsaved work is lost
- Returns `true` if the kill signal was sent

Source: same as above ("Attempts to force the receiver to quit.")

### When to Use

- `terminate()` is appropriate when the intent is "quit this app" — e.g., a user rule like "quit Safari after 4 hours idle"
- `forceTerminate()` should only be a last resort, never automatic
- Neither is appropriate for WindowCleaner's primary "close this window" use case, because they quit the entire app

### Permission Notes

- `terminate()` and `forceTerminate()` do **not** require Accessibility permission
- They work on any `NSRunningApplication` you can reference by PID
- They work from a sandboxed app for apps in the same team, but **not** for arbitrary third-party apps if sandboxed. Non-sandboxed apps can terminate any process.

## Method 3: AppleScript / Apple Events

### Close Window

```applescript
tell application "Safari"
    close window 1
end tell
```

Or close a specific window by name:
```applescript
tell application "Preview"
    close window "Document.pdf"
end tell
```

### Behavior

- Sends a `close` Apple Event to the target application
- The app can respond however it wants — including showing a save dialog
- **The `saving` parameter** (`close window 1 saving yes/no/ask`) is supported by some apps but not all. The Finder, for example, ignores the `saving` parameter entirely.
- App support varies: "Each developer is free to program their app in any way they want, with the exception of a few Apple Events they are required to handle."

Sources:
- [AppleScript Finder Guide](https://applescriptlibrary.wordpress.com/wp-content/uploads/2013/11/applescript-finder-guide.pdf) ("the Finder ignores the saving and saving in parameters")
- [MacScripter: quit with saving doesn't work](https://www.macscripter.net/t/quit-with-saving-doesnt-work/25487)

### Quit App

```applescript
tell application "Preview" to quit
-- or with saving:
tell application "Preview" to quit saving yes
```

- `quit` is one of the required Apple Events that all apps must handle
- The `saving` parameter may or may not be honored

### Permission Required

- **Automation / Apple Events** TCC permission, which prompts **per target app**: "WindowCleaner wants to control Safari. Allow?"
- This is a major UX problem for WindowCleaner: the user would see a separate permission prompt for every app WindowCleaner tries to close. With Accessibility permission, one grant covers all apps.

Source: [Scripting OS X: Avoiding AppleScript Security and Privacy Requests](https://scriptingosx.com/2020/09/avoiding-applescript-security-and-privacy-requests)

### AppleScript from Swift

```swift
let script = NSAppleScript(source: """
    tell application "Safari"
        close window 1
    end tell
""")
var error: NSDictionary?
script?.executeAndReturnError(&error)
```

Or using `NSAppleEventDescriptor` for more control.

## Method 4: Direct `kill` Signals

```swift
kill(pid, SIGTERM) // Graceful shutdown request
kill(pid, SIGKILL) // Force kill (same as forceTerminate)
```

- Lowest-level approach; operates on the process, not windows
- SIGTERM allows cleanup; SIGKILL does not
- No save dialogs with either signal
- Inappropriate for WindowCleaner's per-window close

## Comparison for WindowCleaner

| Method | Granularity | Save dialog? | Permission | UX burden |
|--------|------------|-------------|------------|-----------|
| AXPress close button | Per window | Yes | Accessibility (one prompt) | Low |
| NSRunningApplication.terminate() | Per app | Yes | None (non-sandboxed) | Low |
| NSRunningApplication.forceTerminate() | Per app | No (data loss) | None (non-sandboxed) | Low |
| AppleScript close window | Per window | Depends on app | Automation (per-app prompt) | High |
| AppleScript quit | Per app | Depends on app | Automation (per-app prompt) | High |

### Recommendation

**Use Accessibility API (AXPress on close button) as the primary close mechanism:**
- Per-window granularity matches WindowCleaner's design
- Single Accessibility permission covers all apps
- Standard save dialogs protect user data
- Widely proven in production apps (AltTab, Rectangle, etc.)

**Use NSRunningApplication.terminate() as an optional "quit app" action:**
- For when the user configures "quit this app after N hours" instead of "close windows"
- No additional permission needed
- Shows save dialogs

**Avoid AppleScript for window closing:**
- The per-app permission prompts would make the UX unacceptable
- Behavior is inconsistent across apps
