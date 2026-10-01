# Build vs. Buy: Squeegee Feature Gap Analysis

Comparison of existing macOS apps against Squeegee's planned feature set. The question: can an existing app replace the need to build Squeegee?

---

## Squeegee's Planned Feature Set

1. **Per-window close** -- close individual windows of an app without quitting the entire app
2. **Per-app rules** -- different timeout and action per app
3. **"Since opened" vs. "since last active"** -- two timer modes
4. **Close window vs. quit app** -- choose the action per rule
5. **Menu bar UI** -- shows upcoming closures and recent closures
6. **Configurable timeout** -- hours-scale (not just minutes)

---

## Feature Matrix

| Feature | Quitter | AutoQuit | SwiftQuit | SmartQuit | MacQuit | Hocus Focus |
|---------|---------|----------|-----------|-----------|---------|-------------|
| **Per-window close** | No | No | No | No | No | No |
| **Per-app rules** | Yes | Yes | Yes | Yes | Yes | Yes |
| **"Since opened" timer** | No | No | N/A | No | No | No |
| **"Since last active" timer** | Yes | Yes | N/A | Yes | Yes | Yes |
| **Close window (not quit)** | No | No | No | No | No | Hide only |
| **Quit app** | Yes | Yes | Yes | Yes | Yes | No |
| **Hide app** | Yes | No | No | No | No | Yes |
| **Menu bar UI** | Yes | Yes | Yes | Yes | Yes | Yes |
| **Upcoming closures visible** | No | Yes (countdown) | N/A | Yes | No | No |
| **Recent closures visible** | No | No | No | No | No | No |
| **Hours-scale timeout** | Yes (minutes) | Yes (30m-48h) | N/A | Yes | Yes | No (max 10m) |
| **Grace period / notification** | No | Yes (60s) | No | No | No | No |
| **Busy-app detection** | No | Yes | No | No | No | No |
| **Open source** | No | Yes (GPL-3) | Yes (GPL-3) | No | No | No |
| **Actively maintained** | Barely | Yes | Barely | Unknown | Yes | Discontinued |
| **Price** | Free | Free | Free | $4 | $4.99 | Free |

---

## Analysis

### The critical gap: no existing app closes individual windows

Every app in this space operates at the **app level** -- quit the whole app or hide it. None of them can close a single window within an app that has multiple windows open. This is Squeegee's core differentiator.

The technical reason is straightforward: Quitter and its derivatives use `NSRunningApplication.terminate()` or `.hide()`, which are app-level operations. Closing a specific window requires the Accessibility API (`kAXCloseButtonAttribute` + `AXUIElementPerformAction(kAXPressAction)`) or AppleScript/Apple Events (`close window N`), which these apps do not use.

### "Since opened" mode does not exist

No existing app tracks when a window was opened. All existing idle-quit apps measure inactivity from "last time the app was in the foreground." Squeegee's planned "since opened" mode (close windows that have been open for more than N hours regardless of activity) is novel in this space.

### AutoQuit is the closest competitor

AutoQuit covers the most ground:
- Per-app rules with configurable timeouts (30m to 48h)
- Grace period with notification before quitting
- Busy-app detection (skips media, downloads, wake locks)
- Live countdown timers in the UI
- Open source and actively maintained

**What AutoQuit lacks vs. Squeegee:**
- Per-window close (the big one)
- "Since opened" timer mode
- Close-window-without-quitting action
- Recent closures history

### Quitter is the most well-known but least capable

Quitter has brand recognition (Marco Arment) and simplicity, but it is the most limited: no notification before action, no countdown, no busy-app detection, no per-window control, and effectively unmaintained.

---

## "Next Best Alternative" Recommendation

**Best existing app: AutoQuit**

- **What it covers:** Per-app idle quit with configurable timeouts, grace-period notifications, busy-app detection, live countdown UI, memory monitoring. Open source (GPL-3), actively maintained, free.
- **What it lacks:** Per-window close (cannot close one Finder window), "since opened" timer mode, close-window-without-quit action, recent-closures log.
- **Is it good enough to skip the build?** No. Squeegee's core value proposition -- closing individual windows rather than quitting entire apps -- is not available in any existing tool. If the user's primary annoyance is "I have 20 Finder windows cluttering my desktop," no existing app solves this. AutoQuit would quit Finder entirely, losing all 20 windows. If the user's need is only "quit idle apps after N hours," AutoQuit already does this well and building Squeegee would not add enough value to justify the effort. The decision hinges on whether per-window control is the real need.

---

## macOS State Restoration: What Happens After Quit

A related concern: if Squeegee quits an app, will the user lose state?

- macOS has a Resume feature (since 10.7 Lion) that restores windows on relaunch for Cocoa apps.
- The system setting "Close windows when quitting an application" controls whether apps restore previous windows on relaunch. If this is **off** (the default), most apps will restore their windows.
- Some apps (Safari, Chrome, VS Code) manage their own session restoration independently.
- There is **no published list** of "apps safe to quit" -- behavior varies per app based on whether it implements Apple's state restoration APIs.
- Holding Shift while opening an app suppresses window restoration for that launch.
- Squeegee's per-window close (via AX close button) is actually **safer** than quitting: it triggers the same code path as the user clicking the red button, which gives the app a chance to show "unsaved changes" dialogs and save state per window.

**Sources:**
- [Apple Support: Prevent apps and windows from reopening](https://support.apple.com/en-us/102318)
- [BRNSFT: Mac Session Restore guide](https://www.brnsft.com/blog/mac-session-restore-how-to-bring-back-every-app-tab-and-window-exactly-as-you-left-it)
