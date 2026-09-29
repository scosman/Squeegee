# Accessibility (TCC) Permission — Deep Dive

## What WindowCleaner Needs Accessibility For

WindowCleaner must enumerate other apps' windows, read their titles, and close them. The Accessibility API (`AXUIElement`) is the primary mechanism for all three. Every one of these operations requires that the user grant Accessibility permission in System Settings > Privacy & Security > Accessibility.

Critically, the Accessibility API can also provide window titles via `kAXTitleAttribute` — **without** needing Screen Recording permission. This is a major reason to prefer `AXUIElement` over `CGWindowListCopyWindowInfo` for window titles (see [screen-recording-permission.md](./screen-recording-permission.md) for details on why Screen Recording is worse UX).

## Checking Permission Status

### `AXIsProcessTrusted()`

A pure read. Returns `true` if the current process has Accessibility permission, `false` otherwise. Never prompts the user. Reads from a per-process cache populated at first call.

```swift
let isGranted = AXIsProcessTrusted()
```

Source: [Apple Developer Documentation — AXIsProcessTrustedWithOptions](https://developer.apple.com/documentation/applicationservices/1459186-axisprocesstrustedwithoptions)

### `AXIsProcessTrustedWithOptions(_:)`

Takes a `CFDictionary`. If `kAXTrustedCheckOptionPrompt` is `true`, the system will either show a dialog or redirect the user to the Accessibility pane in System Settings.

```swift
let options: NSDictionary = [
    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
]
let trusted = AXIsProcessTrustedWithOptions(options)
```

**Behavior on macOS 15+ (Sequoia/Tahoe):** The prompt is no longer a modal dialog. The call returns immediately and the user must navigate to System Settings themselves. Production tools open the pane explicitly:

```swift
if let url = URL(string:
    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
) {
    NSWorkspace.shared.open(url)
}
```

Source: [jano.dev — Accessibility Permission (Jan 2025)](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)

## Detecting a Grant Without Restart

There is **no notification API** for TCC state changes. The standard approach:

1. Call `AXIsProcessTrustedWithOptions` with `kAXTrustedCheckOptionPrompt: true` **once** at first launch (or when the user taps a "Grant Permission" button).
2. Open System Settings directly via the URL scheme.
3. Poll `AXIsProcessTrusted()` (without the prompt option) on a timer (e.g., every 1-2 seconds) to detect when the user grants permission.
4. Once `true`, stop polling and proceed.

**Important:** Do not call `AXIsProcessTrustedWithOptions` with the prompt option on every poll iteration — this causes a nagging loop where the prompt reappears every few seconds.

Source: [filipmares/tile Issue #22 — Accessibility onboarding](https://github.com/filipmares/tile/issues/22), [ActivityWatch/aw-watcher-window Issue #147](https://github.com/ActivityWatch/aw-watcher-window/issues/147)

### Caveat: Stale TCC Cache

`AXIsProcessTrusted()` reads from a per-process cache that can become stale. Even when `AXIsProcessTrusted()` returns `true`, actual AX calls can fail with `kAXErrorAPIDisabled` or `kAXErrorCannotComplete`. This happens when:

- The TCC entry was invalidated by an OS update or app re-sign
- The System Settings toggle still shows the app as enabled (it displays by bundle ID/path, not code identity)

**Recommendation:** Validate with a real AX call (e.g., listing windows of a known app) in addition to checking `AXIsProcessTrusted()`. If the real call fails despite `AXIsProcessTrusted() == true`, tell the user to remove and re-add the app in Accessibility settings.

Source: [openowl.dev — Fix macOS Permissions for Computer Use Agents](https://openowl.dev/blog/macos-accessibility-screen-recording-permissions)

## The Code Signing / App Update Problem

This is a critical issue for WindowCleaner and must be handled correctly.

### Root Cause

macOS TCC ties Accessibility grants to the **code identity** of the app. When an app is signed with a Developer ID certificate, the identity includes the `TeamIdentifier`, which stays stable across builds. When an app is ad-hoc signed (development builds, unsigned releases), the identity is the `cdhash` — a hash of the specific binary — which changes on every build.

### What Happens

After an app update that changes the binary:
- **Ad-hoc signed apps:** The TCC grant is silently invalidated. `AXIsProcessTrusted()` may still return `true` (stale cache), and the System Settings toggle may still appear enabled, but actual AX calls fail. The user gets no prompt — the app just silently stops working.
- **Developer ID signed apps:** The grant survives because the `TeamIdentifier` stays the same. This is the correct behavior for shipped apps.

### How to Verify

```bash
# Check signing identity
codesign -dv /path/to/WindowCleaner.app

# Check designated requirement — should show certificate, not cdhash
codesign -d -r- /path/to/WindowCleaner.app
```

If the designated requirement shows a `cdhash` instead of a certificate identifier, grants will break on every update.

### Development Builds

During development with Xcode, builds are typically signed with a development certificate tied to a team. This usually survives rebuilds. However, "Sign to Run Locally" (ad-hoc) builds will lose permissions on every rebuild.

**Recommendation:** Always use a development team signing identity during development, and Developer ID for distribution. WindowCleaner's developer has an Apple Developer account, so this is straightforward.

Sources:
- [pathorsAI/parley Issue #75 — Ad-hoc signing invalidates permissions](https://github.com/pathorsAI/parley/issues/75)
- [NousResearch/hermes-agent Issue #49110 — Sign with Developer ID for stable TCC](https://github.com/NousResearch/hermes-agent/issues/49110)
- [jedipunkz/UnNatural Issue #30 — Permission lost after make install](https://github.com/jedipunkz/UnNatural/issues/30)

## Required Configuration

### Info.plist

```xml
<key>NSAccessibilityUsageDescription</key>
<string>WindowCleaner uses Accessibility to manage your app windows — listing, identifying, and closing windows that have been inactive.</string>
```

### Entitlements (for non-sandboxed app)

No special entitlement is needed for Accessibility in a non-sandboxed app. The `com.apple.security.accessibility` key mentioned in some sources is **not** a valid entitlement for macOS — it is rejected by App Store Connect. Accessibility works through TCC user consent, not entitlements.

Source: [Apple Developer Forums — Unable to submit macOS window-manager app](https://developer.apple.com/forums/thread/805556)

## Resetting Permissions (for troubleshooting)

```bash
# Reset Accessibility permission for a specific app
sudo tccutil reset Accessibility <bundle-id>

# Query current TCC state (requires sudo)
sudo sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT auth_value FROM access WHERE service='kTCCServiceAccessibility' AND client='com.example.windowcleaner';"
# 1 = granted, 2 = denied
```

Source: [jano.dev — Accessibility Permission](https://jano.dev/apple/macos/swift/2025/01/08/Accessibility-Permission.html)
