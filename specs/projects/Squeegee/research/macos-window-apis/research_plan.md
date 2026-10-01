# Research Plan: macOS Window APIs for Squeegee

## Goal

Squeegee closes app windows on macOS after N hours, per app, measured from "opened" or "last active". Before we write the functional spec for project Squeegee, we must know which window APIs exist, what each one needs in permissions, and how well we can track window "activity" — ideally without special permissions. The functional spec (Step 2) and architecture (Step 4) wait on this research.

## Run

- Model: Opus 5.5 (current session model)

## Subtopics

- [x] Window enumeration, identity, and closing — which APIs list, identify, and close individual windows of other apps
- [x] Activity signals — what signals tell us a window is "active", and which need no special permission
- [x] Permissions, sandbox, and distribution — TCC permissions, App Store sandbox limits, and background/menu bar app setup
- [x] Prior art — existing macOS apps that close/quit/hide idle windows or apps, and how they do it

## Focus Details

### Window enumeration, identity, and closing

How can a background app list all windows of other apps, give each window a stable identity over hours, and close one specific window? Cover: `CGWindowListCopyWindowInfo` (fields available, what is redacted without Screen Recording permission on current macOS — e.g. window titles), the Accessibility API (`AXUIElement`, `kAXWindowsAttribute`, the close button via `kAXCloseButtonAttribute` + `AXPress`), and mapping between `CGWindowID` and `AXUIElement` (e.g. the private `_AXUIElementGetWindow`, and its risk). Window identity across time: does a `CGWindowID` stay stable for the life of a window, can it be reused, what happens with tabs (Finder/Safari tabs as windows), Spaces, full-screen, minimized, and hidden apps. No API gives a window creation time — confirm this, and find how to infer "opened at" (first observation, app launch time). Close vs quit: `NSRunningApplication.terminate()`, AppleScript/Apple Events `close window` (Finder, Preview, QuickTime), and what happens on "unsaved changes" dialogs. Note which of these APIs work on macOS 14/15/26 (current). Out of scope: how to measure activity (Activity signals subtopic), permission UX and App Store rules (Permissions subtopic).

### Activity signals

What signals can tell Squeegee that a window was "active" (in use), so the close timer can run from "last active" instead of "opened"? For each signal, state if it needs a special permission. Cover: frontmost app changes (`NSWorkspace.didActivateApplicationNotification`, no permission), focused/main window changes (`AXObserver` with `kAXFocusedWindowChangedNotification`, `kAXMainWindowChangedNotification`, needs Accessibility), window moved/resized/minimized notifications, z-order from `CGWindowListCopyWindowInfo` (front-most window per app via list order — can we infer the focused window without Accessibility?), `kCGWindowIsOnscreen`, Space changes, user idle time (`CGEventSource.secondsSinceLastEventType`) so we don't count time the user is away. Evaluate the user's proposed heuristics: "never entered foreground", "never in foreground for 5s+", "moved position" (weak). Find the best practical design: notifications vs polling, polling cost/energy, accuracy limits (e.g. focused window in an app that is not frontmost). Out of scope: listing/closing windows (Window enumeration subtopic), permission UX (Permissions subtopic).

### Permissions, sandbox, and distribution

What permissions does this class of app need, and what does that mean for distribution and UX? Cover: Accessibility (TCC) — how to check (`AXIsProcessTrustedWithOptions`), prompt, detect a grant without restart, and known problems (grant lost after app update/re-sign, dev builds). Screen Recording permission — is it needed only for window titles, and how bad is its UX on macOS 15+ (monthly re-prompts?). Automation/Apple Events permission (per-target-app prompts). Mac App Store: can a sandboxed app use Accessibility to control other apps' windows (it cannot as far as we know — confirm current rules), so direct distribution with Developer ID + notarization is likely. Background app setup: menu bar only app (`LSUIElement`), `MenuBarExtra` in SwiftUI, launch at login with `SMAppService`, hide-menu-bar-icon option and how the user then re-opens settings. The user has an Apple Developer account and is fine with either Developer ID signed direct distribution or the Mac App Store: state clearly whether the choice matters for this app, and recommend one. Out of scope: which specific APIs list/close windows (Window enumeration subtopic), activity heuristics (Activity signals subtopic).

### Prior art

Which existing macOS apps close, quit, or hide idle windows or apps, and what can we learn from them? Examples to check: Quitter (Marco Arment), Hocus Focus, AutoQuit-type apps, window managers (Rectangle, Amethyst, yabai, AltTab — for how they enumerate windows and track focus), and any open-source "close idle windows" tools. For each: what it does (window vs app level), what permissions it asks for, distribution (App Store or direct), how it measures inactivity, and any known problems or user complaints. Open-source ones (AltTab, Rectangle, Amethyst, yabai) are high value: find the exact APIs they use for window identity and focus tracking, and any private-API use. Also note any lists of "apps safe to close/quit" or heuristics for which apps restore state well. **Build-vs-buy:** the user may use an existing app instead of building Squeegee if one is good enough. Compare the candidates against Squeegee's feature set (per-window close after N hours, per-app rules, "since opened" vs "since last active", close window vs quit app, menu bar UI with upcoming/recent closures) and end the subtopic summary with a clear "Next best alternative" recommendation: the single best existing app, what it covers, what it lacks, and whether it is good enough to skip the build. Out of scope: re-documenting the base APIs in depth (other subtopics own that) — cite them only as used by these apps.
