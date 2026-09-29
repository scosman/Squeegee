# Window Identity, Stability, and Lifecycle

## CGWindowID: The Primary Identifier

`CGWindowID` is a `uint32_t` value assigned by the window server. It is the closest thing macOS provides to a stable, unique window identifier.

```c
typedef uint32_t CGWindowID;
#define kCGNullWindowID ((CGWindowID)0)
```

Source: [CGWindow.h](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGWindow.h)

### Stability

- **A CGWindowID is stable for the entire lifetime of a window.** It does not change when the window moves, resizes, changes title, changes Spaces, enters full-screen, is minimized, or is hidden.
- Peekaboo (a macOS window inspection tool) documents CGWindowID as "a stable identifier that persists for the window's lifetime" and stores it in snapshots for reliable follow-up commands.

Source: [Peekaboo focus documentation](https://peekaboo.sh/focus.html)

### Reuse

- CGWindowIDs are assigned incrementally by the window server. After a window is destroyed, its ID **can** be reused — but only after the counter wraps around the full `uint32_t` range, or under memory pressure scenarios.
- In practice, with a 32-bit counter starting from a high value, reuse within the lifetime of a user session is extremely unlikely for a tool that polls every few minutes. The window server creates thousands of windows during a session (every menu, tooltip, and popup is a window), but `uint32_t` has ~4 billion values.
- **Inference:** For an app like WindowCleaner that tracks windows over hours, CGWindowID is reliable as an identity key within a single user session. Do not persist CGWindowIDs across reboots or user session changes.

**Note:** I could not find an official Apple document confirming reuse policy. The above is inferred from the uint32_t type, observed monotonic incrementing behavior reported by developers, and the practical fact that window management tools rely on CGWindowID stability without encountering reuse issues.

## Tabs vs. Windows

### How Tabs Appear to CGWindowListCopyWindowInfo

macOS has a system-level tab bar (introduced macOS Sierra, 10.12) that groups NSWindows into a tabbed interface. How tabs appear depends on the API and options used:

**With `.optionOnScreenOnly`:**
- Only the **active (visible) tab** in each tab group has an on-screen window. Background tabs do not appear.

**With `.optionAll`:**
- Background tabs may appear as separate entries, but they are off-screen, have zero or small bounds, and are not marked `kCGWindowIsOnscreen`. Different apps behave differently.
- **Xcode** creates a visible helper window for each open tab (even background ones).
- **Safari** does not expose individual tabs as separate CGWindowList entries — it has one window per browser window, and tabs within it are internal to the app.

Source: [SO: Separating real and dummy windows](https://stackoverflow.com/questions/58453011/separating-real-and-dummy-windows-returned-by-cgwindowlistcopywindowinfo)

### How Tabs Appear to Accessibility API

- `kAXWindowsAttribute` returns the app's "real" windows. For a tabbed window, this is typically **one AXUIElement per tab group** (the visible window), not one per tab.
- AltTab has a "Show standard tabs as separate windows" option that uses a complex heuristic: subscribing to `kAXFocusedUIElementChangedNotification` and detecting when new windows appear/disappear as the user switches tabs. This is unreliable — tabs created before AltTab starts are invisible, and multi-tab-group scenarios are ambiguous.

Source: [AltTab issue #1540](https://github.com/lwouis/alt-tab-macos/issues/1540)

### Practical Implication for WindowCleaner

WindowCleaner should operate on **windows**, not tabs. A browser window with 50 tabs is one window. This matches user expectation ("close Safari windows that have been open for 4 hours") and avoids the complexity of tab detection. Tabs within a window are the app's concern, not WindowCleaner's.

## Spaces (Mission Control Desktops)

- Windows on other Spaces **are not returned** by `.optionOnScreenOnly` — they are not "on screen."
- Windows on other Spaces **are returned** by `.optionAll`.
- A window's Space is **not available** from `CGWindowListCopyWindowInfo`. There is no key for which Space a window is on.
- Private APIs exist to query window Spaces (e.g., `CGSCopySpacesForWindows`), but these are fragile. AltTab [reported](https://github.com/lwouis/alt-tab-macos/issues/447) that `CGSAddWindowsToSpaces` stopped working in macOS 12.3.1.
- For WindowCleaner, Spaces are irrelevant — a window's age timer should run regardless of which Space it is on. Using `.optionAll` captures all windows across all Spaces.

## Full-Screen Windows

- Full-screen windows have their own Space and are visible in `CGWindowListCopyWindowInfo` with both `.optionOnScreenOnly` (if currently active) and `.optionAll`.
- The window's bounds fill the screen dimensions.
- The CGWindowID does not change when a window enters or exits full-screen mode.
- The Accessibility API still works on full-screen windows.

## Minimized Windows

- Minimized windows are **not** returned by `.optionOnScreenOnly` — they are off-screen (in the Dock).
- Minimized windows **are** returned by `.optionAll`, with `kCGWindowIsOnscreen = false`.
- Via Accessibility: `kAXMinimizedAttribute` returns `true` for minimized windows; `kAXWindowsAttribute` still lists them.
- The CGWindowID does not change when a window is minimized or restored.

## Hidden Apps

- When an app is hidden (Cmd+H, `NSRunningApplication.hide()`), all its windows disappear from screen.
- Hidden windows are **not** returned by `.optionOnScreenOnly`.
- Hidden windows **are** returned by `.optionAll`.
- `NSRunningApplication.isHidden` tells you if an app is hidden.
- CGWindowIDs remain stable through hide/unhide cycles.

## Window Creation Time

### No API Exists

There is **no API that provides a window creation timestamp.** This is confirmed by:
- The complete list of CGWindowList keys (required and optional) has no creation time field
- The AXUIElement attribute set for windows has no creation date attribute
- No developer documentation, forum post, or source code I found references a window creation time API

### Workarounds for Inferring "Opened At"

1. **First observation time:** Poll `CGWindowListCopyWindowInfo` periodically. The first time a CGWindowID appears that wasn't in the previous poll, record that timestamp as "first seen." This is the most practical approach.
   - Limitation: if WindowCleaner is launched after the window was opened, the first-seen time is the launch time of WindowCleaner, not the window's actual creation time.

2. **App launch time via `NSRunningApplication.launchDate`:** This property returns when the app was launched. For apps that open their main window at launch, this approximates window creation time. Not useful for apps that open multiple windows over time.
   - Also available via `lsappinfo info -only kLSLaunchTimeKey <AppName>` in Terminal.
   
   Source: [The Robservatory: See the launch date and time for any app or process](https://robservatory.com/see-the-launch-date-and-time-for-any-app-or-process)

3. **Accessibility notifications:** Subscribe to `kAXWindowCreatedNotification` via `AXObserverCreate` / `AXObserverAddNotification`. This fires when a new window is created, providing a real-time creation timestamp — but only for windows created after WindowCleaner starts observing.

### Recommended Approach for WindowCleaner

Combine methods:
- On launch, snapshot all existing windows via `CGWindowListCopyWindowInfo(.optionAll, ...)`. Record their CGWindowIDs with "first seen = now."
- Subscribe to `kAXWindowCreatedNotification` for each running app to catch new windows in real-time.
- Accept that pre-existing windows' "opened at" time will be approximate (= WindowCleaner's launch time). This is acceptable because the user just installed the app and old windows will be closed soon anyway.

## AXIdentifier

Some windows expose an `AXIdentifier` attribute — a developer-provided stable string identifier. Peekaboo notes this is "rarely available." It should not be relied on for general window tracking.

Source: [Peekaboo focus documentation](https://peekaboo.sh/focus.html)
