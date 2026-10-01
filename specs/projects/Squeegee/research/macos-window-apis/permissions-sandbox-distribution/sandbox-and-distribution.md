# App Sandbox, App Store, and Distribution — Deep Dive

## Can Squeegee Ship on the Mac App Store?

**No.** The Mac App Store requires the App Sandbox (`com.apple.security.app-sandbox`). The Accessibility API — which Squeegee needs to enumerate, inspect, and close other apps' windows — is explicitly blocked in sandboxed apps. There is no workaround, no exception process for new apps, and no sign Apple plans to change this.

### The Specific Blockers

1. **Accessibility API is prohibited in sandbox.** `AXUIElementCopyAttributeValue`, `AXUIElementSetAttributeValue`, and related calls require that the user grant Accessibility permission via TCC. This permission cannot be requested by sandboxed apps — the system will not show the prompt, and direct TCC database entries are not created.

2. **No `com.apple.security.accessibility` entitlement for macOS.** Developers who have attempted to submit window-management apps receive:
   > "Invalid Code Signing Entitlements — The key `com.apple.security.accessibility` is not supported on macOS."

3. **Apple explicitly prohibits it.** Guideline 2.4.5 has been used to reject apps that use Accessibility features for non-assistive-technology purposes, even when the specific TCC service differs (e.g., `CGEvent.post` uses `kTCCServicePostEvent`, distinct from `kTCCServiceAccessibility`, but both appear under "Accessibility" in System Settings).

Sources:
- [Apple Developer Forums — Accessibility permission in sandbox (Thread #707680)](https://developer.apple.com/forums/thread/707680)
- [Apple Developer Forums — macOS Accessibility APIs and Sandbox (Thread #123527)](https://developer.apple.com/forums/thread/123527)
- [Apple Developer Forums — Unable to submit macOS window-manager app (Thread #805556)](https://developer.apple.com/forums/thread/805556)

### Why Do Some Window Managers Exist on the App Store?

Apps like Magnet, BetterSnapTool, and Divvy are on the Mac App Store despite using Accessibility. They were published **before sandboxing became mandatory** (macOS 10.7.3 era, ~2012). These apps have a grandfathered exception — they are not sandboxed even though they are on the App Store. New apps cannot get this exception.

Source: [alinpanaitiu.com — Why aren't the most useful Mac apps on the App Store?](https://alinpanaitiu.com/blog/apps-outside-app-store/)

### Creative Workarounds (Not Recommended for Squeegee)

Some developers have shipped window-management apps to the App Store using:
- **Private/undocumented APIs** — e.g., snApp (2023), Align (2024) used alternative approaches. Risk: Apple can reject updates at any time, and private API use violates App Store guidelines.
- **External helper apps** — A non-sandboxed helper app running outside the sandbox receives commands from the sandboxed main app. Risk: Complex architecture, potential review rejection, fragile.

Source: [blakecrosley.com — The Mac App Store Won't Let Window Managers Exist. I Shipped One Anyway.](https://blakecrosley.com/blog/window-manager-mac-app-store-sandbox)

## Distribution Recommendation: Developer ID + Notarization

Squeegee should use **direct distribution with Developer ID signing and notarization**. This is the standard path for macOS utility apps that need Accessibility.

### What This Involves

1. **Developer ID Application certificate** — The developer already has an Apple Developer account. A Developer ID Application certificate signs the app for distribution outside the App Store.

2. **Notarization** — Required since macOS Catalina. Xcode uploads the signed app to Apple, which runs automated malware checks and staples a notarization ticket. Without this, Gatekeeper blocks the app on first launch.

3. **Hardened Runtime** — Required for notarization. Restricts certain runtime behaviors (JIT, unsigned code loading, etc.) but does not restrict Accessibility API use.

4. **Distribution format** — Typically a `.dmg` disk image or a `.zip` file. The user drags the app to `/Applications`.

Sources:
- [Apple Developer Documentation — Distributing software on macOS](https://developer.apple.com/macos/distribution/)
- [Apple Developer Documentation — Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [Rambo Codes — Distributing Mac apps outside the App Store (Jan 2021)](https://www.rambo.codes/posts/2021-01-08-distributing-mac-apps-outside-the-app-store)

### What You Give Up vs. the App Store

| Concern | App Store | Direct Distribution |
|---|---|---|
| Commission | 30% (15% for small business) | 0% (pay your own payment processor, ~3%) |
| Updates | Automatic via App Store | Must implement yourself (Sparkle framework) |
| Discovery | App Store search | Your own marketing/website |
| Payment/Licensing | Apple handles | You handle (Paddle, FastSpring, Stripe, or free) |
| Sandbox | Required | Not required |
| Accessibility API | Blocked | Works |
| Review process | Apple review on every update | No review (notarization is automated) |
| User trust | "From the App Store" | "From an identified developer" (Gatekeeper message) |

Source: [fatbobman.com — Escaping the Mac App Store](https://fatbobman.com/en/posts/zipic-2-selling-and-distribution/), [techlila.com — Mac App Store vs Direct Downloads 2026](https://www.techlila.com/mac-app-store-vs-direct-downloads-dmg/)

### If Squeegee Is Free

If Squeegee is distributed for free, direct distribution is simpler — no payment infrastructure needed. The main things to handle:
- **Auto-updates:** Use the [Sparkle](https://sparkle-project.org/) framework (standard for direct-distributed Mac apps)
- **Website/download page:** Host the `.dmg` or `.zip` somewhere accessible
- **Notarization:** Automated in Xcode, adds ~2 minutes to the build/release process

### Automation / Apple Events Permission

If Squeegee uses AppleScript/Apple Events to close windows (e.g., `tell application "Finder" to close window 1`), it also needs the **Automation** permission (`kTCCServiceAppleEvents`). Key points:

- Prompts are **per target app** — the user sees "Squeegee wants to control Finder" the first time Squeegee sends an Apple Event to Finder, then separately for Preview, Safari, etc.
- Requires the `com.apple.security.automation.apple-events` entitlement and an `NSAppleEventsUsageDescription` in Info.plist
- The prompt appears automatically on first use — no API to pre-trigger it
- The grant is remembered permanently (until reset) — no monthly re-prompts like Screen Recording
- Cannot be pre-configured via System Settings UI; only appears after the first attempt

**Recommendation for Squeegee:** Prefer the Accessibility API (`kAXCloseButtonAttribute` + `AXUIElementPerformAction` with `kAXPressAction`) over Apple Events for closing windows. This avoids per-target-app prompts entirely — Accessibility is a single blanket grant.

If Apple Events are needed as a fallback for specific apps, the per-app prompt model is annoying but tolerable. The prompt only appears once per target app and is remembered.

Sources:
- [HackTricks — macOS TCC](https://hacktricks.wiki/en/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-tcc/index.html)
- [Apple Developer Forums — kTCCServiceAppleEvents](https://developer.apple.com/forums/thread/123527)
