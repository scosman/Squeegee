# Activity Signals That Need Accessibility Permission

This document covers signals available via the macOS Accessibility API (`AXObserver`). All require that the user grants Accessibility permission in System Settings > Privacy & Security > Accessibility.

## AXObserver Setup Pattern

To receive notifications about another app's windows, you create an `AXObserver` per app and register for specific notification types.

```swift
// 1. Create application element from PID
let appElement = AXUIElementCreateApplication(app.processIdentifier)

// 2. Create observer with callback
var observer: AXObserver?
AXObserverCreate(app.processIdentifier, axCallback, &observer)

// 3. Register for notifications
AXObserverAddNotification(observer!, appElement,
    kAXFocusedWindowChangedNotification as CFString, nil)

// 4. Add to run loop
CFRunLoopAddSource(CFRunLoopGetCurrent(),
    AXObserverGetRunLoopSource(observer!),
    .defaultMode)
```

The callback receives the `AXUIElement` that fired the notification, the notification name, and optional user data.

Source: [GPII DeveloperSpace — AXObserver example](https://ds.gpii.net/content/axobservercreate-notification-example-swift-accessibility-api)

---

## Window-Relevant AX Notifications

All constant names are from `AXNotificationConstants.h` ([GNUstep mirror](https://github.com/gnustep/libs-boron/blob/master/Headers/HIServices/AXNotificationConstants.h), [Apple docs](https://developer.apple.com/documentation/applicationservices/axnotificationconstants_h)).

### Focus Tracking

| Notification | Fires when | What it gives WindowCleaner |
|---|---|---|
| `kAXFocusedWindowChangedNotification` | The focused window changes within an app | Identifies exactly which window the user is interacting with |
| `kAXMainWindowChangedNotification` | The main window changes within an app | Similar to focused, but "main" and "focused" can differ (e.g., a floating palette is key but the document is main) |
| `kAXApplicationActivatedNotification` | An app becomes active | Redundant with `NSWorkspace.didActivateApplicationNotification` but delivered through AX |
| `kAXApplicationDeactivatedNotification` | An app leaves the foreground | Redundant with `NSWorkspace.didDeactivateApplicationNotification` |

**Note on focused vs main:** The "focused window" (key window) receives keyboard input. The "main window" is the primary document window. A floating inspector panel can be key/focused while the document window remains main. For WindowCleaner's purposes, both signals indicate activity on those respective windows.

### Window Lifecycle

| Notification | Fires when | What it gives WindowCleaner |
|---|---|---|
| `kAXWindowCreatedNotification` | A new window opens | Detect new windows immediately (vs polling) |
| `kAXUIElementDestroyedNotification` | A UI element is destroyed | Detect window close. Note: fires for all element types, not just windows — you must filter by checking the element's role |

**There is no `kAXWindowClosedNotification`.** Window destruction is detected via `kAXUIElementDestroyedNotification`. You register this notification on the specific window element, not the app element.

### Window Geometry Changes

| Notification | Fires when |
|---|---|
| `kAXWindowMovedNotification` | Window was moved (fires at end of drag, not during) |
| `kAXWindowResizedNotification` | Window was resized |
| `kAXWindowMiniaturizedNotification` | Window was minimized to Dock |
| `kAXWindowDeminiaturizedNotification` | Window was restored from Dock |

These are useful as weak activity signals — if a user moves or resizes a window, they are interacting with it. However, "not moved" does not mean "not active."

### App Visibility

| Notification | Fires when |
|---|---|
| `kAXApplicationHiddenNotification` | App was hidden (Cmd-H) |
| `kAXApplicationShownNotification` | Hidden app was shown |

### Window Title

| Notification | Fires when |
|---|---|
| `kAXTitleChangedNotification` | Window title changed |

Useful as an activity signal: a title change often means new content (e.g., navigating to a new web page in Safari, opening a new document). However, title changes can also be noisy (progress indicators in titles, etc.).

---

## Focused Window for Non-Frontmost Apps

You can query `kAXFocusedWindowAttribute` on any app's `AXUIElement`, even if that app is not currently frontmost. However, the returned value is the window that *was* focused when the app was last in the foreground — it does not update while the app is in the background.

```swift
let appElement = AXUIElementCreateApplication(pid)
var focusedWindow: AnyObject?
AXUIElementCopyAttributeValue(appElement,
    kAXFocusedWindowAttribute as CFString, &focusedWindow)
```

**Implication for WindowCleaner:** When an app comes to the foreground, you can immediately query which of its windows is focused — this tells you which specific window the user selected, not just the app.

Sources:
- [Apple Developer Forums — focused window per app](https://developer.apple.com/forums/thread/794253)
- [native-devtools-mcp PR #13 — raise_window](https://github.com/vectora-foundry/native-devtools-mcp/pull/13)

---

## Architecture: Per-App and Per-Window Observers

The mac-taskbar project ([PR #2](https://github.com/MeKo-Christian/mac-taskbar/pull/2)) demonstrates a proven pattern:

**App-level observer (one per running app):**
- `kAXWindowCreatedNotification`
- `kAXFocusedWindowChangedNotification`
- `kAXApplicationHiddenNotification` / `kAXApplicationShownNotification`

**Per-window observer (one per tracked window):**
- `kAXUIElementDestroyedNotification`
- `kAXTitleChangedNotification`
- `kAXWindowMiniaturizedNotification` / `kAXWindowDeminiaturizedNotification`
- `kAXWindowMovedNotification` / `kAXWindowResizedNotification`

**Key design decisions from that project:**
- **Event coalescing:** Notification bursts (e.g., during window dragging) are coalesced into one refresh after 50 ms.
- **Reconciliation:** Every 5 seconds, the observer list is reconciled with `NSWorkspace.shared.runningApplications` to attach to new apps and detach from terminated ones.
- **Retry for launching apps:** Apps that are still initializing may reject `AXObserverAddNotification` — the system retries on the next reconciliation cycle.
- **Performance gain:** Idle CPU dropped from ~2.1% (0.5s polling) to ~0.2% (event-driven + 5s safety net).

---

## Reliability Concerns

Several developers have reported that AX notifications can be unreliable:

1. **Some notifications stop firing** after macOS updates. One workaround is launching Apple's Accessibility Inspector, after which notifications start coming through.

2. **`kAXSelectedTextChangedNotification`** is reported as unreliable for some apps, while `kAXWindowMovedNotification` and `kAXWindowResizedNotification` work consistently.

3. **Swift calling convention issues:** `AXObserverAddNotification` has been reported to fail when called from Swift on certain macOS versions. Writing the observer setup in C or using a wrapper library (AXSwift, DFAXUIElement) can be a workaround.

4. **Permission state changes:** If the user toggles Accessibility permission while the app is running, `AXObserver` calls may hang or return errors. The app should check `AXIsProcessTrusted()` periodically and handle the transition gracefully.

Sources:
- [Apple Developer Forums — AXObserver notification reliability](https://developer.apple.com/forums/thread/687965)
- [AXSwift library](https://github.com/tmandry/AXSwift)
- [DFAXUIElement library](https://github.com/DevilFinger/DFAXUIElement)
- [mac-taskbar PR #2 — event-driven architecture](https://github.com/MeKo-Christian/mac-taskbar/pull/2)
