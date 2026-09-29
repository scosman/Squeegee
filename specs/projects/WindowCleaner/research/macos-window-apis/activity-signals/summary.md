# Activity Signals

## Bottom Line

WindowCleaner can track window activity at the app level without any special permissions, using `NSWorkspace.didActivateApplicationNotification` (frontmost app changes), `CGWindowListCopyWindowInfo` polling at 1 Hz (window on-screen state, z-order, and position changes), and `CGEventSource.secondsSinceLastEventType` (user idle detection). None of these need Accessibility or Screen Recording. With Accessibility permission, the app gains per-window focus tracking via `AXObserver` and `kAXFocusedWindowChangedNotification`, which tells you exactly which window in a multi-window app the user is interacting with. The recommended design is a tiered approach: ship with no-permission signals by default, and unlock finer-grained per-window tracking when the user opts into Accessibility.

## Key Findings

- **`NSWorkspace.didActivateApplicationNotification` needs no permission** and fires every time the frontmost app changes. It provides the `NSRunningApplication` of the newly active app. Paired with `didDeactivateApplicationNotification`, you can compute per-app foreground duration. This is the primary free signal. ([Apple docs](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification))

- **`CGWindowListCopyWindowInfo` with `kCGWindowListOptionOnScreenOnly` returns windows in front-to-back z-order** and needs no permission for basic fields (`kCGWindowNumber`, `kCGWindowBounds`, `kCGWindowOwnerPID`, `kCGWindowIsOnscreen`, `kCGWindowLayer`). Only `kCGWindowName` requires Screen Recording. The first layer-0 entry is the frontmost window. Polling at 1 Hz costs 2-4 ms per call for typical window counts. ([Apple docs](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)), [ai-buddy benchmarks](https://github.com/omesser/ai-buddy/issues/1047))

- **`CGEventSource.secondsSinceLastEventType` needs no permission** and returns seconds since the last keyboard/mouse input. It queries the window server directly (same source the screensaver uses). Use it to freeze close timers during user absence. ([block/buzz PR #2820](https://github.com/block/buzz/pull/2820))

- **`AXObserver` with `kAXFocusedWindowChangedNotification` requires Accessibility permission** but gives per-window focus tracking. A proven architecture (one observer per app, coalesced events, 5s reconciliation poll) reduces idle CPU to ~0.2% compared to ~2.1% for 0.5s polling. ([mac-taskbar PR #2](https://github.com/MeKo-Christian/mac-taskbar/pull/2), [AXNotificationConstants.h](https://github.com/gnustep/libs-boron/blob/master/Headers/HIServices/AXNotificationConstants.h))

- **The user's "never entered foreground" heuristic is strong** — windows whose app has never been frontmost are the safest to close. **"Never in foreground for 5s+" is moderate** — useful as a secondary tier to distinguish "passed through" from "used." **"Moved position" is weak** (the user was correct) — manual moves indicate activity, but absence of movement proves nothing.

- **Polling at 1 Hz is within Apple's energy budget** (no more than 1 wakeup/second idle). Set timer leeway to at least 10% for coalescing. Pause polls during display sleep. Use timestamp-based timing (store `Date` per window), not accumulated timer ticks, to handle sleep and App Nap correctly. ([Apple Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html))

- **Without Accessibility, the main gap is per-window focus in multi-window apps.** You know which app is frontmost but not which of its windows the user is looking at. The conservative fallback is to reset the timer for all windows of the frontmost app.

## Details

- [No-permission signals](./no-permission-signals.md) — Complete documentation of `NSWorkspace` notifications, `CGWindowListCopyWindowInfo` fields and z-order behavior, `CGEventSource` idle detection, and sleep/wake handling. Read this for the full API surface available without special permissions.

- [Accessibility signals](./accessibility-signals.md) — Complete list of AX notifications relevant to window activity (`kAXFocusedWindowChangedNotification`, `kAXWindowCreatedNotification`, `kAXWindowMovedNotification`, etc.), the per-app/per-window observer architecture, and known reliability issues. Read this when designing the Accessibility-enhanced mode.

- [Polling vs notifications](./polling-vs-notifications.md) — Side-by-side comparison of polling `CGWindowListCopyWindowInfo` vs event-driven `AXObserver`, benchmark data (2-4 ms per poll, 7-18 us per window), Apple's energy guidelines, App Nap behavior, and concrete implementation notes (timer setup, sleep gating, timestamp-based timing). Read this for the engineering design.

- [Heuristics evaluation](./heuristics-evaluation.md) — Evaluation of the three proposed heuristics ("never entered foreground," "never in foreground for 5s+," "moved position") plus additional heuristics worth considering. Includes a ranked signal table and discussion of accuracy limits (focused window in background apps, split-screen, fullscreen).

## Open Questions / Gaps

- **App Nap throttling behavior for menu bar apps is not precisely documented.** WindowCleaner runs as a menu bar app (`LSUIElement`) with no visible windows — it meets all App Nap criteria. Apple's docs say timers are throttled but do not specify by how much. This is acceptable for hour-scale timers, but the exact throttle factor is unknown. Testing on real hardware is needed.

- **`kCGWindowIsOnscreen` bugs on macOS 14-15.** Some windows that are visually on-screen are absent from the on-screen-only results but present in the all-windows results. This is a documented Apple bug ([Apple Developer Forums](https://developer.apple.com/forums/thread/767688)). WindowCleaner should compare both result sets rather than relying solely on `kCGWindowListOptionOnScreenOnly`.

- **IOPMAssertion detection for video watching.** I confirmed that `IOPMCopyAssertionsStatus()` can check whether a video player holds a display-sleep assertion, but I did not verify the exact API usage in Swift or confirm it needs no permission. This is a secondary feature for the idle-detection logic.

## Sources

- [Apple docs: didActivateApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification) — Primary reference for frontmost-app notification
- [Apple docs: CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:)) — Window list API reference
- [Apple docs: kCGWindowIsOnscreen](https://developer.apple.com/documentation/coregraphics/kcgwindowisonscreen) — On-screen state key
- [Apple docs: activeSpaceDidChangeNotification](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification) — Space change notification
- [Apple docs: AXNotificationConstants.h](https://developer.apple.com/documentation/applicationservices/axnotificationconstants_h) — Complete list of AX notifications
- [Apple Energy Efficiency Guide — Timers](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html) — Timer best practices, tolerance, coalescing
- [Apple Energy Efficiency Guide — App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html) — App Nap conditions and behavior
- [GNUstep AXNotificationConstants.h mirror](https://github.com/gnustep/libs-boron/blob/master/Headers/HIServices/AXNotificationConstants.h) — Full AX notification constant definitions
- [mac-taskbar PR #2](https://github.com/MeKo-Christian/mac-taskbar/pull/2) — Event-driven AXObserver architecture, performance benchmarks
- [ai-buddy issue #1047](https://github.com/omesser/ai-buddy/issues/1047) — CGWindowListCopyWindowInfo polling cost benchmarks
- [block/buzz PR #2820](https://github.com/block/buzz/pull/2820) — CGEventSource idle detection, no permission needed
- [Receiving Workspace Notifications (Apple Archive)](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Workspace/Articles/WorkspaceNotifications.html) — NSWorkspace notification overview
- [Apple Developer Forums — sleep notification inconsistencies](https://developer.apple.com/forums/thread/796109) — Sleep/wake reliability
- [Apple Developer Forums — window ordering](https://developer.apple.com/forums/thread/129903) — CGWindowList z-order behavior
- [Apple Developer Forums — on-screen visibility bugs](https://developer.apple.com/forums/thread/767688) — kCGWindowIsOnscreen edge cases (macOS 14-15)
