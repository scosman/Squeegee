---
status: complete
---

# Functional Spec: Squeegee

## 1. Summary

Squeegee is a macOS menu bar app that closes stale windows of other apps. The user sets per-app rules ("close Finder windows 6 hours after I last used them"), and Squeegee closes each window when its time is up. It works per **window**, not per process: closing one stale Finder window leaves the other Finder windows alone.

The design goal is "safe by default": it only acts on apps the user has turned on, it only sends a normal close (the same as clicking the red close button), and it never force-quits anything.

Research that backs the decisions in this spec: [macOS window APIs research](research/macos-window-apis/summary.md).

### 1.1 Design principles

Carried over from Biscotti (github.com/scosman/Biscotti, `specs/app_overview.md`):

- **Exceptionally "Apple" native.** Standard controls, HIG compliant, good use of the system accent color. Not "light on design" but "tight design": no invented visual language, just close attention to details, like Apple's own design team.
- **Menu bar first.** The app does its work with no window open. Most users only see the menu bar popover after onboarding.
- **Safe by default.** Nothing closes until the user turns it on. Only normal close/quit actions, never forced ones.
- **Settings are per app, not per window.** The UI never asks the user to manage single windows. To change what happens to a window, the user changes its app's rule.
- **Local and private.** No network, no accounts, no telemetry.

## 2. Scope

### V1

- Per-window close after a duration, measured from **last active** (default) or **opened**.
- Per-app rules, plus one global rule for all other apps.
- Optional per-app "quit app when last window closed".
- Onboarding: Accessibility permission, scan installed apps, suggest rules from a built-in catalog.
- Menu bar popover: upcoming closures, recent closures (with Reopen when possible), pause.
- Settings window: general settings and the per-app rules editor.
- Option to hide the menu bar icon.
- Launch at login.

### P2 (not V1)

- Full close history window (V1 stores the data; see §9).
- Confirmation before a rule change closes open windows (§13).
- In-app management UI: list the oldest windows and close them by hand.
- Safari tab support.
- Auto-updates (Sparkle).

### Out of scope

- Per-window settings (pin, snooze, "keep this one"). All settings are per app.
- Notifications of any kind.
- Force-quit, or any handling of save dialogs.
- Mac App Store distribution (the App Sandbox blocks the Accessibility API — see [permissions research](research/macos-window-apis/permissions-sandbox-distribution/summary.md)).

## 3. Core Concepts

### 3.1 Managed windows

Squeegee tracks only **standard windows**: normal app windows with a close button. It ignores panels, dialogs, sheets, floating/utility windows, popovers, the desktop, and any window without a close button. It includes minimized windows, windows on other Spaces, full-screen windows, and windows of hidden apps.

macOS only lets Squeegee inspect (title, window type) and close windows on the **current Space**. A window that Squeegee has never seen on the current Space (for example, one that was already on another Space when Squeegee started) is tracked (its timers run) but is not shown or closed until the user visits its Space. A window whose deadline passes while it is on another Space closes when Squeegee can reach it (see architecture).

Squeegee never manages its own windows.

### 3.2 Opened time

No macOS API reports when a window opened. **Opened time = the first time Squeegee saw the window.**

- Windows that are already open when Squeegee starts get "opened = now". This means the first launch (or a Mac restart) never causes a burst of closures.
- If Squeegee quits and restarts while the target app keeps running, it restores the saved opened/last-active times for windows it can match (same app process and same window ID). Other windows start fresh.

### 3.3 Last active time

A window is **active** when it is the focused window of the frontmost app. Focus must last **5 seconds or more** to count. This stops a quick Cmd-Tab or click-through from resetting a timer.

- While a window stays focused (after the first 5 s), its last-active time is "now".
- When focus leaves, last-active time = the time focus left.
- A window that has never been active uses its opened time.
- User idle time is **not** taken into account. A window left focused while the user is away counts as active.

