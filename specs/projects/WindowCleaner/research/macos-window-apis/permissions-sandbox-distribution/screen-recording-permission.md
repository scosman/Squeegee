# Screen Recording Permission — Deep Dive

## Does WindowCleaner Need Screen Recording?

**Short answer: No, if it uses the Accessibility API for window titles.**

The Screen Recording permission (TCC service `kTCCServiceScreenCapture`) gates access to window titles through `CGWindowListCopyWindowInfo`. Specifically, without Screen Recording:
- `kCGWindowName` (window title) is **nil/missing**
- `kCGWindowSharingState` returns **0**
- All other fields (`kCGWindowBounds`, `kCGWindowOwnerPID`, `kCGWindowOwnerName`, `kCGWindowNumber`, `kCGWindowLayer`, `kCGWindowAlpha`) remain available

This means `CGWindowListCopyWindowInfo` is still useful for enumerating windows by ID, owner, position, and size — but not for reading titles.

**The alternative:** The Accessibility API (`AXUIElement` with `kAXTitleAttribute`) provides window titles and only requires Accessibility permission, not Screen Recording. This is the approach used by AltTab and other window-management tools that want to avoid Screen Recording.

Sources:
- [ryanthomson.net — Screen Recording Permissions in Catalina are a Mess](https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess/)
- [AltTab GitHub](https://github.com/nahaylo/alttab-macos) — uses Accessibility API, avoids Screen Recording for titles

## What Data Is Available Without Screen Recording

| CGWindowListCopyWindowInfo field | Without Screen Recording | With Screen Recording |
|---|---|---|
| `kCGWindowBounds` | Available | Available |
| `kCGWindowOwnerPID` | Available | Available |
| `kCGWindowOwnerName` | Available | Available |
| `kCGWindowLayer` | Available | Available |
| `kCGWindowNumber` (window ID) | Available | Available |
| `kCGWindowAlpha` | Available | Available |
| **`kCGWindowName`** (title) | **Nil/Missing** | Available |
| `kCGWindowSharingState` | Returns 0 | Accurate value |

This behavior was introduced in **macOS Catalina (10.15)** in 2019. `CGWindowListCopyWindowInfo` itself never triggers a permission dialog — it silently withholds the redacted fields.

Source: [ryanthomson.net — Screen Recording Permissions in Catalina](https://www.ryanthomson.net/articles/screen-recording-permissions-catalina-mess/)

## Why Avoiding Screen Recording Matters: macOS Sequoia/Tahoe UX

### Monthly Re-prompts (macOS 15.0)

Starting with macOS 15 Sequoia, Apple introduced recurring permission prompts for apps with Screen Recording access:

- **Initial beta (Aug 2024):** Weekly prompts + prompt on every reboot
- **Beta 6 (Aug 14, 2024):** Changed to monthly prompts, removed reboot prompts
- **macOS 15.1 (Oct 2024):** Further reduced — "users will see fewer dialogs if they regularly use apps in which they have already acknowledged and accepted the risks"

The prompt text reads:
> "[App name] is requesting to bypass the system private window picker and directly access your screen and audio. This will allow [app name] to record your screen and system audio, including..."

Users can select "Allow For One Month" or go to System Settings.

Sources:
- [9to5Mac — macOS Sequoia monthly screen recording prompt (Aug 2024)](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/)
- [MacRumors — macOS Sequoia screen recording permissions monthly (Aug 2024)](https://www.macrumors.com/2024/08/15/macos-sequoia-screen-recording-app-permissions/)
- [TidBITS — How to avoid Sequoia screen recording prompts (Sep 2024)](https://tidbits.com/2024/09/23/how-to-avoid-sequoias-repetitive-screen-recording-permissions-prompts/)

### The Persistent Content Capture Entitlement

Apple provides `com.apple.developer.persistent-content-capture` for apps that need persistent screen recording without monthly prompts. However:

- It is explicitly "intended for Virtual Network Computing (VNC) apps"
- Developers must apply via a request form
- A window-cleaning utility would **not** qualify
- There is no documented alternative for non-VNC apps

Source: [Michael Tsai — Sequoia Screen Recording Prompts and the Persistent Content Capture Entitlement (Aug 2024)](https://mjtsai.com/blog/2024/08/08/sequoia-screen-recording-prompts-and-the-persistent-content-capture-entitlement/)

### The `SCContentSharingPicker` Alternative

Apple's other recommendation is to use `SCContentSharingPicker`, which lets the user choose what to share via a system picker UI rather than granting blanket access. This avoids the monthly prompt but requires user interaction each time — not suitable for a background utility like WindowCleaner.

Source: [Eternal Storms Blog — PSA: No More Monthly Screen Recording Permission Reminders (Sep 2024)](https://blog.eternalstorms.at/2024/09/23/psa-no-more-macos-15-sequoia-monthly-screen-recording-permission-reminders/)

## Recommendation for WindowCleaner

**Do not request Screen Recording permission.** WindowCleaner should:

1. Use `CGWindowListCopyWindowInfo` for window enumeration (IDs, bounds, owner PID) — this works without Screen Recording.
2. Use the Accessibility API (`AXUIElement` + `kAXTitleAttribute`) for window titles — this requires only Accessibility permission.
3. Never use `CGDisplayStream`, `CGDisplayCreateImage`, or `SCStream` — these trigger the Screen Recording prompt.

This approach avoids the monthly re-prompt UX problem entirely and requires only a single TCC permission (Accessibility).

### What WindowCleaner Would Lose

- No window thumbnails/previews (requires Screen Recording or ScreenCaptureKit). This is acceptable — WindowCleaner does not need thumbnails.
- No window title via `kCGWindowName` from `CGWindowListCopyWindowInfo` — but the Accessibility API provides the same information.

### If Screen Recording Were Ever Needed

If future features require it (e.g., window previews), be aware:
- macOS 15+: monthly re-prompts unless the user "regularly uses" the app (vague Apple-defined heuristic)
- macOS 15.1+: "fewer dialogs" for regularly-used apps — the exact frequency is not documented
- The Persistent Content Capture entitlement is not available for this category of app
- Enterprise environments can suppress prompts via MDM (`forceBypassScreenCaptureAlert` key, macOS 15.1+)

Source: [Jamf Community — Monthly TCC Prompts macOS v15](https://community.jamf.com/t5/jamf-pro/monthly-tccc-prompts-macos-v15/m-p/331604)
