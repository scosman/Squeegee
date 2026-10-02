---
status: complete
---

# Component: Engine (tracker, planner, executor) and `AppCore`

This doc covers the decision core (the `Engine` module, which is pure) and the orchestration in `AppCore`, which connects the ports (system_layer.md), the store (architecture.md §4), and the UI.

## 1. Shape

```
events ──► TrackerReducer.reduce(&TrackerState, TrackerEvent) ──► [TrackerOutput]
                                   │
RuleSet + TrackerState + now + flags ──► Planner.plan(PlanInput) ──► Plan { schedules, actions, nextWakeAt }
                                   │
AppCore executor ──► ports (close / quit) ──► results become TrackerEvents
```

`TrackerReducer` and `Planner` are `enum` namespaces with `static` functions. They do no I/O and read no clock. Every time value is passed in.

## 2. Types (`Engine`)

```swift
public enum CloseState: Sendable, Equatable {
    case none                                    // eligible
    case sent(at: Date, wasListed: Bool)         // AXPress delivered; waiting for verification
    case declined(at: Date)                      // app kept the window (save dialog etc.); no retry until active again
    case unreachable(since: Date)                // no AX element / press on another Space did nothing; retry when AX lists it
}

public struct TrackedWindow: Sendable, Equatable {
    public let key: WindowKey
    public var bundleID: String
    public var appName: String
    public var firstSeen: Date
    public var lastActive: Date?                 // end time of the most recent qualifying focus session
    public var metadata: WindowMetadata?         // nil until an AX inspection lists it
    public var closeState: CloseState
}

public enum QuitState: Sendable, Equatable { case none, sent(at: Date), declined }

public struct TrackedApp: Sendable, Equatable {
    public let pid: Int32
    public var bundleID: String
    public var appName: String
    public var launchDate: Date?
    public var hadStandardWindow: Bool           // true once any window with metadata.isStandard == true was seen
    public var noStandardWindowsSince: Date?     // set when the present-window count drops to 0 (only if hadStandardWindow)
    public var quitAfterSqueegeeClose: Bool // set when a Squeegee close emptied the app
    public var quitState: QuitState
}

public struct FocusSession: Sendable, Equatable { public let key: WindowKey; public let start: Date }

public struct TrackerState: Sendable, Equatable {
    public var windows: [WindowKey: TrackedWindow] = [:]
    public var apps: [Int32: TrackedApp] = [:]
    public var frontmostPID: Int32?
    public var focusedKey: WindowKey?            // focused window of the frontmost app (kept during display sleep)
    public var session: FocusSession?            // activity measurement; nil while displays sleep
}

public enum TrackerEvent: Sendable, Equatable {
    case windowList([ObservedWindow], at: Date)
    case inspected(pid: Int32, InspectionResult, at: Date)
    case focusChanged(app: ObservedApp?, windowID: UInt32?, at: Date)
    case displaysSlept(at: Date)
    case appTerminated(pid: Int32, at: Date)
    case closeSent(WindowKey, wasListed: Bool, latest: WindowMetadata?, at: Date)
    case closeUnreachable(WindowKey, at: Date)
    case closeFailed(WindowKey, at: Date)         // noCloseButton handled separately
    case closeHasNoButton(WindowKey)
    case closeVerification(WindowKey, at: Date)   // fired 10 s after closeSent
    case quitSent(pid: Int32, at: Date)
    case quitVerification(pid: Int32, at: Date)   // fired 30 s after quitSent
}

public enum TrackerOutput: Sendable, Equatable {
    case windowClosedBySqueegee(TrackedWindow, at: Date)
    case appQuitBySqueegee(TrackedApp, at: Date)
    case needsInspection(pid: Int32)
    case permissionLost
}

// TrackedWindowSnapshot removed: perf project — tracked window state is in memory only.
```

Constants: `Tracker.focusQualifyingDuration = 5`, `Tracker.alwaysQuitGrace = 60`, `Tracker.closeVerificationDelay = 10`, `Tracker.quitVerificationDelay = 30`.

## 3. Focus accounting

This measures "active" exactly, with event timestamps and no sampling (functional spec §3.3).