### 3.4 Deadline

For a window whose app rule is enabled:

- Measure from **Last active**: deadline = last-active time + duration.
- Measure from **Opened**: deadline = opened time + duration.

Times are wall-clock times. Time while the Mac sleeps counts. There is no special case for sleep or wake in V1.

## 4. Rules

### 4.1 Rule fields

| Field | Values | Default |
|---|---|---|
| Enabled | on / off | off (global rule); on (suggested rules) |
| Close after | duration, 5 minutes to 30 days | 6 hours |
| Measure from | Last active / Opened | Last active |
| Quit app when last window closed | Off / If closed by Squeegee / Always | Off |

"Close after" has presets (30 min, 1 h, 2 h, 4 h, 6 h, 12 h, 1 day, 2 days, 1 week) and a custom value (hours and minutes).

### 4.2 Global rule and app rules

- **Global rule ("All other apps"):** applies to every app that has no app rule. It is **disabled by default**.
- **App rule:** a custom rule for one app, identified by bundle ID. An app rule fully replaces the global rule for that app. An app rule with Enabled = off means "never close this app's windows", even if the global rule is on.
- The user can add an app rule for any installed or running app, edit it, or remove it (the app then follows the global rule again).
- The "Quit app when last window closed" option is not available for the global rule, and not available for Finder (Finder cannot be quit in a normal way).
- Rule changes apply immediately (standard macOS settings behavior; there is no Save button in V1).

## 5. Closing Behavior

### 5.1 When a window closes

Squeegee checks all managed windows at a regular interval. A window closes within **1 minute** after its deadline, if all these conditions are true:

1. Its rule is enabled.
2. Closures are not paused (§5.5).
3. It is not the focused window of the frontmost app. (If it is, it waits. When focus leaves, last-active time updates, so a "Last active" window gets a new deadline. An "Opened" window closes at the next check after focus leaves.)
4. Squeegee has not already sent a close to this window since it was last active (§5.3).

### 5.2 Close action

Squeegee **sends a close** — the same as clicking the window's red close button. It does not enforce the close:

- If the app closes the window, Squeegee records a closure (§8).
- If the app does not close it (a "save changes?" dialog, a confirm prompt, or anything else), that is the app's decision. Squeegee does nothing more. It does not click dialog buttons and does not try again (§5.3).
- Each native macOS tab (e.g. a Finder window with tabs) is its own window, with its own timers. A close closes only that tab (verified on hardware; see hardware_findings.md).

### 5.3 One attempt per activity period

After Squeegee sends a close to a window, it does not send another close to that window until the window becomes active again. If the user uses the window again, it gets a new last-active time and a new deadline. This stops a repeated save dialog every minute.

### 5.4 Quit app when last window closed

This per-app option has three values:

- **Off** (default): Squeegee never quits the app.
- **If closed by Squeegee:** when Squeegee closes a window and after that the app has **no standard windows left**, Squeegee quits the app.
- **Always:** when the app has **no standard windows left**, for any reason (Squeegee closed the last one, or the user did), Squeegee quits the app.

Rules for all quits:

- The quit is a normal quit (the same as Cmd-Q). It never force-quits. If the app does not quit (for example, it asks to save), that is the app's decision, and Squeegee does not try again until the app has a standard window again.
- It does not quit an app that is frontmost at that moment. It waits until the app is not frontmost.
- For **Always**, the app must have had at least one standard window since Squeegee started to track it, and must have no standard windows for **1 minute** continuously. This stops a quit of an app that just launched (before its first window opens), or of an app that closes and opens its window for a short time while it loads.
- Squeegee records the quit in recent closures.

### 5.5 Pause

The user can pause all closures: **for 1 hour**, **until tomorrow** (next 6:00 AM local time), or **until resumed**. While paused, tracking continues (opened and last-active times still update) but no windows close. When the pause ends, windows past their deadline close at the next check. Pause state persists across app restarts.

