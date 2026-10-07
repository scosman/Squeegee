---
status: complete
---

# UI Design: Squeegee

Visual and interaction design for the behavior in `functional_spec.md`. Section references (§N) point to the functional spec.

## 1. Principles

- **Exceptionally Apple native** (§1.1). Standard AppKit/SwiftUI controls, SF Symbols, system fonts, the **system accent color**. No custom colors, fonts, or visual language.
- **Light and dark appearance** both supported (standard controls do this for free).
- **Two surfaces only:** the menu bar menu (daily use) and one app window (onboarding, then settings).
- **Per app, not per window.** Windows are shown for context (time left), never with per-window actions.
- **Progressive disclosure.** Simple defaults first; custom duration and quit options appear only when relevant.

## 2. Surfaces and Navigation

```
                 ┌────────────────────┐
  first launch → │ App window:        │ → Get Started → (window closes)
                 │ Onboarding route   │
                 └────────────────────┘
┌──────────────┐  Settings… / click a row   ┌────────────────────┐
│ Menu bar menu│ ─────────────────────────→ │ App window:        │
└──────────────┘                            │ Settings route     │
   open app again from Finder/Spotlight ──→ └────────────────────┘
```

- **One app window**, with two routes: Onboarding (until complete) and Settings. The same pattern as Biscotti's main window.
- **Dock presence:** Squeegee is menu bar only. While the app window is open, it shows in the Dock and Cmd-Tab. When the window closes, it goes back to menu bar only.
- **Cmd-Q** closes the main window (same as clicking the close button) instead of quitting the app. Quitting is only via the menu bar "Quit Squeegee" item.
- **User-initiated launch** (Dock, Finder, Spotlight, Launchpad, `open`, Xcode Run) opens the app window at the current route (Settings after onboarding; Onboarding before). This applies to both cold launch and reopen while running.
- **Login-item launch** (system starts the app at login via `SMAppService.mainApp`) is silent: menu bar only, no window. Detected via `keyAELaunchedAsLogInItem` in the `kAEOpenApplication` Apple event.
- Opening the app again (Finder, Spotlight, Launchpad) while it runs opens the app window at the Settings route (§8.3). During onboarding, it opens the onboarding.

## 3. Menu Bar

### 3.1 Icon

A template image (monochrome, adapts to menu bar appearance). The normal state uses a custom squeegee SVG from the MenuBarUI asset catalog; other states use SF Symbols:

| State | Icon |
|---|---|
| Normal | Custom squeegee SVG (`Media.xcassets/squeegee`) |
| Paused | SF Symbol `pause.rectangle` |
| Permission missing | SF Symbol `exclamationmark.triangle` |

### 3.2 Menu structure

A native `NSMenu` (standard menu, not a custom panel). Rows use a title plus a **subtitle** (`NSMenuItem.subtitle`, macOS 14.4+) and the app icon at 16 pt. Sections use native section headers.

```
[⚠ Accessibility Access Needed…]         ← only if permission missing
[Paused until 3:40 PM]  (disabled)       ← only if paused
[Resume]                                 ← only if paused
─────────────
Closing Next                             ← section header
📁 Downloads
   Finder · in 2h 10m
🎬 trailer.mov
   QuickTime Player · in 3h 05m
   …up to 8 rows
3 more                    (disabled)     ← only if more than 8
─────────────
Recently Closed                          ← section header
📄 Report.pdf
   Preview · 20m ago
💬 Messages
   1h ago
🎬 QuickTime Player
   Quit · 2h ago
   …up to 8 rows
─────────────
Pause                              ▸     ← submenu: For 1 Hour / Until Tomorrow / Until Resumed
Settings…                         ⌘,
Quit Squeegee                ⌘Q
```

**Rows and actions**

| Row | Title | Subtitle | Click action |
|---|---|---|---|
| Closing Next | window title (app name if no title) | `App · in 2h 10m`; `App · waiting — in use` if past deadline and focused | Open app window at this app's rule (or "All other apps" if the global rule covers it) |
| Recently Closed — window with URL | window title | `App · 20m ago` | **Reopen** the document (§9) |
| Recently Closed — window without URL | window title | `App · 20m ago` | Open (activate or launch) the app |
| Recently Closed — app quit | app name | `Quit · 2h ago` | Launch the app |
| Recently Closed — URL no longer exists | window title | `App · File not found` | Disabled |