- A **session** is the time one window is the focused window of the frontmost app, while the displays are awake.
- A session **qualifies** when `end - start >= 5 s`.
- **Ending a session at time `t`:** if `t - start >= 5`, then the window's `lastActive = t`, and its `closeState = .none` (it is "active again", so the one-attempt rule resets; functional spec §5.3). Otherwise nothing changes.
- **Effective last active (planner):** if `session.key == w.key && now - session.start >= 5`, then `now`. Otherwise `w.lastActive`.
- `focusedKey` is separate from `session`. It stays set while the displays sleep, so the "never close the focused window of the frontmost app" rule still protects that window. Only activity measurement stops.

## 4. `TrackerReducer.reduce(_ state: inout TrackerState, _ event: TrackerEvent) -> [TrackerOutput]`

**`.windowList(observed, at)`** (a full CG scan):

1. For each observed window not in `state.windows`: insert a `TrackedWindow` with `firstSeen = at`, `metadata = nil`, and `closeState = .none`. Insert `TrackedApp` for a new pid with `hadStandardWindow = false`, `quitState = .none`, and the other fields empty.
2. For each tracked window **not** in `observed`: remove it.
   - If its `closeState` is `.sent` or `.declined`, output `.windowClosedBySqueegee(window, at)`. If after that its app has no present windows, set `app.quitAfterSqueegeeClose = true`.
   - A removed `focusedKey` / `session` window clears those fields. The session ends without qualifying, because the window is gone.
3. Collect the pids that have windows with `metadata == nil` → output `.needsInspection(pid)` once per pid.
4. Recompute the presence of each app (below).

**Present windows of an app** = its tracked windows where `metadata == nil || metadata.isStandard`. Unknown windows count as present; this is conservative and prevents a quit.

**Presence recompute (per app):**
- If present count > 0: `noStandardWindowsSince = nil`, `quitAfterSqueegeeClose = false`, and if `quitState == .declined`, then `quitState = .none`.
- Else if `hadStandardWindow && noStandardWindowsSince == nil`: set `noStandardWindowsSince = at`.

**`.inspected(pid, result, at)`:**
- `.inspected(map)`: for each `(windowID, meta)`:
  - If the window is tracked: set `metadata = meta`. If `closeState == .unreachable`, change it to `.none` (it is reachable now).
  - If it is not tracked: insert it with `firstSeen = at` (AX saw it before the CG scan did).
  - If `meta.isStandard`: `app.hadStandardWindow = true`.
  - Tracked windows of this pid that are not in `map` keep their old metadata (they are on another Space).
  - Then recompute presence.
- `.appUnavailable`: no change.
- `.notTrusted`: output `.permissionLost`.

**`.focusChanged(app, windowID, at)`:**
1. End the current session at `at` (§3).
2. `state.frontmostPID = app?.pid`.
3. If `app` and `windowID` are non-nil: `key = WindowKey(app.pid, windowID)`. If `key` is not tracked, insert it (`firstSeen = at`, `metadata = nil`) and output `.needsInspection(pid)`. Then `focusedKey = key` and `session = FocusSession(key, start: at)`.
4. Else: `focusedKey = nil`, `session = nil`.

**`.displaysSlept(at)`:** end the session at `at` and set `session = nil`. Keep `focusedKey` and `frontmostPID`. On wake, `AppCore` sends a new `.focusChanged` (§5).

**`.appTerminated(pid, at)`:**
- Remove the app's windows. These are **not** closure records (functional spec §13), even if `closeState == .sent`.
- If `app.quitState == .sent`, output `.appQuitBySqueegee(app, at)`.
- Remove the app. Clear `focusedKey` / `session` / `frontmostPID` if they point to it.

**Close lifecycle events:**
- `.closeSent(key, wasListed, latest, at)`: `closeState = .sent(at, wasListed)`. If `latest != nil`, `metadata = latest` (the freshest title and URL for the closure record).
- `.closeUnreachable(key, at)`: `closeState = .unreachable(since: at)`.
- `.closeFailed(key, at)`: `closeState = .declined(at)`. This means no retry loop on an AX error.
- `.closeHasNoButton(key)`: `metadata?.isStandard = false`. The window becomes unmanaged.
- `.closeVerification(key, at)`: if the window is still tracked and still `.sent(_, wasListed)`:
  - `wasListed == true` → `.declined(at)` (the app kept it open).
  - `wasListed == false` → `.unreachable(since: at)` (the press on another Space did nothing; retry when AX lists it).

  If the window is gone, this is a no-op; the scan already recorded it.

