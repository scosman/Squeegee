# Polling vs Notifications: Design Tradeoffs

This document evaluates the two main approaches to tracking window activity on macOS and recommends a practical design for Squeegee.

## The Two Approaches

### Approach A: Notification-Driven (Accessibility Required)

Use `NSWorkspace` notifications (no permission) for app-level events, and `AXObserver` (Accessibility permission) for per-window events.

| Aspect | Details |
|---|---|
| **Accuracy** | High — exact timestamps for focus changes, window creation/destruction, move/resize |
| **Energy** | Low — ~0.2% idle CPU (event-driven + 5s reconciliation poll). [mac-taskbar PR #2](https://github.com/MeKo-Christian/mac-taskbar/pull/2) |
| **Permission** | Accessibility required. No Screen Recording needed |
| **Complexity** | High — must manage one observer per app, handle app launch/quit, retry for slow-launching apps, handle permission revocation |
| **Reliability** | Generally good, but some macOS versions have bugs where notifications stop firing |

### Approach B: Polling `CGWindowListCopyWindowInfo` (No Permission Required)

Poll the window list on a timer and diff against previous state to detect changes.

| Aspect | Details |
|---|---|
| **Accuracy** | Medium — can detect frontmost window, on-screen state, position changes. Cannot identify focused window within a multi-window app |
| **Energy** | Moderate — depends on poll frequency and window count |
| **Permission** | None for basic fields. Screen Recording for window titles |
| **Complexity** | Lower — single timer, single API call, diff logic |
| **Reliability** | Consistent — no observer registration bugs |

---

## Polling Cost Benchmarks

Data from the ai-buddy/fidget project ([issue #1047](https://github.com/omesser/ai-buddy/issues/1047), [issue #427](https://github.com/omesser/ai-buddy/issues/427)):

| Metric | Measurement |
|---|---|
| Call latency (standalone process) | ~0.4 ms median |
| Call latency (in-app) | 1.5 - 3.9 ms median |
| In-app slowdown factor | 3.7 - 5.4x |
| Worst-case single call | 15.2 ms |
| Per-window scaling | 7 - 18 us/window |
| At 156 windows, p95 | 10.8 ms |
| Achieved Hz (desktop, ~20 windows) | 45.4 Hz |
| Achieved Hz (100 added windows) | 40.2 Hz |

**For Squeegee's use case (1-4 Hz polling):** At 1 Hz with typical window counts (20-50), a single poll takes 2-4 ms. This is negligible. At 4 Hz, it is still well under 1% CPU.

### Energy Recommendations from Apple

Apple's [Energy Efficiency Guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html):

1. **Set timer tolerance to at least 10% of the interval** to enable timer coalescing.
2. **Target no more than 1 wakeup per second when idle.** (Apple's stated performance guideline.)
3. **Invalidate timers that are no longer needed.** "Forgetting to stop timers probably wastes more energy than anything else in OS X."
4. **Pause during sleep.** A 250 ms timer that never pauses costs ~14,400 window-list reads per hour during sleep. Gate polls on `CGDisplayIsAsleep` or `screensDidSleepNotification`. [notchline issue #68](https://github.com/soondubu137/notchline/issues/68)

### App Nap Considerations

[Apple's App Nap documentation](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html):

App Nap activates when ALL of these are true:
- App is not the foreground app
- App has not recently updated visible window content
- App is not playing audio
- App has not taken IOKit power management assertions
- App is not using OpenGL

**Impact:** App Nap throttles timers, so a 1s polling interval may fire much less frequently when Squeegee is in the background (which is always, since it is a menu bar app).

**This is actually fine for Squeegee.** The app does not need sub-second precision for close timers measured in hours. If App Nap throttles the poll from 1 Hz to every 30 seconds, that is acceptable.

If you need to prevent App Nap for a specific activity, use `ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "...")`. But for Squeegee, there is no reason to fight App Nap.

---

## Recommended Design for Squeegee

### Tiered approach — free signals first, Accessibility optional

**Tier 1 (No Permission):**
1. Subscribe to `NSWorkspace.didActivateApplicationNotification` and `didDeactivateApplicationNotification` for app-level foreground tracking. Record timestamps per app.
2. Subscribe to `activeSpaceDidChangeNotification` to know when the visible window set changes.
3. Subscribe to sleep/wake notifications to pause timers.
4. Poll `CGWindowListCopyWindowInfo` at **1 Hz** (with 10% tolerance) to:
   - Detect new windows (new `kCGWindowNumber` values)
   - Detect closed windows (disappeared `kCGWindowNumber` values)
   - Track on-screen state via `kCGWindowIsOnscreen`
   - Detect the frontmost window (first layer-0 entry in on-screen-only results)
   - Detect position/size changes (compare `kCGWindowBounds`)
5. Check `CGEventSource.secondsSinceLastEventType` on each poll to detect user idle time. Freeze close timers when idle exceeds a threshold (e.g., 5 minutes).

**Tier 2 (With Accessibility — optional enhancement):**
If the user grants Accessibility permission, switch from polling-based window tracking to event-driven:
1. Register `AXObserver` per app for `kAXFocusedWindowChangedNotification`, `kAXWindowCreatedNotification`.
2. Register per window for `kAXUIElementDestroyedNotification`, `kAXWindowMiniaturizedNotification`.
3. Reduce poll frequency to **0.2 Hz** (every 5 seconds) as a reconciliation safety net.
4. Gain per-window focus tracking — know exactly which window in a multi-window app is active.

### Why 1 Hz for Tier 1

- Squeegee's close thresholds are measured in hours. Detecting activity within 1 second is more than sufficient.
- 1 Hz is at Apple's recommended maximum of 1 wakeup/second for idle apps.
- The poll itself costs 2-4 ms — negligible.
- App Nap may throttle this further, which is acceptable.

### What You Lose Without Accessibility

| Capability | With Accessibility | Without |
|---|---|---|
| Per-window focus tracking | Exact, via notification | Only frontmost window across all apps (via z-order) |
| Window creation detection | Immediate | Within 1 second (poll) |
| Window close detection | Immediate | Within 1 second (poll) |
| Move/resize detection | Immediate, event-driven | Within 1 second (poll diff) |
| Energy cost | ~0.2% CPU idle | ~0.5-1% CPU (1 Hz poll) |

**Assessment:** The loss of per-window focus tracking is the main gap. Without Accessibility, you know which *app* is frontmost but not which *window* within that app. For apps with a single window, this does not matter. For apps like Safari with many windows, you would reset the timer for all windows of the frontmost app, not just the one the user is looking at. This is a conservative approach — windows stay open longer than necessary, which is a safe default.

---

## Polling Implementation Notes

### Pause during sleep/display-off

```swift
// Gate on display state
var displayAsleep = false

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main
) { _ in displayAsleep = true }

NSWorkspace.shared.notificationCenter.addObserver(
    forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main
) { _ in displayAsleep = false }

// In poll timer:
guard !displayAsleep else { return }
```

### Timer coalescing

```swift
let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
timer.schedule(deadline: .now(), repeating: .seconds(1), leeway: .milliseconds(100))
timer.setEventHandler { [weak self] in self?.pollWindowList() }
timer.resume()
```

### Timestamp-based timing, not tick counting

Do not accumulate elapsed time from timer ticks. Store `Date` timestamps for each window's last-active time, and compute age on each poll. This handles sleep, App Nap throttling, and missed ticks correctly.

Sources:
- [Apple Energy Efficiency Guide — Timers](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/Timers.html)
- [Apple Energy Efficiency Guide — App Nap](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html)
- [ai-buddy issue #1047 — polling Hz measurements](https://github.com/omesser/ai-buddy/issues/1047)
- [ai-buddy issue #427 — benchmark spec](https://github.com/omesser/ai-buddy/issues/427)
- [notchline issue #68 — polling during display sleep](https://github.com/soondubu137/notchline/issues/68)