## 6. Permissions

Squeegee needs exactly one permission: **Accessibility**. It does not use Screen Recording or Automation (Apple Events).

- Onboarding asks for it (§7).
- If the permission is missing or revoked at any time, Squeegee stops all closures and tracking that needs it. The menu bar icon shows a warning state, and the popover and Settings show a banner: "Squeegee needs Accessibility access to close windows" with an **Open System Settings** button.
- When the permission is granted, Squeegee detects it without a restart and resumes.

## 7. Onboarding

Shown on first launch. It follows the **layout** of the Biscotti onboarding (not its fonts or colors): a full-window scaffold with a thin progress bar and a small uppercase kicker at the top, centered content with a max width, a brand footer at the bottom, one primary button, and forward-only navigation (no Back).

| # | Screen | Kicker | Content |
|---|---|---|---|
| 1 | Welcome | WELCOME | What Squeegee does, in two sentences. Button: Continue. |
| 2 | Accessibility | PERMISSIONS | Why the permission is needed and what we do with it (close windows; nothing leaves the Mac). One permission row with a **Grant** button that changes to a **Granted** tag. Continue is enabled when granted. A **Skip** link is available; if skipped, the permission banner (§6) shows later. |
| 3 | Suggestions | SUGGESTIONS | A checklist of suggested rules for apps found on this Mac (§7.1). Button: Continue. |
| 4 | Done | FINISH | "You're set." A short note that the menu bar icon is where to see upcoming closures. Button: Get Started. |

After Get Started, the onboarding window closes and the app runs from the menu bar.

Launch at login is not part of onboarding. It is **on by default** (set when onboarding completes) and the user changes it in Settings.

### 7.1 Suggestions

Squeegee scans for installed apps (`/Applications`, `/System/Applications`, `~/Applications`) and running apps, and matches them by bundle ID against the built-in catalog (§11).

- Only matched apps show. They are grouped by category (§11) with the app icon, name, and a one-line rule summary (e.g. "Close windows 6 h after last use").
- All rows are **checked by default**. The user can uncheck any row.
- Continue creates an app rule (enabled) for each checked row. The global rule stays disabled.
- If no apps match, the screen says so and Continue moves on.

The same Suggestions view is available later from Settings → Apps ("Add suggested rules"). There it shows only catalog apps that do not already have an app rule.

### 7.2 Launch behavior

A user-initiated launch (Dock, Finder, Spotlight, Launchpad, `open`, Xcode Run) opens the main window at the current route: Onboarding if not complete, Settings otherwise. A launch at login (the system starts the app via `SMAppService.mainApp`) is silent: menu bar only, no window. The login-item launch is detected via the `keyAELaunchedAsLogInItem` descriptor in the `kAEOpenApplication` Apple event.

## 8. Menu Bar

A menu bar icon opens a popover.

### 8.1 Icon states

- Normal.
- Paused (different icon).
- Permission missing (warning icon).

### 8.2 Popover contents

1. **Banner** (only if needed): permission missing (§6), or "Paused until …" with a Resume button.
2. **Closing next:** the managed windows with the soonest deadlines, sorted by deadline, up to 8 rows. Each row: app icon, window title (or app name if there is no title), time left ("in 2 h 10 m"; "waiting — in use" for a focused window past its deadline). Clicking a row opens Settings → Apps at that app's rule, so the user can adjust it. There are no per-window actions.
3. **Recently closed:** the last 8 closures, newest first. Each row: app icon, window title, and time ago ("20 m ago"). A **Reopen** button shows when a document or folder URL was captured (§9). App quits show as "Quit QuickTime Player".
4. **Footer:** Pause menu (1 hour / Until tomorrow / Until resumed, or Resume when paused), Settings…, Quit Squeegee.

Empty states: "No windows scheduled to close" with a hint to add rules in Settings; "Nothing closed yet".