**Quit lifecycle events:**
- `.quitSent(pid, at)`: `quitState = .sent(at)`.
- `.quitVerification(pid, at)`: if the app still exists and `quitState == .sent`, set `.declined`. It is reset to `.none` only when the app has a present window again (presence recompute). There is no quit retry loop.

<!-- .restore event removed: perf project — tracked window state is in memory only -->

## 5. `Planner`

```swift
public struct PlanInput: Sendable {
    public var ruleSet: RuleSet
    public var state: TrackerState
    public var now: Date
    public var isPaused: Bool
    public var pausedUntil: Date?
    public var hasPermission: Bool
}

public enum ScheduleStatus: Sendable, Equatable {
    case scheduled                // deadline in the future
    case dueInUse                 // past deadline, focused window of frontmost app
    case duePaused                // past deadline, paused or no permission
    case dueUnreachable           // past deadline, waiting for AX reach (other Space)
    case closing                  // close sent, awaiting verification
    case keptOpen                 // declined; waits until used again
    case disabled                 // rule off
}

public struct WindowSchedule: Sendable, Equatable, Identifiable {
    public var id: WindowKey { key }
    public let key: WindowKey
    public let bundleID: String
    public let appName: String
    public let title: String?
    public let ruleSource: ResolvedRule.Source
    public let deadline: Date?           // nil when disabled
    public let status: ScheduleStatus
}

public enum PlannedAction: Sendable, Equatable {
    case closeWindow(WindowKey)
    case quitApp(pid: Int32)
}

public struct Plan: Sendable, Equatable {
    public var schedules: [WindowSchedule]   // managed windows only
    public var actions: [PlannedAction]
    public var nextWakeAt: Date?
    public static let empty: Plan
}

public struct DryRunResult: Sendable, Equatable {
    public let windowsToClose: [WindowSchedule]
    public let appsToQuit: [TrackedApp]
}

public enum Planner {
    public static func plan(_ input: PlanInput) -> Plan
    public static func dryRun(ruleSet: RuleSet, state: TrackerState, now: Date) -> DryRunResult
}
```

**`plan`, per window.** Only windows with `metadata?.isStandard == true` are managed. Other windows get no schedule.

1. `let r = ruleSet.resolve(bundleID:)`. If `!r.rule.isEnabled`, the status is `.disabled` and the deadline is nil.
2. `base = r.rule.measureFrom == .opened ? firstSeen : (effectiveLastActive(now) ?? firstSeen)`, and `deadline = base + r.rule.closeAfter`.
3. The status comes from the first match:
   1. `closeState == .sent` → `.closing`.
   2. `closeState == .declined` → `.keptOpen`.
   3. `deadline > now` → `.scheduled`, and `deadline` is a wake candidate.
   4. `key == state.focusedKey` → `.dueInUse`. There is no wake candidate; a focus event causes the replan.
   5. `closeState == .unreachable` → `.dueUnreachable`. An inspection that lists the window causes the replan.
   6. `isPaused || !hasPermission` → `.duePaused`.
   7. Otherwise `.closing`, and append `.closeWindow(key)`.

**`plan`, per app** (this is skipped entirely when `isPaused || !hasPermission`, and for `com.apple.finder`). `r = resolve(bundleID)`; require `r.rule.isEnabled`, `r.source == .app`, `app.quitState == .none`, and `app.pid != state.frontmostPID`.
- `.always`: require `hadStandardWindow` and `noStandardWindowsSince = s`. If `now >= s + 60`, append `.quitApp(pid)`. Otherwise `s + 60` is a wake candidate.
- `.ifClosedBySqueegee`: if `app.quitAfterSqueegeeClose` and the present count is 0 → append `.quitApp(pid)`.
- `.never`: nothing.

The frontmost-app block needs no wake candidate. When the app loses frontmost status, the focus event replans.

**`nextWakeAt`** = the minimum of the wake candidates and `pausedUntil` (if paused until a date and it is in the future).

**Sort `schedules`:** by `deadline` ascending (nil last), then `appName`, then `title`. This is stable and deterministic for tests.

**`dryRun`** = `plan(PlanInput(ruleSet:, state:, now:, isPaused: false, pausedUntil: nil, hasPermission: true))`. It returns the schedules of `.closeWindow` actions and the apps of `.quitApp` actions. It has no side effects by construction. The P2 confirmation dialog and tests use it.

