# CGWindowListCopyWindowInfo: Window Enumeration via Quartz

## Overview

`CGWindowListCopyWindowInfo` is the primary public API for discovering windows in macOS. Available since macOS 10.5, it returns an array of `CFDictionary` values, each describing one window in the current user session.

**Signature (Swift):**
```swift
func CGWindowListCopyWindowInfo(
    _ option: CGWindowListOption,
    _ relativeToWindow: CGWindowID
) -> CFArray?
```

Source: [Apple Developer Documentation](https://developer.apple.com/documentation/coregraphics/cgwindowlistcopywindowinfo(_:_:))

## Window List Options

The `option` parameter controls which windows are returned:

- `.optionAll` — all windows, including off-screen and minimized
- `.optionOnScreenOnly` — only on-screen windows (excludes off-screen, other Spaces, minimized)
- `.excludeDesktopElements` — excludes desktop background and icons
- `.optionOnScreenAboveWindow` / `.optionOnScreenBelowWindow` — relative to a specific window

For Squeegee, `.optionAll` combined with `.excludeDesktopElements` is needed to track windows across all Spaces, including minimized ones.

**Important:** Using `.optionAll` without `.optionOnScreenOnly` returns many "dummy" windows — invisible helper windows, tab placeholders, etc. Filtering by `kCGWindowLayer == 0` catches most normal application windows, but further heuristics are needed. ([SO: Separating real and dummy windows](https://stackoverflow.com/questions/58453011/separating-real-and-dummy-windows-returned-by-cgwindowlistcopywindowinfo))

## Required Dictionary Keys (Always Present)

These keys are guaranteed in every returned dictionary:

| Key | Type | Description |
|-----|------|-------------|
| `kCGWindowNumber` | CFNumber (Int32) | Unique window ID (`CGWindowID`) within the user session |
| `kCGWindowStoreType` | CFNumber (Int32) | Backing store type (retained, non-retained, buffered) |
| `kCGWindowLayer` | CFNumber (Int32) | Window level/layer. Normal app windows are layer 0 |
| `kCGWindowBounds` | CFDictionary | Window bounds as `{X, Y, Width, Height}` in screen coordinates |
| `kCGWindowOwnerPID` | CFNumber (Int32) | PID of the owning process |
| `kCGWindowOwnerName` | CFString | Name of the owning process |
| `kCGWindowSharingState` | CFNumber (Int32) | Sharing type (see permissions section) |

Source: [CGWindow.h header](https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/CoreGraphics.framework/Versions/A/Headers/CGWindow.h), Apple documentation

## Optional Dictionary Keys

| Key | Type | Description |
|-----|------|-------------|
| `kCGWindowName` | CFString | Window title. **Requires Screen Recording permission** since macOS 10.15 |
| `kCGWindowAlpha` | CFNumber (Float) | Window alpha/opacity |
| `kCGWindowMemoryUsage` | CFNumber (Int64) | Approximate memory usage |
| `kCGWindowIsOnscreen` | CFNumber (Bool) | Whether the window is currently visible on screen |

**There is no `kCGWindowCreationTime` or equivalent.** The API does not expose when a window was created.

## What Is Redacted Without Screen Recording Permission

Since macOS 10.15 Catalina, without Screen Recording (TCC) permission:

- **`kCGWindowName` is omitted entirely** — the key is absent from the dictionary, not just empty
- **`kCGWindowSharingState` returns 0** instead of its actual value

Everything else remains available without Screen Recording: window ID, bounds, owner PID, owner name, layer, on-screen status, and memory usage.

**Exceptions:** An app can always read its own windows' names. Certain system UI elements (Window Server, Dock) may also be readable.

Sources:
- [Ryan Thomson: Screen Recording Permissions in Catalina are a Mess](https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess)
- [SO: Detecting screen recording settings on macOS Catalina](https://stackoverflow.com/questions/56597221/detecting-screen-recording-settings-on-macos-catalina)
- WWDC 2019: "Advances in macOS Security" (briefly discusses this)

## Screen Recording Permission: macOS 15 Sequoia Changes

macOS 15 Sequoia introduced **periodic re-prompting** for Screen Recording permission:

- macOS 15.0: Monthly re-prompt (changed from weekly in beta after developer backlash)
- macOS 15.1: Reduced frequency for "regularly used" apps — fewer prompts if the user has already approved
- macOS Tahoe 26: Weekly re-prompt reported

This is relevant for Squeegee because **window titles require Screen Recording permission**. If Squeegee can work without window titles (using only window ID, bounds, owner PID), it avoids this entire permission and its UX burden. This is a strong argument for not requiring Screen Recording.

Sources:
- [TidBITS: How to Avoid Sequoia's Repetitive Screen Recording Permissions Prompts](https://tidbits.com/2024/09/23/how-to-avoid-sequoias-repetitive-screen-recording-permissions-prompts)
- [9to5Mac: macOS Sequoia monthly screen recording prompts](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/)
- [iDownloadBlog: macOS Sequoia 15.1 fewer prompts](https://www.idownloadblog.com/2024/10/09/macos-sequoia-15-1-macos-screen-recording-prompts-frequency-reduced)
- [Skilly: Enable screen recording permission on macOS](https://tryskilly.app/learn/enable-screen-recording-permission-macos) (confirms Tahoe 26 weekly re-prompt)

## Practical Implications for Squeegee

1. **Without Screen Recording**, CGWindowListCopyWindowInfo still gives: window IDs, bounds, owner PID/name, layer, on-screen status. This is sufficient for window enumeration and identity.
2. **Window titles are nice-to-have** for the UI (showing "Untitled — TextEdit" in the close list) but not essential for core functionality.
3. **Generating the window list is expensive** per Apple's docs — polling should be infrequent or event-driven.
4. **Filtering normal windows**: Layer 0 + exclude desktop elements + exclude zero-size windows is a reasonable starting heuristic.

## Availability

- Available since macOS 10.5
- Works on macOS 14 Sonoma, 15 Sequoia, and 26 Tahoe
- No deprecation notice as of September 2026