Every clickable Recently Closed row has a tooltip that states what the click does ("Reopen Report.pdf in Preview", "Open Finder").

**States**

- **Permission missing:** the top item "Accessibility Access Needed…" opens System Settings → Privacy & Security → Accessibility. The Closing Next section shows one disabled row: "Paused — needs Accessibility access". Recently Closed still shows.
- **Paused:** the top shows "Paused until 3:40 PM" (or "Paused" for until-resumed) and a **Resume** item. Closing Next still lists windows and times, so the user can see what will close after the pause ends. In the Pause submenu, the active option has a checkmark.
- **Empty Closing Next:** one disabled row, "No windows scheduled to close". Subtitle: "Add rules in Settings".
- **Empty Recently Closed:** one disabled row, "Nothing closed yet".

The menu is built when it opens. Times do not update while it is open (they have minute granularity).

## 4. App Window — Settings Route

A standard single window titled "Squeegee". Default size 760×540, minimum 640×440, resizable. `NavigationSplitView` with a sidebar (about 220 pt) and a detail pane. Sidebar collapse prevention is a known open item.

### 4.1 Sidebar

```
⚙ General
RULES                          ← section header
▢ All other apps
  Off
📁 Finder
  6h · last active
🎬 QuickTime Player
  2h · last active · quits
💬 Messages
  4h · last active
…
[+] [−]                         ← bottom bar (no chevron)
```

- **General** row: `gearshape` symbol.
- **All other apps:** always the first rule row. Symbol `square.stack`. Subtitle is the rule summary (§7).
- **App rows:** app icon (20 pt), app name, rule summary subtitle. Sorted by app name. Disabled rules show "Off".
- **Bottom bar** (+ button only, no chevron indicator):
  - **+** is a menu button (no menu indicator chevron):
    - **Running Apps** ▸ submenu: running regular apps that have no app rule, sorted by name. The list is queried fresh each time the menu opens.
    - **Choose App…**: an open panel in `/Applications` that accepts only `.app` bundles.
    - divider
    - **Suggested Rules…**: opens the Suggestions sheet (§4.5).
  - **−** removes the selected app rule. It is enabled only when an app rule is selected (disabled for General and "All other apps"). Clicking it shows the `RemoveRuleSheet` confirmation (same flow as the Delete key). It must not remove without confirmation.
- A new app rule starts with: enabled, 6 hours, Last active, Keep app running. The new row is selected.
- If the user adds an app that already has a rule, that rule is selected (no duplicate).
- The selection is restored when the window reopens.

### 4.2 General page

A grouped `Form`.

| Section | Rows |
|---|---|
| Status | **Accessibility Permission:** "✓ Granted" (secondary text) or "Not granted" + **Open System Settings** button. **Pause State:** **Pause ▾** menu button (same options as §3.2), sized to content (`.fixedSize()`), when not paused (no "Active" status text), or "Paused until 3:40 PM" / "Paused" status text + **Resume** button when paused. |
| Startup | **Launch at login** toggle. |
| Menu Bar | **Show menu bar icon** toggle. Footer (caption2 size, tertiary color): "When the icon is hidden, open Squeegee again from Finder or Spotlight to show this window." |
| About | Version (e.g. "Version 1.0 (42)") and a link to the project site. |

### 4.3 Rule page

A grouped `Form`. It is the same for app rules and the global rule, except where noted.

```
[icon 48]  Finder                               ← header (not a form row)

Close windows automatically            [ ON ]

Close after                        [ 6 hours ▾]
Measure from                   [ Last active ▾]
  (each option has a subtitle in the dropdown)

When the last window closes   [ Keep app running ▾]
  (each option has a subtitle in the dropdown)

OPEN WINDOWS (3)
Downloads                              in 2h 10m
Projects                               in 5h 40m
Screenshots                   waiting — in use

                                [Remove Rule…]
```