## 6. `AppCore` (`@MainActor @Observable public final class`)

### 6.1 Public surface

```swift
public enum Route: Equatable, Sendable { case onboarding, settings(SettingsSelection) }
public enum SettingsSelection: Hashable, Sendable { case general, globalRule, appRule(bundleID: String) }
public enum PermissionState: Sendable { case granted, denied }
public enum PauseOption: Sendable, CaseIterable { case oneHour, untilTomorrow, untilResumed }
public enum MenuBarIconState: Sendable { case normal, paused, permissionMissing }

public init(store: Store, ports: AppCorePorts,          // ports.scheduler is the clock/timer seam (§6.2)
            catalog: SuggestionCatalog = .builtIn, calendar: Calendar = .current)
public static func live(store: Store, ports: AppCorePorts) -> AppCore

public private(set) var route: Route
public private(set) var permission: PermissionState
public private(set) var plan: Plan
public var isPaused: Bool { get }                    // from store.settings; see §6.6
public var pausedUntil: Date? { get }
public var menuBarIconState: MenuBarIconState { get } // permissionMissing > paused > normal
public var showMainWindow: (@MainActor () -> Void)?  // set by the AppDelegate
public let store: Store

public func start() async

public func pause(_ option: PauseOption)
public func resume()
public func requestAccessibility()
public func openAccessibilitySettings()
public func setLaunchAtLogin(_ enabled: Bool) throws
public var launchAtLogin: Bool { get }

public func open(_ selection: SettingsSelection)     // sets route (if onboarding is complete) + showMainWindow()
public func schedules(for selection: SettingsSelection) -> [WindowSchedule]  // Open Windows list (rule page)
public func dryRun(_ ruleSet: RuleSet) -> DryRunResult
public func recentClosures(limit: Int) -> [ClosureValue]
public func reopen(_ closure: ClosureValue) async throws   // URL → open in app; no URL / quit → launch app
public func menuContent() -> MenuContent             // Presentation.MenuContentBuilder with current state

public func suggestions(excludingExistingRules: Bool) async -> [Suggestion]
public func applySuggestions(_ selected: [Suggestion])      // addAppRule for each (no duplicates)
public func completeOnboarding()                     // settings.onboardingComplete = true; login item on; route → .settings(.general)
```

`schedules(for:)`:
- `.appRule(id)` → the schedules with that bundle ID.
- `.globalRule` → the schedules with `ruleSource == .global`.
- `.general` → empty.

### 6.2 `AppScheduler` seam (Biscotti pattern, adapted to wall-clock deadlines)

The protocol is a port: it lives in `Engine/Ports/` with the other ports (system_layer.md §1) and is carried in `AppCorePorts.scheduler`. `LiveAppScheduler` lives in `SystemBridge`, so the ManualTestApp can measure real timer latency (`sb_timer_latency`) before `AppCore` exists.

```swift
public protocol AppScheduler: Sendable {
    func now() -> Date
    @MainActor func schedule(at date: Date, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable
    @MainActor func schedule(every interval: TimeInterval, tolerance: TimeInterval, _ action: @escaping @MainActor () -> Void) -> any Cancellable
}
public protocol Cancellable: Sendable { func cancel() }
```

- **`LiveAppScheduler`** (`SystemBridge`) uses `DispatchSource.makeTimerSource(queue: .main)`. One-shot timers use `DispatchWallTime` (wall clock, so the deadline stays correct across sleep), with `leeway = tolerance`. Repeating timers use `DispatchTime`.
- **`FakeScheduler`** (in TestSupport) holds a manual `now`. `advance(to:)` / `advance(by:)` fire the due actions in time order.

### 6.3 Event pump

`start()` does the following, in order:

1. `permission = ports.permission.isTrusted() ? .granted : .denied`.
2. `route = settings.onboardingComplete ? .settings(restoredSelection) : .onboarding`.
3. Start one `Task` per stream (`workspace.events()`, `focus.signals()`, `permission.changes()`). Each loop calls `await handle(...)` on the main actor.
4. Run the initial sync:
   1. `scan()`.
   2. Inspect every pid that has windows, one after another.
   3. `syncFocus()`.
   4. If the displays are awake, start the scan timer.
