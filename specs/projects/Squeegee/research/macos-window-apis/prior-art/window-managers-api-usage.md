# Window Managers: API Usage for Window Identity and Focus Tracking

Deep reference on how open-source macOS window managers enumerate windows, track focus, and identify windows. These apps solve adjacent problems to Squeegee and their API usage is directly relevant.

---

## AltTab (lwouis/alt-tab-macos)

**Repo:** [github.com/lwouis/alt-tab-macos](https://github.com/lwouis/alt-tab-macos) -- 16.3k stars, GPL-3.0, Swift.

**What it does:** Windows-style Alt-Tab window switcher with live thumbnails. Must enumerate all windows across all apps, track focus order, and switch to a specific window.

### Window Enumeration

AltTab uses a two-source approach:

1. **`CGWindowListCopyWindowInfo`** -- returns on-screen windows in z-order (front-to-back). Provides `kCGWindowNumber` (CGWindowID), owner PID, bounds, layer, `kCGWindowIsOnscreen`. Returns 100+ entries including shadows, fill services, widgets -- requires filtering.

2. **`AXUIElement` per app** -- `kAXWindowsAttribute` on each app's AXUIElement. Returns minimized windows that CGWindowList misses.

### Bridging CG and AX: `_AXUIElementGetWindow`

The critical link between CGWindowList and AXUIElement is the private SPI `_AXUIElementGetWindow(AXUIElementRef, &CGWindowID)`. This is in the ApplicationServices framework, not a public API. It has been stable since macOS 10.9. **Every major macOS window manager depends on it** (AltTab, Rectangle, yabai, Amethyst, Hammerspoon).

In AltTab, this lives in `Sources/AltTabCore/WindowList.swift`. The app resolves it at runtime -- if the symbol is missing, it falls back to matching by title and position (less reliable).

### Focus Tracking (MRU Order)

AltTab maintains most-recently-used window order via:

- **`NSWorkspace.didActivateApplicationNotification`** -- fires when the frontmost app changes. No special permission needed.
- **`AXObserver` per app** -- subscribes to `kAXFocusedWindowChangedNotification` (later changed to `kAXMainWindowChangedNotification` in a bug fix) and `kAXFocusedUIElementChangedNotification`. Requires Accessibility permission.

Between invocations, these events schedule a debounced, rate-limited background re-gather so the cached window list is never stale.

**Bug: background apps corrupting MRU order.** `kAXFocusedWindowChanged` from non-frontmost apps (Electron/Chromium window churn, windows closed by background jobs) promoted their windows to the front while the user worked elsewhere. Fix: accept promotions only from the frontmost app. ([Source: sergio-farfan fork](https://github.com/sergio-farfan/alttab-macos))

**Bug: observer registration failures.** `AXObserverAddNotification` failures (Accessibility not yet granted, app's AX server not up) were stored as if they succeeded and never retried. Fix: observers register only on success, reinstall when Accessibility is granted, retry for just-launched apps, self-heal on first activation.

### Tab Detection

AltTab subscribes to `kAXFocusedUIElementChangedNotification` on every app. On trigger, it queries the app's windows. Limitation: tabs created before AltTab launches cannot be detected.

### Windows on Other Spaces

Public AX API only reports windows on the current Space. AltTab uses `_AXUIElementCreateWithRemoteToken` SPI to find off-Space windows, cached and refreshed on Space changes.

### Window Focusing (Bringing a Window Forward)

Uses `_SLPSSetFrontProcessWithOptions` (private SkyLight framework) plus a synthetic make-key event plus an AX raise. Loaded with `dlopen`; falls back to public APIs if the symbol is missing.

Also uses `CGSSetSymbolicHotKeyEnabled` to temporarily disable the system Cmd-Tab switcher while AltTab's panel is open.

### Thumbnails

macOS 14+: ScreenCaptureKit for async captures. macOS 13: `CGWindowListCreateImage`. If Screen Recording permission is denied, shows app icons instead.

### Permissions Required

- **Accessibility** -- required for AXUIElement queries and AXObserver focus tracking.
- **Screen Recording** -- optional, for live thumbnails. Without it, app icons are shown.
- No SIP disable needed.

**Sources:**
- [GitHub repo](https://github.com/lwouis/alt-tab-macos)
- [sergio-farfan fork (bug fixes)](https://github.com/sergio-farfan/alttab-macos)
- [mac-taskbar PR #2 (AXObserver pattern)](https://github.com/MeKo-Christian/mac-taskbar/pull/2)
- [mac-taskbar PR #6 (CGWindowID keying)](https://github.com/MeKo-Christian/mac-taskbar/pull/6)

---

## yabai (koekeishiya/yabai)

**Repo:** [github.com/koekeishiya/yabai](https://github.com/koekeishiya/yabai) -- C, MIT license. Supports macOS 11.0+ through 26.0+.

**What it does:** Tiling window manager with CLI control. Manages window positions, sizes, spaces, and displays.

### Window Enumeration

Uses both `CGWindowListCopyWindowInfo` and AXUIElement (`kAXWindowsAttribute`). The macOS API does not return AXUIElementRef of windows on inactive spaces -- yabai brute-forces the element_id to create the AXUIElementRef as a workaround.

### Private APIs Used

yabai is the heaviest user of private APIs among these tools:

- **`_AXUIElementGetWindow`** -- bridge CGWindowID to AXUIElement
- **SkyLight framework** -- `SLSMainConnectionID`, `SLSNewConnection`, `SLSRegisterConnectionNotifyProc`, `SLSConnectionGetPID`, `_SLPSGetFrontProcess`, `SLSFindWindowAndOwner`, `SLEventPostToPid`, and many more
- **Dock scripting addition** -- for moving windows between spaces, creating/destroying spaces. Requires **partial SIP disable** to inject into Dock.app.

### Permissions

- **Accessibility** -- required, requested on launch
- **Screen Recording** -- for window animations
- **Partial SIP disable** -- for advanced features (space management, focus-follows-space)

### Relevance to Squeegee

yabai's private API usage is instructive but too aggressive for Squeegee's needs. Squeegee does not need to move windows between spaces or control window ordering. The `_AXUIElementGetWindow` bridge and frontmost-app detection are the relevant patterns. yabai's SIP disable requirement is a non-starter for a user-friendly utility.

**Sources:**
- [GitHub wiki](https://github.com/koekeishiya/yabai/wiki)
- [Source: window_manager.c](https://github.com/koekeishiya/yabai/blob/master/src/window_manager.c)
- [cua.ai blog on SkyLight internals](https://cua.ai/blog/inside-macos-window-internals)

---

## Amethyst (ianyh/Amethyst)

**Repo:** [github.com/ianyh/Amethyst](https://github.com/ianyh/Amethyst) -- Swift, free. Tiling window manager modeled after xmonad.

### Architecture

Uses a library called **Silica** (vendored at `Packages/Silica`) that wraps Accessibility and private CoreGraphics APIs. The Silica layer provides typed objects: `SIWindow`, `SIApplication`, `SISpace`.

All CGS parsing lives in Silica; the Swift app side only sees typed objects and window IDs. Three validators enforce safety: `ConfigurationValidator`, `FrameValidator`, `LayoutValidator`.

### API Usage

- **AXUIElement** -- for window queries (`kAXPositionAttribute`, `kAXSizeAttribute`, `kAXMinimizedAttribute`, `kAXFullscreenAttribute`) and setting window properties
- **`_AXUIElementGetWindow`** -- in the Silica package, for bridging CGWindowID to AXUIElement
- **Private CGS calls** -- for Space queries (`managedSpaceID`, on-screen window-ID queries)

### Permissions

- **Accessibility** -- required, no SIP disable needed
- No Screen Recording needed

**Sources:**
- [GitHub repo](https://github.com/ianyh/Amethyst)
- [Vendored Silica fork details](https://github.com/mgabs/Amethyst)

---

## Rectangle (rxhanson/Rectangle)

**Repo:** [github.com/rxhanson/Rectangle](https://github.com/rxhanson/Rectangle) -- Swift, MIT license. Snap-to-position window manager.

### API Usage

- **AXUIElement** exclusively for window positioning. No private APIs documented.
- Uses `_AXUIElementGetWindow` for CGWindowID correlation (confirmed by cross-project searches).
- Tracks each window's original position for restore-after-snap.
- No telemetry, no network requests, tiny footprint.

### Permissions

- **Accessibility** -- required, no SIP, no Screen Recording

**Sources:**
- [GitHub repo](https://github.com/rxhanson/Rectangle)
- [macoswm.com listing](https://macoswm.com/wm/rectangle)

---

## Summary: Common API Patterns Across Window Managers

| API | Used by | Permission | Purpose |
|-----|---------|------------|---------|
| `CGWindowListCopyWindowInfo` | All four | None (titles need Screen Recording on macOS 15+) | List on-screen windows with z-order |
| `AXUIElement` (`kAXWindowsAttribute`) | All four | Accessibility | List windows per app (incl. minimized) |
| `_AXUIElementGetWindow` | All four | Accessibility (private SPI) | Bridge CGWindowID <-> AXUIElement |
| `NSWorkspace.didActivateApplicationNotification` | AltTab, (inferred: Rectangle) | None | Frontmost app changes |
| `AXObserver` + `kAXFocusedWindowChangedNotification` | AltTab, Amethyst | Accessibility | Track which window is focused within an app |
| `AXObserver` + `kAXWindowCreatedNotification` | AltTab (mac-taskbar) | Accessibility | Detect new windows |
| `AXObserver` + `kAXUIElementDestroyedNotification` | AltTab (mac-taskbar) | Accessibility | Detect window close |
| SkyLight / CGS private APIs | yabai, AltTab (focusing) | Varies; some need SIP | Space management, window focusing |
| ScreenCaptureKit / `CGWindowListCreateImage` | AltTab | Screen Recording | Thumbnails |

### Key Takeaway for Squeegee

The stable, well-tested pattern is:
1. **`CGWindowListCopyWindowInfo`** for initial window discovery (no permission needed for IDs and bounds; titles need Screen Recording on macOS 15+)
2. **`AXUIElement`** for per-app window lists and the close button (`kAXCloseButtonAttribute` + `AXUIElementPerformAction(kAXPressAction)`)
3. **`_AXUIElementGetWindow`** to bridge between the two (private but stable since 10.9, used by every major window manager)
4. **`NSWorkspace.didActivateApplicationNotification`** for frontmost-app tracking (free, no permission)
5. **`AXObserver`** for per-window focus tracking if finer granularity is needed (Accessibility permission)

This is the same stack Quitter uses for app-level tracking (minus Accessibility), extended to window-level with AXUIElement and AXObserver.
