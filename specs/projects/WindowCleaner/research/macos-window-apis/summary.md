# Research: macOS Window APIs for WindowCleaner

## Bottom Line

WindowCleaner can list, track, and close individual windows of other apps on macOS. The core API stack is well-proven: `CGWindowListCopyWindowInfo` for enumeration (no permission), the Accessibility API for closing windows and reading titles (one-time Accessibility permission), and the private `_AXUIElementGetWindow` to bridge the two (stable since macOS 10.9, used by every major window manager). **Accessibility is the only TCC permission required**, and it does not re-prompt. Screen Recording is avoidable. The App Store is not an option -- sandboxed apps cannot use Accessibility -- so direct distribution with Developer ID + notarization is the correct path. Activity tracking works at two tiers: app-level foreground tracking needs no permission at all; per-window focus tracking needs the same Accessibility permission already required for closing. No existing app closes individual idle windows -- every competitor operates at the app level (quit or hide the whole app). WindowCleaner's per-window close is a genuinely novel feature, and no existing tool is a substitute.

## Key Findings

- **Accessibility is the single required permission, and it is sufficient.** It enables window closing (`kAXCloseButtonAttribute` + `AXPressAction`), window title reading (`kAXTitleAttribute`), per-window focus tracking (`AXObserver`), and the CGWindowID bridge (`_AXUIElementGetWindow`). It prompts once and does not re-prompt. Screen Recording (which re-prompts monthly on macOS 15+) is avoidable because titles come from AX, not from `CGWindowListCopyWindowInfo`. ([Permissions](./permissions-sandbox-distribution/summary.md), [Window Enumeration](./window-enumeration-identity-closing/summary.md))

- **Activity can be tracked well, and the no-permission tier is useful for the close timer -- but not for closing.** `NSWorkspace.didActivateApplicationNotification` (no permission) fires on every frontmost-app change. `CGWindowListCopyWindowInfo` polling at 1 Hz (no permission, 2-4 ms per call) gives z-order and position changes. `CGEventSource.secondsSinceLastEventType` (no permission) detects user idle time. Together these support the user's "never entered foreground" heuristic reliably. The gap without Accessibility is per-window focus in multi-window apps -- the conservative fallback is to reset the timer for all windows of the frontmost app. Since Accessibility is already mandatory for closing windows, per-window focus tracking comes for free. ([Activity Signals](./activity-signals/summary.md))

- **`CGWindowID` is a stable identity key for a window's lifetime.** It does not change across moves, resizes, Space changes, full-screen, or minimize. No API provides window creation time -- infer "opened at" by recording first-observation timestamps via polling plus `kAXWindowCreatedNotification`. Tabs are not separate windows in `CGWindowListCopyWindowInfo`. ([Window Enumeration](./window-enumeration-identity-closing/summary.md))

- **Close (one window) and quit (whole app) are cleanly separated.** `AXPressAction` on the close button closes one window, triggers save dialogs, and leaves the app running. `NSRunningApplication.terminate()` quits the entire app. AppleScript `close window` works but adds per-target-app Automation permission prompts -- avoid it. ([Window Enumeration](./window-enumeration-identity-closing/summary.md))

- **App Store is blocked; Developer ID is standard for this category.** The App Sandbox prohibits the Accessibility API. Existing App Store window managers (Magnet, BetterSnapTool) are grandfathered. Every comparable tool (Quitter, AutoQuit, AltTab, yabai) distributes outside the App Store. Developer ID + notarization is straightforward. ([Permissions](./permissions-sandbox-distribution/summary.md), [Prior Art](./prior-art/summary.md))

- **No existing app does per-window idle close.** Quitter, AutoQuit, SwiftQuit, MacQuit, SmartQuit, and Hocus Focus all operate at the app level. AutoQuit is the strongest competitor (per-app rules, grace-period notifications, busy-app detection) but cannot close individual windows. The open-source window managers (AltTab, yabai, Amethyst, Rectangle) validate the API stack but do not implement idle timers. ([Prior Art](./prior-art/summary.md))