### 8.3 Hidden menu bar icon

Settings has a "Show menu bar icon" toggle (default on). When off, the icon is not shown. To open Settings again, the user opens Squeegee again from Finder, Spotlight, or Launchpad; this shows the Settings window. The toggle shows this instruction next to it.

## 9. Recent Closures and Reopen

For each closure Squeegee records: app bundle ID, app name, window title, closed time, kind (window closed / app quit), and the window's document or folder URL if the app exposes one.

- **Reopen** opens the URL in the same app.
- If the file or folder no longer exists, Reopen shows an inline error ("File not found") and the button is disabled for that row.
- Apps that do not expose a URL get no Reopen button; the row opens (activates or launches) the app. This includes **Finder**, which exposes a title but no folder URL (hardware_findings.md).

Squeegee stores the last **1000** closure records on disk, first in, first out (the V1 menu shows 8; the P2 history window will show all).

## 10. Settings Window

The app window is in practice only settings. This section lists its **functional content**. The layout (one screen or sections, and how it relates to the menu bar) is decided in the UI design step.

### 10.1 General

- Launch at login (toggle, default on).
- Show menu bar icon (toggle, with the reopen instruction from §8.3).
- Pause status and controls (same as §5.5).
- Accessibility permission status, with Open System Settings when missing.

### 10.2 Apps

- A list: "All other apps" (the global rule) at the top, then all app rules sorted by app name, with icon and a rule summary.
- Selecting a row shows the rule editor (§4.1 fields).
- **Add app** (+): choose from running apps or pick an app from Finder.
- **Remove** an app rule (the app goes back to the global rule). Removal asks for confirmation naming the app.
- **Add suggested rules:** opens the Suggestions view (§7.1).

### 10.3 About

Version, and a link to the project site.

## 11. Suggested Rules Catalog

A built-in list. Bundle IDs are verified during implementation; apps not found are ignored. Focus: windows that are safe to close because the app restores its state, has no unsaved data, or keeps running in the background.

| Category | App (bundle ID) | Close after | Measure from | Quit when last window closed | Why |
|---|---|---|---|---|---|
| Files | Finder (`com.apple.finder`) | 6 h | Last active | n/a | Folder windows pile up; no data loss. |
| Files | Preview (`com.apple.Preview`) | 12 h | Last active | off | Read-only viewing in most cases. |
| Media | Photos (`com.apple.Photos`) | 2 h | Last active | off | Uses a lot of resources; no data loss. |
| Media | QuickTime Player (`com.apple.QuickTimePlayerX`) | 2 h | Last active | **Always** | Stays running with no windows; no data loss. |
| Media | VLC (`org.videolan.vlc`) | 2 h | Last active | **Always** | Same as QuickTime. |
| Media | IINA (`com.colliderli.iina`) | 2 h | Last active | **Always** | Same as QuickTime. |
| Media | Music (`com.apple.Music`) | 6 h | Last active | off | Playback continues without the window. |
| Media | Spotify (`com.spotify.client`) | 6 h | Last active | off | Playback continues without the window. |
| Messaging | Messages (`com.apple.MobileSMS`) | 4 h | Last active | off | New messages still notify. |
| Messaging | Slack (`com.tinyspeck.slackmacgap`) | 4 h | Last active | off | Keeps running and notifying. |
| Messaging | Discord (`com.hnc.Discord`) | 4 h | Last active | off | Keeps running and notifying. |
| Messaging | WhatsApp (`net.whatsapp.WhatsApp`) | 4 h | Last active | off | Keeps running and notifying. |
| Messaging | Signal (`org.whispersystems.signal-desktop`) | 4 h | Last active | off | Keeps running and notifying. |
| Messaging | Telegram (`ru.keepcoder.Telegram`) | 4 h | Last active | off | Keeps running and notifying. |
| Background apps | 1Password (`com.1password.1password`) | 1 h | Last active | off | Menu bar / background mode; no state. |
| Background apps | Granola (bundle ID TBD) | 2 h | Last active | off | Background mode; no state. |
| System | System Settings (`com.apple.systempreferences`) | 1 h | Last active | **If closed by Squeegee** | No state. |
| System | App Store (`com.apple.AppStore`) | 1 h | Last active | **If closed by Squeegee** | No state. |
| System | Activity Monitor (`com.apple.ActivityMonitor`) | 2 h | Last active | **If closed by Squeegee** | No state. |

