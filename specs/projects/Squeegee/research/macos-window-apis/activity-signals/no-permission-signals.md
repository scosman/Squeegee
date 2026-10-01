# Activity Signals That Need No Special Permission

This document covers signals Squeegee can use to detect window activity without asking for Accessibility or Screen Recording permission.

## 1. Frontmost App Changes: `NSWorkspace.didActivateApplicationNotification`

**Permission required: None.**

This is the single most useful free signal. The system posts it on `NSWorkspace.shared.notificationCenter` every time the frontmost (active) application changes. The notification's `userInfo` contains `NSWorkspace.applicationUserInfoKey`, which yields an `NSRunningApplication` with the PID, bundle ID, and localized name of the newly activated app.

```swift
NSWorkspace.shared.notificationCenter
    .publisher(for: NSWorkspace.didActivateApplicationNotification)
    .sink { note in
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication else { return }
        // app is now frontmost — record timestamp for this app's windows
    }
    .store(in: &bag)
```

**Related notifications (also no permission):**

| Notification | Fires when |
|---|---|
| `didDeactivateApplicationNotification` | An app leaves the foreground |
| `didHideApplicationNotification` | An app is hidden (Cmd-H) |
| `didUnhideApplicationNotification` | A hidden app is shown |
| `didLaunchApplicationNotification` | A new app launches |
| `didTerminateApplicationNotification` | An app terminates |

All are delivered via `NSWorkspace.shared.notificationCenter` (not `NotificationCenter.default`).

**Limitation:** This signal tells you *which app* is frontmost, not *which window*. An app with five open windows gives you only one event when it comes to the foreground. You cannot tell which of those five windows the user is looking at.

