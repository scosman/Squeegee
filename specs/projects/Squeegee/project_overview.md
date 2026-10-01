---
status: complete
---

# Squeegee

A "window tidier" for macOS.

## Features

- **Core feature: close windows after N hours**
  - Includes powerful per-app settings (and global defaults for non-custom apps):
    - Enabled
    - Time: N hours
    - Time since: active or opened (see "active" concept below)
    - Close mode: close window vs. quit app (default is close window)
  - Note: we are WINDOW based, not process based.
- **Good suggestions baked in.** Focus on cleaning windows that you can safely re-open. Nice onboarding to get you more defaults: it scans the apps you have and suggests a set. Examples:
  - Finder: close windows after 6 hours
  - Photos app: safe to close, uses lots of resources
  - Video playback apps: QuickTime, VLC — use resources, no data loss potential
  - Messaging apps that will re-notify: Messages, maybe more
  - Apps that can just re-open (have background mode/tray mode, or no state): 1Password, Granola, etc.
- **Great Mac native UI**
  - SwiftUI, nice design, 100% native UI, zero HTML.
- **Tray icon / app**
  - The app needs to run in the background.
  - It has a simple tray (menu bar) app showing upcoming closures and recent closures.
  - Hiding the tray icon is an option in app settings.
- **P2: Close history**
  - See what was closed in the UI.
- **P2: Window "activity" tracking (TBD)**
  - Can we detect "active" windows? The closing timer would ideally be from "last active", not "opened".
  - Never entered foreground, or never entered foreground for 5s+ — pretty good.
  - Moved position (weak signal).
  - Need to investigate what we can do here.
- **P2: In-app management UI**
  - See the oldest active windows, close them.
- **P2 (not in V1): Safari tab support**
  - Same idea, for Safari tabs.

## Technical Direction

- https://github.com/scosman/Biscotti is another macOS app of mine, built with the /spec skill, and is quite good. Use it for technical inspiration. Build out the technical plan in the functional spec/architecture, not here. Ideas to carry over:
  - All app core logic is a library, highly tested. The SwiftUI wrapper is a thin wrapper. 99% of work can happen with agents/unit tests; minimal UI testing needed.
  - "ManualTestApp" concept.
  - The CI setup.
  - Potentially more.
- Distribution: I have an Apple Developer account. Okay with signed self distribution and/or the App Store.

## Open Questions

- Research phase on window APIs: can we track "active" well, and without special permissions?