- **Header:** app icon (48 pt) and app name. For the global rule: `square.stack` symbol, "All other apps", and the subtitle "Applies to every app that doesn't have its own rule."
- **Close windows automatically:** a toggle. When off, the sections below it are disabled (dimmed), and the Open Windows times show "Won't close".
- **Close after:** a pop-up menu: 1 minute, 30 minutes, 1 hour, 2 hours, 4 hours, 6 hours, 12 hours, 1 day, 2 days, 1 week, divider, Custom…. When Custom is selected, a row shows below it with **hours** and **minutes** fields plus steppers. The range is limited to 1 minute – 30 days, and the value is clamped when the field loses focus. If a saved value is not a preset, the pop-up shows "Custom" and the custom row is visible.
- **Measure from:** a pop-up menu with **Last active** and **Opened**. Each option has an `NSMenuItem.subtitle` in the dropdown:
  - Last active: "Time since you last used the window (focused for 5 seconds or more)."
  - Opened: "Time since the window opened, or since Squeegee first saw it."
- **When the last window closes:** a pop-up menu with **Keep app running**, **Quit if Squeegee closed it**, **Always quit app**. Each option has an `NSMenuItem.subtitle` in the dropdown. This section is **hidden** for the global rule and for Finder.
- **Open Windows (N):** a read-only list of this app's managed windows (for the global rule: all windows covered by it, with the app icon on each row). Each row: window title (app name if there is no title) and time left, with the same text as the menu (§7). Sorted by time left. It updates live (once per minute, and immediately when the rule changes). Empty: "No open windows". For the global rule, each row has a trailing **+** button that creates an app-specific rule for that window's app and selects it (the button does not appear if the app already has a rule).
- **Remove Rule…:** a plain (non-destructive) push button right-aligned below the last form section, outside the grouped section boxes (app rules only). The ellipsis signals that it asks for confirmation. Clicking it shows the `RemoveRuleSheet` confirmation naming the app ("Remove the rule for [App Name]?" / "The app will use the global rule." / Cancel + Remove). The confirmation is a custom SwiftUI `.sheet` (not `.confirmationDialog` or `.alert`, because both macOS system presentations render as an NSAlert panel that shows the app icon). The same confirmation is also reachable via the sidebar **−** button and the Delete key.
- All changes apply immediately. There is no Save button (§4.2 of the functional spec).

### 4.4 Permission banner

When Accessibility is missing, a banner shows at the top of **every** detail page: a yellow `exclamationmark.triangle` symbol, the text "Squeegee needs Accessibility access to close windows.", and an **Open System Settings** button. It is a standard inset `GroupBox`-style row, not a custom colored bar. It goes away as soon as the permission is granted.

### 4.5 Suggestions sheet

This sheet opens from **+ → Suggested Rules…**. It uses the same list component as onboarding step 3 (§5.3), inside a standard sheet:

- Title: "Suggested Rules".
- The list shows only catalog apps that are installed and have no app rule. All rows are checked by default.
- Buttons: **Cancel** and **Add N Rules** (default button; disabled when N = 0).
- Empty state: "All suggested apps already have rules." with a **Done** button.

## 5. App Window — Onboarding Route

This follows the **layout** of Biscotti's onboarding (`OnboardingScaffold`), with system fonts and the system accent color in place of Biscotti's custom tokens.

### 5.1 Scaffold

```
            ━━━━━━━━━──────────────          ← progress bar, 240×3, accent fill
                  PERMISSIONS                ← kicker
            
            
             [large centered title]
          [lead text, max ~440 pt wide]
          
          [screen content, max 520 pt]
          
          
             [ Primary Button ]              ← full-width in content column, height 40
                    Skip                     ← only where allowed
                    
            [app icon] Squeegee         ← brand footer
          Clean your windows.
```

- The window is the same app window. While onboarding runs, it is not resizable, at a fixed size of 640×600, and has no sidebar. The title bar is hidden; the traffic lights float at top left.
- **Progress bar:** a capsule track (`.quaternary` fill) with an accent-color fill of `(step)/4`.
- **Kicker:** `.caption`, semibold, uppercase, wide tracking, secondary color.
- **Title:** `.largeTitle`, semibold. **Lead:** `.title3`, secondary color.
- **Primary button:** `.borderedProminent`, `.large` control size.
- **Skip:** a plain text button, secondary color.
- **Brand footer:** app icon (16 pt) + "Squeegee" (`.headline`) + tagline (`.caption`, tertiary).
- Navigation is forward only. There is no Back button.