Sources:
- [Apple docs: didActivateApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification?language=objc)
- [Receiving Workspace Notifications (Apple Archive)](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Workspace/Articles/WorkspaceNotifications.html)
- [onmyway133/blog #900 — frontmost app detection](https://github.com/onmyway133/blog/issues/900)

---

## 2. Space Changes: `NSWorkspace.activeSpaceDidChangeNotification`

**Permission required: None.**

Posted when the user switches Spaces (virtual desktops), including swipe-between-fullscreen-apps. No permission needed.

This matters because a Space change means a different set of windows is now visible. Combined with a `CGWindowListCopyWindowInfo` poll (see section 4), you can update your "on-screen" window set after each switch.

**Limitation:** There is no public API to identify *which* Space is active — only that a change occurred. Private API `CGSCopyManagedDisplaySpaces` exists but is unsupported and breaks across OS versions.

Sources:
- [Apple docs: activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)
- [Swindler issue #26 — space tracking heuristics](https://github.com/tmandry/swindler/issues/26)
- [CodeJam — Swift space change detection](https://www.codejam.info/2024/05/swift-detect-space-virtual-desktop-changes.html)

---

## 3. User Idle Time: `CGEventSource.secondsSinceLastEventType`

**Permission required: None.**

This function returns the number of seconds since the last user input event (keyboard or mouse) for the login session. It queries the window server directly — the same source the screensaver uses.

```swift
let idleSeconds = CGEventSource.secondsSinceLastEventType(
    .combinedSessionState,
    eventType: CGEventType(rawValue: ~0)!  // kCGAnyInputEventType
)
```

**Why no permission:** The function returns only a time interval — it does not expose what keys were pressed or where the mouse moved. It has been available since Mac OS X 10.4.

**Use for Squeegee:** When computing "time since last active," subtract idle time so that a user who leaves for lunch does not have their windows closed while they are away. For example, if the close threshold is 2 hours and the user has been idle for 1.5 hours, the effective active-age of each window should freeze during those 1.5 hours.

**Caveat — video watching:** A user watching a long video gives no input events, but they are at the computer. Video-playing apps typically hold an `IOPMAssertion` to prevent the display from sleeping. You can check for active assertions via `IOPMCopyAssertionsStatus()` to distinguish "idle because away" from "idle because watching."

Sources:
- [GitHub Gist — macOS idle time in Swift](https://gist.github.com/c586ce379d3e7e91a57d89ed557192ec)
- [block/buzz PR #2820 — idle detection fix](https://github.com/block/buzz/pull/2820)
- [Apple Developer Forums — CGEventSourceSecondsSinceLastEventType](https://developer.apple.com/forums/thread/25509)

---

## 4. Window Z-Order and On-Screen State via `CGWindowListCopyWindowInfo`

**Permission required: None for basic fields; Screen Recording for `kCGWindowName`.**

`CGWindowListCopyWindowInfo` returns an array of dictionaries describing all windows in the user session. The fields available without Screen Recording include:

| Key | Type | Description |
|---|---|---|
| `kCGWindowNumber` | Int | Stable window ID for the life of the window |
| `kCGWindowOwnerPID` | Int | PID of the owning process |
| `kCGWindowOwnerName` | String | Process name (always available) |
| `kCGWindowBounds` | Dict | `{X, Y, Width, Height}` of the window frame |
| `kCGWindowLayer` | Int | 0 = normal app window |
| `kCGWindowIsOnscreen` | Bool | `true` if the window is ordered on-screen; key absent means off-screen |
| `kCGWindowAlpha` | Float | Window opacity |
| `kCGWindowStoreType` | Int | Backing store type |

**Z-order:** When called with `kCGWindowListOptionOnScreenOnly`, the returned array is in front-to-back order. The first window at `kCGWindowLayer == 0` is the frontmost normal window. This gives you the frontmost window on the current Space — without Accessibility.

**On-screen vs off-screen:** `kCGWindowIsOnscreen` being `true` means the window server has ordered the window onto a display. If the key is absent, the window is off-screen (minimized, on another Space, or in a hidden app). This lets you detect minimization by comparing `kCGWindowListOptionAll` results against `kCGWindowIsOnscreen`.

**What this gives Squeegee (polling approach):**
- Which windows just appeared or disappeared from screen
- Position/size changes between polls (window moved or resized)
- The frontmost window per Space (first layer-0 entry in on-screen-only results)
- Whether a window went off-screen (minimized or switched Space)

**What it cannot give you:**
- Which window *within* a multi-window app is focused (only the frontmost across all apps)
- Event-driven notification of changes — you must poll

Sources:
- [Apple docs: CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))
- [Apple docs: kCGWindowIsOnscreen](https://developer.apple.com/documentation/coregraphics/kcgwindowisonscreen)
- [Apple Developer Forums — window list ordering](https://developer.apple.com/forums/thread/129903)
- [Apple Developer Forums — window visible but not in onscreen list](https://developer.apple.com/forums/thread/767688)

---

## 5. Sleep/Wake Notifications

**Permission required: None.**

| Notification | Fires when |
|---|---|
| `willSleepNotification` | System is about to sleep |
| `didWakeNotification` | System woke from sleep |
| `screensDidSleepNotification` | Display went to sleep (may happen before system sleep) |
| `screensDidWakeNotification` | Display woke |

**Use for Squeegee:** Pause the close timer during sleep. On wake, use `CGEventSource.secondsSinceLastEventType` to determine how long the user was away, rather than trusting timer ticks that may have been frozen during sleep.

**Caveat:** Sleep/wake notification delivery can be inconsistent across MacBook models (documented on [Apple Developer Forums](https://developer.apple.com/forums/thread/796109)). Using multiple notifications and timestamp-based calculations (rather than accumulated timer ticks) is recommended.

Sources:
- [Apple docs: willSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/willsleepnotification)
- [Apple docs: screensDidSleepNotification](https://developer.apple.com/documentation/appkit/nsworkspace/screensdidsleepnotification)
- [Apple Developer Forums — Sleep notification inconsistencies](https://developer.apple.com/forums/thread/796109)