5. Start rule observation (§6.5) and call `replan()`.

**Helpers:**
- `scan()`: `await windowLister.listWindows()` → `reduce(.windowList)`.
- `inspect(pid)`: `await windowInspector.inspect(pid:)` → `reduce(.inspected)`. At most one inspection runs per pid at a time. If another request comes while one runs, it is merged into one more run after it.
- `syncFocus()`: `app = workspace.frontmostApp()`; `await focus.observe(pid: app?.pid)`; `id = await windowInspector.focusedWindowID(pid:)` → `reduce(.focusChanged(app, id, at: now))`. The timestamp is taken before the awaits.
- `reduce(event)`: apply `TrackerReducer.reduce`, handle the outputs (below), then `replan()`.

**Tracker outputs:**
- `.windowClosedBySqueegee(w, at)` → `store.appendClosure(ClosureValue(bundleID: w.bundleID, appName: w.appName, windowTitle: w.metadata?.title, documentURL: w.metadata?.documentURL, kind: .windowClosed, closedAt: at))`.
- `.appQuitBySqueegee(app, at)` → `appendClosure(kind: .appQuit, windowTitle: nil, documentURL: nil)`.
- `.needsInspection(pid)` → `inspect(pid)`. At most one per pid per 10 s from this output, so a flapping window cannot cause a flood.
- `.permissionLost` → `refreshPermission()`.

**Events:**

| Input | Handling |
|---|---|
| `.appActivated(app)` | `syncFocus()` (uses the event's app and time); then `inspect(previous frontmost pid)` to refresh its titles |
| `.appDeactivated` | none (the activation of the next app covers it) |
| `FocusSignal(.focusMayHaveChanged, pid, at)` | if `pid == state.frontmostPID`: `id = await focusedWindowID(pid)` → `reduce(.focusChanged(app, id, at: signal.at))`. Signals from other pids are ignored (AltTab lesson). |
| `FocusSignal(.windowCreated, pid, at)` | `scan()`, then `inspect(pid)` |
| `.appLaunched` | `scan()` |
| `.appTerminated(pid)` | `reduce(.appTerminated)`; `windowInspector.forget(pid:)` |
| `.activeSpaceChanged` | `inspect` each pid that has windows with `metadata == nil` or `closeState == .unreachable` |
| `.displaysSlept` / `.sessionResigned` | `reduce(.displaysSlept(at: now))`; stop the scan timer |
| `.displaysWoke` / `.sessionBecameActive` | `scan()`; `syncFocus()`; start the scan timer |
| `.ownAppBecameActive` | `refreshPermission()` |
| permission `changes()` | `refreshPermission()` now and again after 1.5 s |
| scan timer (60 s, tolerance 6 s) | `scan()`; then reconcile focus: `id = await focusedWindowID(frontmost)`; if it differs from `focusedKey`, `reduce(.focusChanged(...))` |
| deadline timer | `replan()` |

**`refreshPermission()`:** read `isTrusted()`.
- If it changed to granted: `inspect` all pids, then `syncFocus()`.
- If it changed to denied: nothing else. The planner input stops the actions.
- Then `replan()`.

### 6.4 Replan and executor

`replan()`:
1. `plan = Planner.plan(PlanInput(ruleSet: store.ruleSet(), state:, now:, isPaused:, pausedUntil:, hasPermission: permission == .granted))`.
2. Clear an expired pause: if the pause is "until date" and `now >= pausedUntil`, clear it in settings and plan again.
3. Re-arm the one deadline timer at `plan.nextWakeAt` (tolerance 5 s). Cancel the old one.
4. Put `plan.actions` that are not already in flight on the executor queue.

**Executor:** a single serial `Task` loop, so there is one action at a time. There is an in-flight set of `WindowKey`s and pids.

- **`.closeWindow(key)`**: `result = await windowCloser.close(key)`:
  - `.pressed(latest, wasListed)` → `reduce(.closeSent(key, wasListed, latest, at: now))`. Schedule `scan()` at +2 s and +10 s, and `reduce(.closeVerification(key, at:))` at +10 s, after the second scan.
  - `.unreachable` → `reduce(.closeUnreachable)`.
  - `.noCloseButton` → `reduce(.closeHasNoButton)`.
  - `.failed` → `reduce(.closeFailed)`.
  - `.notTrusted` → `refreshPermission()`.
- **`.quitApp(pid)`**: `ok = await appTerminator.terminate(pid:)`.
  - If `ok`: `reduce(.quitSent)`, and `reduce(.quitVerification)` at +30 s.
  - Otherwise: set the quit state to declined through `reduce(.quitVerification)` right away (same effect: no retry until the app has windows again).

Before it runs an action, the executor checks the action against a fresh `replan()`, so that pause or permission changes that happened while it waited in the queue are respected.

### 6.5 Rule observation

```swift
private func observeRules() {
    withObservationTracking { _ = store.ruleSet() } onChange: { [weak self] in
        Task { @MainActor in self?.replan(); self?.observeRules() }
    }
}
```

`store.ruleSet()` reads every `AppRuleRecord` field and the global fields of `AppSettingsRecord`. So any edit through a `@Bindable` in Settings triggers a replan. Inserts and deletes of rules are covered because `appRules()` fetches through the context. Persistence tests include a test that this `onChange` fires for an insert, a delete, and a property edit.

### 6.6 Pause

- `pause(.oneHour)` → `pauseModeRaw = "untilDate"`, `pausedUntil = now + 3600`.
- `pause(.untilTomorrow)` → `pausedUntil` = the next 06:00 local time after `now`, from `calendar.nextDate(after: now, matching: DateComponents(hour: 6), matchingPolicy: .nextTime)`.
- `pause(.untilResumed)` → `pauseModeRaw = "untilResumed"`, `pausedUntil = nil`.
- `resume()` clears both.
- `isPaused` = `pauseModeRaw == "untilResumed" || (pauseModeRaw == "untilDate" && now < pausedUntil)`.

Each of these saves the store and replans.

### 6.7 Tracker state (in memory only)

Tracked window state (opened time, last-active time, close state) lives in memory only and resets when Squeegee restarts. The SwiftData `TrackedWindowRecord` table was removed in schema V2.

### 6.8 Onboarding and suggestions

- `SuggestionCatalog` (Engine) is a static array of entries: `bundleID`, `category: SuggestionCategory` (files, media, messaging, backgroundApps, system; declared in display order), and `rule: Rule`. Its contents are functional spec §11. Granola's bundle ID is found during implementation (from an installed copy, or the vendor's docs). If it cannot be confirmed, the entry is left out.
- `suggestions(excludingExistingRules:)`:
  1. `installed = await ports.installedApps.installedApps()`.
  2. Join with the catalog by bundle ID.
  3. Map each match to `Suggestion(entry, appName, appURL)`.
  4. Optionally remove bundle IDs that have an `AppRuleRecord`.
  5. Sort by category order, then by catalog order.