### 5.2 Screens

| # | Kicker | Title | Lead / content | Buttons |
|---|---|---|---|---|
| 1 | WELCOME | Welcome to Squeegee | App icon (96 pt) above the title. Lead: "Squeegee closes windows you've stopped using, based on rules you set for each app. Nothing closes until you turn it on." | Continue |
| 2 | PERMISSIONS | Allow Accessibility Access | Lead: "Squeegee uses Accessibility to see and close windows of other apps. Nothing leaves your Mac." A card with one row: an icon tile (`accessibility` symbol on an accent-tinted rounded square), "Accessibility", "Lets Squeegee close windows", and at the trailing edge a **Grant** button (`.borderedProminent`, small), or a **Granted** tag (accent `checkmark.circle.fill` + "Granted"). Below the card, help text: "macOS opens System Settings. Turn on Squeegee, then come back here." | Continue (enabled when granted), Skip (shown until granted) |
| 3 | SUGGESTIONS | Pick Apps to Tidy | Lead: "These apps are safe to clean up. You can change any rule later in Settings." Then the suggestions list (§5.3). | Continue |
| 4 | FINISH | You're All Set | Lead: "Squeegee runs in the menu bar. Click [inline menu bar glyph] to see what closes next, or to change settings." | Get Started |

- **Grant** calls the system prompt and opens System Settings at the Accessibility pane. The screen checks the permission state again while it shows (and when the app becomes active), and changes to **Granted** without a restart.
- After **Get Started**, the window closes and the app goes back to menu bar only.

### 5.3 Suggestions list (shared component)

A card (rounded, `.background.secondary`-style fill, standard separators) with a scroll view inside it, for long lists:

```
FILES
[✓] 📁 Finder            Close windows 6h after last use
[✓] 👁 Preview           Close windows 12h after last use
MEDIA
[✓] 🎬 QuickTime Player  Close windows 2h after last use, then quit
[ ] 🖼 Photos            Close windows 2h after last use
MESSAGING
…
                                             8 selected
```

- Category headers use the kicker style.
- Row: checkbox, app icon (24 pt), app name, and a secondary one-line summary in sentence form (§7). The whole row toggles the checkbox.
- A count below the list: "N selected".
- Empty state (no catalog apps installed): the text "None of the suggested apps are installed. You can add rules for any app later in Settings." In onboarding, Continue is still enabled.

## 6. Copy

- The app name is always "Squeegee" (one word).
- Use sentence case for body text and footers. Use title case for menu items, buttons, and window/screen titles (Apple HIG).
- There is no text that says what the user "must" do. The text states what occurs.

## 7. Formatting

| Item | Format | Examples |
|---|---|---|
| Time left | `in` + largest two units, compact | `in 2h 10m`, `in 45m`, `in 3d 4h`, `in <1m` |
| Past deadline, focused | fixed text | `waiting — in use` |
| Past deadline, paused | time left shown as `due now` | `due now` |
| Rule disabled | fixed text | `Won't close` |
| Time ago | relative, compact | `just now`, `20m ago`, `3h ago`, `yesterday`, then a short date `Sep 12` |
| Rule summary (sidebar) | duration · measure · quit | `6h · last active`, `2h · opened · quits`, `Off` |
| Rule summary (suggestions) | sentence | `Close windows 6h after last use`, `…, then quit` |
| Paused until | time of day for today, weekday + time otherwise | `Paused until 3:40 PM`, `Paused until Tue 6:00 AM` |

"quits" in the summary means that the option is not "Keep app running" (both quit options).

## 8. Accessibility (VoiceOver)

- All controls are standard, so they have default labels. Custom rows (sidebar rows, open window rows, suggestion rows) combine their parts into one element with a full label, e.g. "Finder, close windows after 6 hours since last active".
- The progress bar has the label "Step 2 of 4".
- Menu items use their title and subtitle as the label.
