# Permissions, Sandbox, and Distribution

## Bottom Line

Squeegee needs exactly one TCC permission: **Accessibility**. This single permission covers window enumeration, title reading, and window closing via `AXUIElement`. Screen Recording permission is avoidable — window titles come from the Accessibility API (`kAXTitleAttribute`), not `CGWindowListCopyWindowInfo` (`kCGWindowName`), so the painful monthly re-prompts introduced in macOS 15 Sequoia do not apply. The App Store is **not an option** — sandboxed apps cannot use the Accessibility API, and Apple actively rejects new apps that try. **Direct distribution with Developer ID signing + notarization** is the correct and standard path for this category of app. For background operation, SwiftUI's `MenuBarExtra` with `LSUIElement` and `SMAppService` for launch-at-login are the modern, well-documented approach.

## Key Findings

- **Accessibility is the only required permission** — `AXIsProcessTrustedWithOptions` prompts the user once; poll `AXIsProcessTrusted()` on a timer to detect the grant without requiring a restart. Validate with a real AX call, not just the boolean, to catch stale TCC entries. ([accessibility-permission.md](./accessibility-permission.md))

- **Screen Recording is avoidable and should be avoided** — `CGWindowListCopyWindowInfo` redacts `kCGWindowName` without Screen Recording (since macOS 10.15 Catalina), but the Accessibility API provides window titles without it. macOS 15 Sequoia introduced monthly re-prompts for Screen Recording that would degrade UX significantly. The Persistent Content Capture entitlement that exempts apps from these prompts is restricted to VNC apps. ([screen-recording-permission.md](./screen-recording-permission.md)) Sources: [9to5Mac (Aug 2024)](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/), [Michael Tsai (Aug 2024)](https://mjtsai.com/blog/2024/08/08/sequoia-screen-recording-prompts-and-the-persistent-content-capture-entitlement/)

- **App Store is blocked for this app category** — The App Sandbox prohibits the Accessibility API. `com.apple.security.accessibility` is not a valid macOS entitlement and is rejected by App Store Connect. Existing window managers on the App Store (Magnet, BetterSnapTool) are grandfathered from before sandboxing was mandatory. ([sandbox-and-distribution.md](./sandbox-and-distribution.md)) Sources: [Apple Developer Forums (Thread #707680)](https://developer.apple.com/forums/thread/707680), [alinpanaitiu.com](https://alinpanaitiu.com/blog/apps-outside-app-store/)

- **Developer ID + notarization is straightforward** — Sign with Developer ID Application certificate, notarize via Xcode (automated), distribute as `.dmg`. Hardened Runtime is required for notarization but does not restrict Accessibility use. The developer already has an Apple Developer account. ([sandbox-and-distribution.md](./sandbox-and-distribution.md)) Source: [Apple Developer — Distributing software on macOS](https://developer.apple.com/macos/distribution/)

- **Code signing stability matters for TCC** — Ad-hoc signed builds lose Accessibility permission on every rebuild because TCC ties grants to `cdhash`. Developer ID signing uses `TeamIdentifier`, which stays stable across updates. Development builds should use team signing, not "Sign to Run Locally." ([accessibility-permission.md](./accessibility-permission.md)) Sources: [pathorsAI/parley Issue #75](https://github.com/pathorsAI/parley/issues/75), [NousResearch/hermes-agent Issue #49110](https://github.com/NousResearch/hermes-agent/issues/49110)

- **Automation/Apple Events permission is avoidable** — If Squeegee uses the Accessibility API's close button (`kAXCloseButtonAttribute` + `AXUIElementPerformAction`) instead of AppleScript to close windows, it avoids per-target-app Automation prompts entirely. If Apple Events are needed as a fallback, each target app triggers a one-time prompt that is remembered permanently. ([sandbox-and-distribution.md](./sandbox-and-distribution.md))

- **Menu bar app setup is well-supported** — `MenuBarExtra` (macOS 13+) with `.menuBarExtraStyle(.window)`, `LSUIElement = YES` in Info.plist to hide the Dock icon, and `SMAppService.mainApp.register()` for launch at login. Keep the menu bar icon always visible for v1. ([menu-bar-app-setup.md](./menu-bar-app-setup.md)) Sources: [Nil Coalescing (Feb 2025)](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/), [Nil Coalescing (Jan 2025)](https://nilcoalescing.com/blog/LaunchAtLoginSetting/)

## Details

- [accessibility-permission.md](./accessibility-permission.md) — How to check, prompt, and poll for Accessibility permission; stale TCC cache detection; code signing impact on permission persistence; configuration (Info.plist keys). Read when implementing the permission onboarding flow.
- [screen-recording-permission.md](./screen-recording-permission.md) — What `CGWindowListCopyWindowInfo` returns without Screen Recording; the macOS 15 monthly re-prompt timeline; the Persistent Content Capture entitlement; why Squeegee should not request this permission. Read when deciding the window-title strategy.
- [sandbox-and-distribution.md](./sandbox-and-distribution.md) — Why the App Store is blocked; what Developer ID + notarization involves; App Store vs direct distribution trade-offs; Automation/Apple Events permission model. Read when setting up the distribution pipeline.
- [menu-bar-app-setup.md](./menu-bar-app-setup.md) — `MenuBarExtra` implementation; `LSUIElement`; `SMAppService` for launch at login; the hide-menu-bar-icon problem and recovery strategies. Read when building the app shell.

## Open Questions / Gaps

- **macOS Tahoe (26) TCC changes:** I found references to the stale-TCC-entry problem persisting in macOS 26 but could not find official Apple documentation of any TCC behavioral changes in macOS 26 specifically. The overall model appears unchanged from Sequoia.
- **Screen Recording prompt frequency on macOS 15.1+:** Apple says "fewer dialogs" for regularly used apps but has not published the exact heuristic. If Squeegee ever needs Screen Recording in the future, the actual prompt frequency is unpredictable.
- **Sparkle auto-update integration:** Direct distribution typically uses the Sparkle framework for auto-updates. I did not research Sparkle's current API or integration effort — this belongs in implementation, not in this permissions/distribution research.

## Sources

- [Apple Developer Documentation — AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions) — Authoritative for Accessibility check API
- [jano.dev — Accessibility Permission (Jan 2025)](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html) — Practical guide with code examples for checking/requesting Accessibility
- [openowl.dev — Fix macOS Permissions for Computer Use Agents](https://openowl.dev/blog/macos-accessibility-screen-recording-permissions) — Documents the stale TCC entry failure mode
- [ryanthomson.net — Screen Recording Permissions in Catalina are a Mess](https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess/) — Definitive reference for what CGWindowListCopyWindowInfo returns with/without Screen Recording
- [9to5Mac — macOS Sequoia screen recording prompt monthly (Aug 2024)](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/) — Timeline of Sequoia prompt frequency changes
- [Michael Tsai — Sequoia Screen Recording Prompts and Persistent Content Capture (Aug 2024)](https://mjtsai.com/blog/2024/08/08/sequoia-screen-recording-prompts-and-the-persistent-content-capture-entitlement/) — Aggregated developer reactions and entitlement details
- [TidBITS — How to Avoid Sequoia Screen Recording Prompts (Sep 2024)](https://tidbits.com/2024/09/23/how-to-avoid-sequoias-repetitive-screen-recording-permissions-prompts/) — User-facing workarounds and Apple policy analysis
- [Apple Developer Forums — Accessibility in sandbox (Thread #707680)](https://developer.apple.com/forums/thread/707680) — Apple confirmation that Accessibility is blocked in sandbox
- [Apple Developer Forums — macOS Accessibility APIs and Sandbox (Thread #123527)](https://developer.apple.com/forums/thread/123527) — Extended discussion of sandbox limitations
- [alinpanaitiu.com — Why aren't the most useful Mac apps on the App Store?](https://alinpanaitiu.com/blog/apps-outside-app-store/) — Comprehensive analysis of App Store restrictions for utility apps
- [Apple Developer — Distributing software on macOS](https://developer.apple.com/macos/distribution/) — Official distribution guidance
- [Apple Developer — Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — Official notarization reference
- [Nil Coalescing — Build a macOS menu bar utility in SwiftUI (Feb 2025)](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/) — MenuBarExtra implementation guide
- [Nil Coalescing — Add launch at login setting (Jan 2025)](https://nilcoalescing.com/blog/LaunchAtLoginSetting/) — SMAppService implementation guide
- [HackTricks — macOS TCC](https://hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-tcc/index.html) — TCC internals and Apple Events permission model