## 12. Persistence

Stored locally on disk (no network, no telemetry, no accounts):

- Global rule and app rules.
- General settings (menu bar icon, pause state). Launch at login uses the system login item state.
- Onboarding completed flag.
- Tracked window times (opened, last active, close sent) for restore after a Squeegee restart (§3.2).
- Last 1000 closure records (§9).

## 13. Edge Cases

| Case | Behavior |
|---|---|
| Target app quits or crashes | Its windows are no longer tracked. Nothing is recorded as a closure. |
| Target app relaunches and restores windows | Restored windows are new windows (opened = first seen). |
| Window moves between Spaces, is minimized, or goes full-screen | Same window; times are kept. Minimized and other-Space windows are never "active" until the user brings them forward. |
| Closing a full-screen window | Allowed. macOS removes its Space. While the user is not on its Space, its title and URL are not readable; the last known values are kept. macOS also adds an extra window for a full-screen window; it stays unmanaged until Squeegee can inspect it. |
| Window title changes (e.g. Finder navigates) | Same window; the title shown in the UI updates. The closure record uses the title at close time. |
| App does not respond to close | Squeegee does not wait or retry (§5.3). The app remains as it is. |
| Rule edited | Deadlines are calculated again at the next check, with the new values. |
| Rule enabled for an app with old windows | Deadlines use the existing tracked times, so old windows can close at the next check. **P2:** when the user changes a rule and the new rule would close open windows right away, show a confirmation: "This rule calls for N open windows to be closed." with Cancel / Save. This applies to every rule change (edit, enable, add, or remove), not only the global rule. |
| Mac wakes from sleep with many windows past their deadline | They close at the next check (no special case in V1). |
| Multiple displays | No difference. |
| Accessibility revoked while running | See §6. |

## 14. Constraints

- **macOS 15 or later.** macOS 14 support only if it costs nearly nothing.
- **Distribution:** Developer ID signed and notarized, as a DMG. Not the Mac App Store.
- **Native UI:** SwiftUI and AppKit only. No web views, no HTML.
- **Resource use:** Idle CPU use must be very low (below 1% average), and there must be no noticeable energy impact in Activity Monitor.
- **Privacy:** Window titles and URLs stay on the Mac. No network access.
- **Testability (carried from Biscotti):** Almost all logic (rules, timers, deadlines, the close decision, persistence, view models) lives in a Swift package that is fully tested with `swift test`, with no app, signing, or real windows. The app target is a thin shell. Real system behavior (window APIs, permissions) is checked with a ManualTestApp on real hardware. The architecture step defines this in detail.
- **Dry run:** the close decision must be able to run on a **draft** rule set against the current windows ("what would close if this rule set applied now"), with no side effects. Tests use it, and the P2 confirmation (§13) uses it to count windows.

## 15. To Verify on Real Hardware

These come from gaps in the research. The architecture must plan a way to test them (e.g. in a manual test app):

- The private window ID bridge (`_AXUIElementGetWindow`) on macOS 26.
- Close behavior on an app that does not respond (timeouts).
- Document/folder URL access for Finder, Preview, and QuickTime (for Reopen). **Done:** Preview and QuickTime yes, Finder no.
- Close button behavior on tabbed windows (Finder). **Done:** each tab is its own window.
- Timer accuracy while the app is in App Nap. **Open** (backlog).

Results: hardware_findings.md.
