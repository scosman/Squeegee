# Evaluation of Proposed Activity Heuristics

This document evaluates the user's proposed heuristics for deciding when a window is "active" and recommends a practical approach.

## User's Proposed Heuristics

### 1. "Never entered foreground"

**Definition:** A window that has never been part of the frontmost app since Squeegee started observing.

**Assessment: Strong signal, recommended.**

If a window's owning app has never been activated (per `NSWorkspace.didActivateApplicationNotification`), the user has never interacted with that window. This is the safest class of window to close — it was opened by some background process or left over from a previous session.

**Implementation:** Track per-app foreground timestamps. Any window whose app has never been in the foreground since observation began (or since the window was first seen) is a candidate for early closure.

**Edge cases:**
- Apps that launch at login and open windows the user never asked for (e.g., "What's New" dialogs) — correctly caught by this heuristic.
- Multi-window apps where only some windows were visible when the app was last frontmost — this heuristic does not distinguish them (Accessibility needed for per-window focus).
- Windows on other Spaces that the user has used but not switched to recently — their app may have been frontmost on that Space. The `didActivateApplicationNotification` fires for *any* Space, so this is handled correctly.

**No permission needed.**

---

### 2. "Never in foreground for 5s+"

**Definition:** A window whose app was in the foreground, but only briefly (under 5 seconds), suggesting the user switched through it accidentally or only glanced at it.

**Assessment: Moderate signal, useful as a secondary tier.**

This catches the case where a user Cmd-Tabs past an app without intending to use it. A 5-second threshold distinguishes "passed through" from "used."

**Implementation:** On `didActivateApplicationNotification`, record the timestamp. On `didDeactivateApplicationNotification`, compute the duration. If the app was frontmost for less than 5 seconds, do not update the "last active" timestamp for its windows.

**Risks:**
- A user who quickly checks something (reads a notification, glances at a dashboard) may legitimately use a window for under 5 seconds. Closing those windows after the timer expires could be annoying.
- **Recommendation:** Use this as a *separate tier* with a shorter close threshold, not as a binary "active/not active" gate. For example: windows never in foreground for 5s+ close after N hours; windows that were in foreground for 5s+ close after 2N hours. The exact thresholds are UX decisions, not API decisions.

**No permission needed** (uses only `NSWorkspace` activate/deactivate notifications).

---

### 3. "Moved position" (user's note: weak)

**Definition:** A window whose `kCGWindowBounds` changed, indicating the user moved or resized it.

**Assessment: Weak signal, agree with user's assessment.**

**Why it's weak:**
- Most users do not move windows they are actively using. A window can be heavily used without ever being repositioned.
- Conversely, window management tools (Rectangle, Magnet, Stage Manager) can move windows programmatically, generating false positives.
- macOS itself moves windows during Space transitions and display configuration changes.

**Why it might still be useful:**
- A manual move/resize is a strong indicator of intentional interaction — if detected, it is a reliable "this window is definitely active" signal.
- It is available without Accessibility permission (via `CGWindowListCopyWindowInfo` polling).

**Recommendation:** Use as a *supplementary* signal that resets the close timer, but never use the *absence* of movement as evidence of inactivity. In other words: "moved" = definitely active; "not moved" = no information.

**No permission needed** (polling `kCGWindowBounds` from `CGWindowListCopyWindowInfo`).

---

## Additional Heuristics Worth Considering

### 4. "On-screen state changed" (appeared on screen)

A window transitioning from off-screen (`kCGWindowIsOnscreen` absent) to on-screen (`true`) indicates the user unminimized it, switched to its Space, or unhid its app. This is a meaningful activity signal.

**No permission needed** (polling `CGWindowListCopyWindowInfo`).

### 5. "User was idle, subtract idle time"

Use `CGEventSource.secondsSinceLastEventType` to freeze close timers during extended user absence. If the user is idle for 30 minutes, do not count those 30 minutes against any window's age.

**Implementation options:**
- **Simple:** Freeze all timers when idle exceeds threshold (e.g., 5 min). Resume on input.
- **Proportional:** Track cumulative idle time and subtract from window age.
- **Recommendation:** Simple freeze is easier to reason about and explain to users.

**No permission needed.**

### 6. "Frontmost window in the app" (Accessibility only)

With `kAXFocusedWindowChangedNotification`, you can track which specific window within a multi-window app the user is interacting with. This is the highest-fidelity signal and the main reason to request Accessibility permission.

**Accessibility permission required.**

---

## Recommended Heuristic Stack

Listed from strongest to weakest signal:

| Priority | Signal | Permission | Resets timer? |
|---|---|---|---|
| 1 | App entered foreground for 5s+ | None | Yes, for all windows of that app |
| 2 | Specific window gained AX focus | Accessibility | Yes, for that specific window |
| 3 | Window appeared on-screen | None | Yes |
| 4 | Window moved/resized | None | Yes |
| 5 | App entered foreground for <5s | None | Partial (extend by 50%, not full reset) |
| - | User idle | None | Freeze all timers |
| - | Display/system sleep | None | Freeze all timers |

### Without Accessibility:
Activity tracking is per-app, not per-window. When an app is frontmost, all its windows get their timer reset. This is conservative (windows stay open longer than strictly necessary) but safe.

### With Accessibility:
Activity tracking is per-window. Only the focused window gets its timer reset. This is more aggressive about closing unused windows but more accurate.

---

## Accuracy Limits

### Focused window in a non-frontmost app

A background app's `kAXFocusedWindowAttribute` returns the window that was focused when the app was *last* frontmost. It does not update while the app is in the background. This means you cannot know which window the user will interact with *next* when they switch to that app.

**Implication:** The best you can do is record "the user last focused window X in app Y at time T." You cannot predict future focus.

### Split-screen / multiple displays

An app can be visible on one display while a different app is frontmost on another display. `didActivateApplicationNotification` fires for the app the user most recently clicked, but the other visible app's windows are still on-screen and potentially being read.

**Implication:** Consider on-screen time (visible on any display) as a weaker but valid activity signal, separate from frontmost-app time. A window that is visible for 2 hours but never frontmost is likely being monitored/referenced.

### Fullscreen apps

A fullscreen app occupies its own Space. Switching to/from it fires both `activeSpaceDidChangeNotification` and `didActivateApplicationNotification`. No special handling needed — these are the same signals.

Sources:
- [Apple Developer Forums — frontmost app detection](https://developer.apple.com/forums/thread/129903)
- [native-devtools-mcp PR #13 — focus vs z-order](https://github.com/vectora-foundry/native-devtools-mcp/pull/13)
- [Apple docs: didActivateApplicationNotification](https://developer.apple.com/documentation/appkit/nsworkspace/didactivateapplicationnotification)