## Implications

**Architecture:** The tiered permission model simplifies to a single tier for v1. Since Accessibility is mandatory for the core feature (closing windows), and since it also unlocks per-window focus tracking, there is no reason to ship a "no-permission mode." Request Accessibility on first launch and gate all functionality behind it.

**Activity tracking design:** Use `NSWorkspace` notifications (no-cost, event-driven) for app-level foreground tracking plus `AXObserver` per-app for per-window focus. Supplement with 1 Hz `CGWindowListCopyWindowInfo` polling for position/visibility changes and `CGEventSource` for user idle detection. Store `Date` timestamps per window, not accumulated ticks, to survive sleep and App Nap.

**Distribution:** Developer ID + notarization, distributed as `.dmg`. Use team signing during development to keep Accessibility grants stable across rebuilds. Plan for Sparkle or equivalent for auto-updates.

**Edge cases from prior art:** SwiftQuit found that apps temporarily close their main window during loading (e.g., Excel), causing premature action. AltTab found that background apps can corrupt MRU order. WindowCleaner should debounce close actions with a minimum observation window and accept focus promotions only from the frontmost app.

## Conflicts and Uncertainty

**Permission tier design tension (resolved).** The Activity Signals subtopic proposed a "no-permission tier" with free signals, while Window Enumeration and Permissions both state Accessibility is required for closing. These are consistent: you *can* track activity without Accessibility, but you *cannot* close windows without it. Since closing is the core feature, the no-permission tier has no standalone value. The free signals remain useful as part of the activity tracking stack alongside AXObserver.

**`kCGWindowIsOnscreen` reliability.** The Activity Signals subtopic reports bugs on macOS 14-15 where on-screen windows are missing from on-screen-only results. Workaround: query both all-windows and on-screen-only result sets and compare.

**macOS 26 (Tahoe) unknowns.** No subtopic found Apple documentation on TCC changes in macOS 26. `_AXUIElementGetWindow` has not been explicitly verified on macOS 26, though no breakage has been reported. Screen Recording re-prompts may have shifted from monthly to weekly on Tahoe (one source), which reinforces the decision to avoid that permission.

## Gaps

- **`CGWindowID` reuse policy is undocumented.** The uint32 counter space makes reuse negligible in practice, but no Apple source confirms the guarantee. A collision would cause a misidentified window. Mitigation: pair CGWindowID with owner PID and first-seen timestamp.
- **`_AXUIElementGetWindow` on macOS 26 is unverified.** Current tools run on it without reported issues, but no source explicitly tested macOS 26. Risk is low given 17 years of stability.
- **AXPress behavior on unresponsive apps is untested.** `AXUIElementPerformAction` has a configurable timeout (default 10s). What the user sees when it times out needs testing on real hardware.
- **App Nap throttling for menu bar apps is imprecise.** Apple documents that timers are throttled but not by how much. Acceptable for hour-scale timers, but exact behavior needs testing.
- **Sparkle auto-update integration was not researched.** Standard for Developer ID distribution but out of scope for this research.

## Subtopics

- [Window Enumeration, Identity, and Closing](./window-enumeration-identity-closing/summary.md) -- APIs for listing, identifying, and closing windows; CGWindowID stability; private bridge API; close vs. quit mechanics
- [Activity Signals](./activity-signals/summary.md) -- Signals that indicate window activity, permission requirements per signal, polling vs. notifications, heuristic evaluation
- [Permissions, Sandbox, and Distribution](./permissions-sandbox-distribution/summary.md) -- Accessibility as the sole permission; Screen Recording avoidance; App Store blocked; Developer ID + notarization; menu bar app setup
- [Prior Art](./prior-art/summary.md) -- Existing idle-quit and window-management apps; API patterns from open-source tools; build-vs-buy recommendation (AutoQuit is closest but lacks per-window close)
