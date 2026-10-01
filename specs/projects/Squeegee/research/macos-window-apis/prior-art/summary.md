# Prior Art

## Bottom Line

No existing macOS app closes individual windows after idle time -- every tool in this space (Quitter, AutoQuit, SwiftQuit, MacQuit, SmartQuit, Hocus Focus) operates at the app level, either quitting the whole app or hiding it. Squeegee's per-window close is genuinely novel. The closest competitor is AutoQuit (open source, GPL-3, actively maintained), which quits idle apps with per-app rules, grace-period notifications, and busy-app detection, but cannot touch individual windows. The open-source window managers (AltTab, yabai, Amethyst, Rectangle) demonstrate a stable, well-tested API stack for window enumeration and focus tracking: `CGWindowListCopyWindowInfo` + `AXUIElement` + the private `_AXUIElementGetWindow` bridge + `NSWorkspace.didActivateApplicationNotification` + `AXObserver` for per-window focus events. All four depend on `_AXUIElementGetWindow` (private but stable since macOS 10.9) and all require Accessibility permission.

## Key Findings

- **No per-window idle-close tool exists.** Every idle-quit app (Quitter, AutoQuit, MacQuit, SmartQuit) uses `NSRunningApplication.terminate()` or `.hide()` -- app-level operations. None uses the Accessibility close-button pattern (`kAXCloseButtonAttribute` + `AXUIElementPerformAction`) that would enable per-window close. ([idle-quit-apps.md](./idle-quit-apps.md))