- `applySuggestions` calls `store.addAppRule(bundleID:appName:rule:)` for each suggestion, then saves.

### 6.9 Menu content

`menuContent()` calls `MenuContentBuilder.build(input)` (Presentation) with:
- the plan's schedules with a status in `{scheduled, dueInUse, duePaused, dueUnreachable, closing}`;
- `recentClosures(limit: 8)`;
- `fileExists` (from `ports.opener`) for each closure URL;
- `isPaused`, `pausedUntil`, `permission`, and `now`.

The builder returns `MenuContent` (a value tree of sections and items, with a `MenuAction` enum for each item). `MenuRenderer` (MenuBarUI) maps each `MenuAction` to an `AppCore` call.

Status text (Presentation; adds to ui_design §7): `.scheduled` → `in 2h 10m`; `.dueInUse` → `waiting — in use`; `.duePaused` → `due now`; `.dueUnreachable` → `waiting — other Space`; `.closing` → `closing…`. The Open Windows list (rule page) also shows `.keptOpen` → `kept open by app` and `.disabled` → `Won't close`.

## 7. Performance notes

- `Planner.plan` is O(windows + apps), which is fewer than 500 in practice. It runs on the main actor on each event. Its cost is microseconds.
- The executor never blocks main. All port calls are `async` on other actors or tasks.

## 8. Test plan