- **Quitter (Marco Arment) is the best-known but most limited.** Free, closed source, version 1.0 (build 108), effectively unmaintained since ~2021. Still works on macOS 15 Sequoia. Cannot be sandboxed. Tracks inactivity by monitoring frontmost app via `NSWorkspace`. No notification before quitting, no "since opened" mode. ([marco.org/apps](https://marco.org/apps))

- **AutoQuit is the strongest existing idle-quit app.** Open source (GPL-3), Swift/SwiftUI, actively maintained (v1.4.3, 2026). Default 8-hour timeout, per-app rules, 60-second grace period with notification. Skips busy apps (media, downloads, wake locks). Shows live countdown and memory usage. App-level only. ([GitHub](https://github.com/treelazy888/AutoQuit))

- **`_AXUIElementGetWindow` is the universal private API.** AltTab, yabai, Amethyst, and Rectangle all use this undocumented SPI to bridge CGWindowID and AXUIElement. Stable since macOS 10.9. AltTab resolves it at runtime and falls back to title+position matching if missing. This is safe for Squeegee to adopt. ([window-managers-api-usage.md](./window-managers-api-usage.md))

- **AltTab's focus-tracking architecture is the best reference.** Maintains MRU window order via `NSWorkspace.didActivateApplicationNotification` (no permission) plus per-app `AXObserver` callbacks for `kAXFocusedWindowChangedNotification` (Accessibility permission). Key bugs found and fixed: background apps corrupting MRU order (fix: accept promotions only from frontmost app), observer registration failures silently dropped (fix: register only on success, retry). ([window-managers-api-usage.md](./window-managers-api-usage.md))

- **SwiftQuit illustrates per-window edge cases.** Apps that temporarily close their main window (e.g., Excel loading a file) get insta-quit. Some apps retain hidden controller windows after visible windows close, causing false negatives. These edge cases apply to Squeegee's window-close feature. ([GitHub issue #3](https://github.com/onebadidea/swiftquit/issues/3))

- **No "apps safe to quit" list exists.** macOS state restoration (Resume, since 10.7) is per-app and varies. There is no published heuristic or list. Squeegee's per-window close via AX close button is safer than app-level quit because it triggers the same code path as the user clicking the red button. ([build-vs-buy.md](./build-vs-buy.md))

- **App Store distribution is not viable.** Quitter, SwiftQuit, AutoQuit, and Hocus Focus all distribute outside the App Store because `NSRunningApplication.terminate()` and Accessibility-based window control cannot work in the App Sandbox. HazeOver and MacQuit are on the App Store, but HazeOver only dims (no terminate), and MacQuit's idle-quit scope within the sandbox is unclear. Squeegee will need Developer ID + notarization. (Detailed analysis in the Permissions subtopic.)

## Details

- [idle-quit-apps.md](./idle-quit-apps.md) -- Detailed profiles of 8 idle-quit/auto-close apps: Quitter, AutoQuit, SwiftQuit, MacQuit, SmartQuit, Hocus Focus, HazeOver, and minor tools. What each does, APIs used, permissions, distribution, and known problems.
- [window-managers-api-usage.md](./window-managers-api-usage.md) -- How AltTab, yabai, Amethyst, and Rectangle enumerate windows and track focus. Exact API usage with source references. Common patterns table. Key bugs and fixes from AltTab's AXObserver implementation.
- [build-vs-buy.md](./build-vs-buy.md) -- Feature matrix comparing all candidates against Squeegee's planned features. Gap analysis and "next best alternative" recommendation. macOS state restoration notes.

## Open Questions / Gaps

- **Quitter source code is closed.** The inactivity-detection mechanism is inferred from behavior and third-party rewrites, not from reading the actual code. High confidence it uses `NSWorkspace.didActivateApplicationNotification` + `NSRunningApplication.terminate()/hide()`, but cannot verify.
- **MacQuit's "AIR algorithm" is undocumented.** Cannot determine how it differs from simple frontmost-app tracking.
- **SmartQuit details are thin.** Gumroad page did not load full details. The app combines last-window-quit and idle-quit, but the implementation is unknown.
- **Medium article on "Rewriting Quitter"** returned HTTP 403. Could not verify the implementation details described in that rewrite.

## Sources

- [Quitter - Marco.org (2016-05-02)](https://marco.org/2016/05/02/quitter) -- Original announcement, still the definitive description
- [Quitter - marco.org/apps](https://marco.org/apps) -- Download page, version info
- [AutoQuit - GitHub](https://github.com/treelazy888/AutoQuit) -- Open source idle-quit app, actively maintained
- [SwiftQuit - GitHub](https://github.com/onebadidea/swiftquit) -- Open source last-window-quit, GPL-3
- [AltTab - GitHub](https://github.com/lwouis/alt-tab-macos) -- 16.3k stars, reference implementation for window enumeration and focus tracking
- [yabai wiki](https://github.com/koekeishiya/yabai/wiki) -- Private API documentation and SkyLight usage
- [Amethyst - GitHub](https://github.com/ianyh/Amethyst) -- Silica wrapper for AXUIElement + CGS
- [Rectangle - GitHub](https://github.com/rxhanson/Rectangle) -- Minimal AXUIElement-only window manager
- [MPU Talk: Alternative to Quitter](https://talk.macpowerusers.com/t/alternative-to-quitter-app/22055) -- User discussion of Quitter problems and alternatives
- [How-To Geek: Quitter walkthrough](https://www.howtogeek.com/268963/automatically-close-or-hide-idle-applications-on-your-mac-with-quitter/) -- Detailed usage guide
- [Apple Support: Prevent apps and windows from reopening](https://support.apple.com/en-us/102318) -- macOS state restoration behavior
- [cua.ai: Inside macOS window internals](https://cua.ai/blog/inside-macos-window-internals) -- SkyLight framework research
- [HazeOver - Daring Fireball review (2026-03)](https://daringfireball.net/2026/03/hazeover) -- Confirms Accessibility-only approach for window tracking

---

## Next Best Alternative

**AutoQuit** is the single best existing app for idle-app management. It covers per-app rules with configurable timeouts (30 min to 48 hours), grace-period notifications before quitting, busy-app detection (media, downloads, wake locks), and a live countdown UI. It is open source (GPL-3), actively maintained, and free.

**What it lacks:** Per-window close (the core Squeegee feature), "since opened" timer mode, close-window-without-quitting action, and recent-closures history.

**Verdict:** AutoQuit is not good enough to skip the build. Squeegee's core value -- closing individual windows rather than quitting entire apps -- does not exist in any shipping product. If the user's actual need is "quit idle apps after N hours," AutoQuit already solves that. But if the need is "close stale Finder/Preview/QuickTime windows without losing other windows in those apps," nothing on the market does this.