**TrackerReducer**
1. A new window in the scan → tracked with `firstSeen = at`; outputs `needsInspection`.
2. A window missing from the scan with `closeState .none` → removed, no closure output.
3. A window missing with `.sent` → `windowClosedBySqueegee`; the app becomes empty → `quitAfterSqueegeeClose = true`.
4. A window missing with `.declined` (the user later chose Don't Save) → closure output.
5. Focus for 4.9 s, then a change → `lastActive` unchanged.
6. Focus for 5 s exactly, then a change → `lastActive = change time`; `closeState` resets from `.declined` to `.none`.
7. Focus, then displays sleep at +10 s → `lastActive = sleep time`; `session = nil`; `focusedKey` kept.
8. A focus event for an untracked window → inserted; `needsInspection`.
9. `.inspected` lists an unreachable window → `closeState .none`; `metadata` set; `hadStandardWindow` set.
10. `.inspected` omits a known window → its metadata is kept.
11. `.inspected(.notTrusted)` → `permissionLost`.
12. `closeVerification` with the window present: `wasListed` true → `.declined`; false → `.unreachable`.
13. `closeVerification` after the window is gone → no-op.
14. `appTerminated` with `quitState .sent` → `appQuitBySqueegee`; windows removed with no closure outputs.
15. `appTerminated` with windows in `.sent` → no closure outputs.
16. Presence: an unknown-metadata window keeps the app present; the last standard window gone → `noStandardWindowsSince` set only if `hadStandardWindow`.
17. `quitVerification` with the app alive → `.declined`; the app gets a window → `.none`.
18. (removed: perf project — restore event removed)

**Planner**
19. Rule disabled → `.disabled`, no action.
20. Global rule applies to an app without a rule; an app rule overrides the global rule (including app rule off + global on → disabled).
21. `.opened` deadline = firstSeen + duration; `.lastActive` uses lastActive, falling back to firstSeen.
22. A focused window with a qualifying session → its deadline moves with now (never due).
23. A due focused window with a session under 5 s → `.dueInUse`, no action.
24. Due + paused → `.duePaused`, no action; the pause end date appears in `nextWakeAt`.
25. Due + no permission → no action.
26. Due + `.unreachable` → `.dueUnreachable`, no action.
27. Due + `.none` → `.closeWindow`.
28. `.sent` → `.closing`, no duplicate action; `.declined` → `.keptOpen`.
29. Non-standard or unknown-metadata windows → no schedule.
30. `.always` quit: no windows since `s`; at `s+59` no action and a wake at `s+60`; at `s+60` a quit action. Not while frontmost. Not if `!hadStandardWindow`. Not for a global-rule app. Not for Finder. Not when `quitState != .none`.
31. `.ifClosedBySqueegee`: a quit only after the flag is set and the present count is 0.
32. `nextWakeAt` = the earliest future deadline.
33. Schedules sort order.
34. `dryRun` ignores pause and permission; lists due windows only; a draft that turns off a rule produces no closes; a draft that removes an "off" app rule while the global rule is on lists that app's old windows.

**AppCore scenarios** (FakeScheduler + fake ports + in-memory store)
35. Open Finder window → after 6 h since last active, a close is sent → the window disappears in the +2 s scan → a history record with its title and no URL (Finder exposes none; hardware_findings.md).
36. The app shows a save dialog (the fake keeps the window) → `.keptOpen` at +10 s, no retry at +1 h. The user focuses it for 6 s → deadline reset → closes after the next period.
37. Kept element on another Space: the press succeeds but the window stays with `wasListed = false` → `.dueUnreachable`. A Space change inspection lists it → closes.
38. QuickTime `.always`: the last window closed by the user → a quit 60 s later (not frontmost) → terminated → history "app quit".
39. `.ifClosedBySqueegee`: Squeegee closes the last window → quit; the user closes the last window → no quit.
40. Pause one hour → no closes; at the end → due windows close.
41. Permission revoked (`notTrusted` from inspect) → state denied, no actions, icon state; granted by notification → resumes.
42. Displays sleep → the scan timer stops (no `listWindows` calls); wake → scan + focus sync.
43. A focus signal from a non-frontmost pid is ignored.
44. (removed: perf project — restart restore removed, tracked windows are in memory only)
45. A rule edit through a store record → replan without an explicit call (observation).
46. Onboarding: suggestions filter by installed apps; apply creates enabled rules; completeOnboarding sets the flag, enables the login item, and changes the route.
47. `reopen`: with a URL → `opener.open`; without one → `launch`; a quit record → `launch`.
48. History FIFO: 1005 closures → 1000 stored, the oldest removed (Persistence test).
