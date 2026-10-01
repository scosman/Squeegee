---
status: complete
---

# Architecture: WindowCleaner

Technical design for `functional_spec.md` and `ui_design.md`. The research this rests on is in [research/macos-window-apis/summary.md](research/macos-window-apis/summary.md). The technical setup copies Biscotti (github.com/scosman/Biscotti) where noted.

Detailed component designs:

- [components/system_layer.md](components/system_layer.md): CoreGraphics/Accessibility/NSWorkspace adapters, the private window-ID bridge, the element cache, focus observation, permissions.
- [components/engine.md](components/engine.md): tracker reducer, planner (with dry run), executor, scheduling, and the `AppCore` orchestration loop.
- [components/manual_test_app.md](components/manual_test_app.md): hardware test harness and scripts.

## 1. Principles

1. **Swift-package-first, thin app** (from Biscotti). All logic, view models, and nearly all views live in one Swift package, `WindowCleanerKit`, and build and test with `swift build` / `swift test`. The app target is only the composition root plus Apple glue (Info.plist, entitlements, scenes, app delegate).
2. **Pure decision core.** "What should close, and when" is a pure function of (rule set, tracker state, time, flags). It has no system calls and no clock reads. This is what makes 99% of behavior unit-testable, and gives the dry run (functional spec §14) for free.
3. **Every system API behind a `Sendable` protocol** ("port") with a `Live*` implementation. Tests use fakes from a shared `TestSupport` target (Biscotti pattern).
4. **Event-driven, low energy.** No focus polling. One AXObserver on the frontmost app only, NSWorkspace notifications, a slow 60 s window scan while displays are awake, and one timer armed for the next deadline. Nothing runs while displays sleep except that timer.
5. **Hardware behavior is verified, not assumed.** Every system behavior that unit tests cannot cover has a ManualTestApp step (§10).

## 2. Repository Layout

```
/
├── App/                          # thin app target (XcodeGen)
│   ├── project.yml
│   ├── Sources/WindowCleanerApp.swift, AppDelegate.swift
│   ├── Resources/Info.plist, Assets.xcassets
│   └── WindowCleaner.entitlements
├── ManualTestApp/                # hardware test harness (XcodeGen)
│   ├── project.yml
│   ├── Sources/…
│   └── Results/manual_test_results.json   # committed
├── Packages/WindowCleanerKit/    # all real code
│   ├── Package.swift
│   ├── Sources/<Module>/…
│   └── Tests/<Module>Tests/…, Tests/TestSupport/…
├── scripts/release.sh            # archive → sign → notarize → DMG
├── specs/…
├── .github/workflows/ci.yml
├── .githooks/pre-commit
├── Makefile, Brewfile, .swiftlint.yml, .swiftformat
├── .mcp.json, hooks_mcp.yaml
└── CLAUDE.md
```

The `.xcodeproj` files are generated and git-ignored.

## 3. Package and Modules

`Packages/WindowCleanerKit/Package.swift`: `swift-tools-version: 6.1`, `platforms: [.macOS(.v15)]`, `swiftLanguageModes: [.v6]`, and every target gets `swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]`. Tests use **Swift Testing** (`import Testing`). There are no third-party dependencies.

### 3.1 Module DAG

```
L0  Engine            (Foundation only; pure)        ← value types, ports, TrackerReducer, Planner, SuggestionCatalog
L0  Presentation      (Foundation; depends Engine)   ← formatters, rule summaries, MenuContent builder
L1  Persistence       (SwiftData; depends Engine)    ← @Model types, Store, mapping to Engine values
L1  SystemBridge      (AppKit, ApplicationServices, CoreGraphics, ServiceManagement; depends Engine)
L2  AppCore           (depends Engine, Presentation, Persistence)     ← orchestrator; takes ports by injection
L3  SharedUI          (SwiftUI; depends Presentation, AppCore)        ← AppIconView, SuggestionListView
L3  MenuBarUI         (AppKit; depends Presentation, AppCore)         ← StatusItemController, NSMenu rendering
L3  OnboardingUI      (SwiftUI; depends SharedUI, AppCore)
L3  SettingsUI        (SwiftUI; depends SharedUI, AppCore, Persistence)
L3b AppShellUI        (SwiftUI; depends OnboardingUI, SettingsUI)     ← main window root, route switch
--  ManualTestKit     (Foundation; pure)  + executable `manual-tests-check`
--  TestSupport       (test-only target at Tests/TestSupport; not a product) ← fakes, fixtures
L4  App target        (depends AppShellUI, MenuBarUI, AppCore, SystemBridge, Persistence)
```

- `AppCore` does **not** depend on `SystemBridge`. It sees only the ports (protocols in `Engine`). The app target wires `SystemBridge` live types into `AppCore.live(...)`. This keeps the dependency direction clean and forces all tests through fakes.
- `ManualTestApp` depends on `SystemBridge`, `Engine`, and `ManualTestKit`.

### 3.2 Module responsibilities (summary)

| Module | Responsibility |
|---|---|
| Engine | Domain value types (`Rule`, `RuleSet`, `WindowKey`, `TrackedWindow`, …), port protocols, `TrackerReducer` (events → state), `Planner` (state + rules + time → schedules + actions + next wake), `SuggestionCatalog` (static data + matching). |
| Presentation | Pure text: time-left / time-ago / pause / rule-summary formatting (ui_design §7), `MenuContentBuilder` (plan + history + flags → `MenuContent` value tree). |
| Persistence | SwiftData schema (versioned), `Store` (@MainActor; main context), mapping between `@Model` objects and Engine values, FIFO history trimming. |
| SystemBridge | Live ports: `CGWindowLister`, `AXWindowService` (actor), `FrontmostFocusObserver`, `LiveWorkspaceEvents`, `LiveAccessibilityPermission`, `LiveLoginItem`, `LiveInstalledAppScanner`, `LiveAppOpener`, `LiveAppTerminator`, `LiveAppScheduler`. See system_layer.md. |
| AppCore | `@MainActor @Observable final class AppCore`: event pump, tracker state, replanning, executor, deadline timer, pause, permissions state, onboarding completion, dry run, reopen, route. See engine.md. |
| SharedUI | `AppIconView` (icon by bundle ID, cached), `SuggestionListView` (onboarding step 3 + Settings sheet). |
| MenuBarUI | `StatusItemController`: owns `NSStatusItem`; `NSMenuDelegate.menuNeedsUpdate` asks `AppCore` for a `MenuContent` and renders it with `MenuRenderer`. |
| OnboardingUI | `OnboardingScaffold`, `ProgressHeader`, `BrandFooter`, step views, `OnboardingViewModel`. |
| SettingsUI | `SettingsRootView` (`NavigationSplitView`), sidebar, General page, Rule page, Open Windows list, add-app menu, Suggestions sheet, view models. |
| AppShellUI | `MainWindowRootView`: switches on `core.route` (`.onboarding` / `.settings(selection)`). |

## 4. Data Model

### 4.1 Engine value types (the domain, all `Sendable`, `Equatable`)

```swift
public struct WindowKey: Hashable, Sendable, Codable { public let pid: Int32; public let windowID: UInt32 }

public enum MeasureFrom: String, Codable, Sendable { case lastActive, opened }
public enum QuitPolicy: String, Codable, Sendable { case never, ifClosedByWindowCleaner, always }

public struct Rule: Equatable, Sendable, Codable {
    public var isEnabled: Bool
    public var closeAfter: TimeInterval            // seconds; clamped to Rule.closeAfterRange
    public var measureFrom: MeasureFrom
    public var quitPolicy: QuitPolicy
    public static let closeAfterRange: ClosedRange<TimeInterval> = 300...(30 * 86_400)
    public static let globalDefault = Rule(isEnabled: false, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never)
    public static let newAppRuleDefault = Rule(isEnabled: true, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never)
}

public struct RuleSet: Equatable, Sendable {
    public var global: Rule                       // quitPolicy always treated as .never
    public var appRules: [String: Rule]           // key: bundle ID
    public func resolve(bundleID: String) -> ResolvedRule   // app rule or global; forces .never for global + Finder
}
public struct ResolvedRule: Equatable, Sendable { public let rule: Rule; public let source: Source; public enum Source { case app, global } }
```

`TrackedWindow`, `TrackedApp`, `FocusSession`, `TrackerState`, `WindowSchedule`, `Plan`, `PlannedAction` are defined in [engine.md](components/engine.md) §2.

### 4.2 SwiftData schema (`Persistence`)

Versioned from day 1: `WindowCleanerSchemaV1: VersionedSchema` and `WindowCleanerMigrationPlan` (Biscotti pattern), with no migrations yet. The store file is `~/Library/Application Support/WindowCleaner/WindowCleaner.store`.

```swift
@Model final class AppRuleRecord {
    @Attribute(.unique) var bundleID: String
    var appName: String               // display fallback when app is not installed
    var isEnabled: Bool
    var closeAfterSeconds: Int
    var measureFromRaw: String        // MeasureFrom.rawValue
    var quitPolicyRaw: String         // QuitPolicy.rawValue
    var createdAt: Date
}

@Model final class AppSettingsRecord {        // exactly one row; Store creates it on first open
    var globalIsEnabled: Bool                 // default false
    var globalCloseAfterSeconds: Int          // default 21600
    var globalMeasureFromRaw: String          // default "lastActive"
    var onboardingComplete: Bool              // default false
    var showMenuBarIcon: Bool                 // default true
    var pauseModeRaw: String?                 // nil = not paused; "untilDate" | "untilResumed"
    var pausedUntil: Date?
    var lastSettingsSelection: String?        // sidebar selection restore ("general" | "global" | bundleID)
}

@Model final class ClosureRecord {
    #Index<ClosureRecord>([\.closedAt])
    var id: UUID
    var bundleID: String
    var appName: String
    var windowTitle: String?
    var documentURL: URL?
    var kindRaw: String                       // "windowClosed" | "appQuit"
    var closedAt: Date
}

@Model final class TrackedWindowRecord {      // for restore after a WindowCleaner restart (§3.2 functional spec)
    #Unique<TrackedWindowRecord>([\.pid, \.windowID])
    var pid: Int32
    var windowID: UInt32
    var bundleID: String
    var processLaunchDate: Date?              // guards against pid reuse
    var firstSeen: Date
    var lastActive: Date?
    var closeSentAt: Date?
}
```

Launch at login is **not** stored: `SMAppService.mainApp.status` is the source of truth.

### 4.3 Store API (`Persistence.Store`, `@MainActor final class`)

```swift
public init(configuration: StoreConfiguration) throws   // .onDisk(URL) | .inMemory
public var context: ModelContext { get }                // main context; autosave on
public var settings: AppSettingsRecord { get }          // the singleton row
public func appRules() -> [AppRuleRecord]               // sorted by appName (case-insensitive)
public func appRule(bundleID: String) -> AppRuleRecord?
@discardableResult public func addAppRule(bundleID: String, appName: String, rule: Rule) -> AppRuleRecord  // returns existing if present (no duplicate)
public func removeAppRule(bundleID: String)
public func ruleSet() -> RuleSet                        // reads records → Engine value (observation-tracked reads)
public func appendClosure(_ value: ClosureValue)        // insert, then trim to newest 1000 (FIFO)
public func recentClosures(limit: Int) -> [ClosureValue]
public func saveTrackedWindows(_ windows: [TrackedWindowSnapshot])  // upsert by (pid, windowID); delete rows not in input
public func loadTrackedWindows() -> [TrackedWindowSnapshot]
public func save()                                      // explicit save after writes that must persist now
```

**Bindings.** Settings views bind directly to `@Model` objects with `@Bindable` (for example, `Toggle("…", isOn: $rule.isEnabled)`). This is the reason SwiftData was chosen over JSON. Values that need clamping or enum mapping are exposed as computed `Binding`s by the view model (for example, `closeAfter` as a `TimeInterval` that clamps to `Rule.closeAfterRange`).

**Rule changes → replan.** `AppCore` calls `store.ruleSet()` inside `withObservationTracking`. `@Model` classes are `Observable`, so any change to a rule or global setting fires `onChange`. `AppCore` then replans on the main actor and re-registers the tracking. No manual "rules changed" calls are needed from views.

## 5. Runtime Flow

```
 NSWorkspace ─┐  FrontmostFocusObserver ─┐   60s scan timer ─┐   deadline timer ─┐
              ▼                          ▼                   ▼                   ▼
          ┌─────────────────────── AppCore (MainActor) event pump ───────────────────────┐
          │ 1. convert to TrackerEvent (may await ports: list windows / inspect app)     │
          │ 2. TrackerReducer.reduce(&state, event) → outputs (closures detected, …)     │
          │ 3. handle outputs (history records, quit-pending)                            │
          │ 4. Planner.plan(input) → Plan (schedules, due actions, nextWakeAt)           │
          │ 5. Executor runs due actions via ports (close / quit), feeds results back   │
          │ 6. arm deadline timer at plan.nextWakeAt; publish plan for UI; persist (debounced) │
          └──────────────────────────────────────────────────────────────────────────────┘
```

- **Threading:** `AppCore` is `@MainActor`. All Accessibility calls run on the `AXWindowService` actor (off main), with a 0.5 s messaging timeout per app element, so a hung target app never blocks the UI. `CGWindowListCopyWindowInfo` runs on a background task (about 3 ms).
- **Event sources and cadence** (details in system_layer.md §5 and engine.md §5):

| Source | Trigger | Work |
|---|---|---|
| NSWorkspace `didActivateApplication` | frontmost app changes | move the focus observer to the new app; query its focused window; inspect the app that lost focus (titles) |
| AXObserver (frontmost app only) | `kAXFocusedWindowChanged`, `kAXMainWindowChanged`, `kAXWindowCreated` | focus event; on window created → inspect that app |
| NSWorkspace `didLaunch/didTerminateApplication` | app launch / quit | window scan; terminate → drop app, record quit if WindowCleaner sent it |
| NSWorkspace `activeSpaceDidChange` | Space change | inspect apps that have windows without metadata, or with close pending |
| NSWorkspace `screensDidSleep/screensDidWake`, `sessionDidResignActive/BecomeActive` | display off/on, fast user switch | end focus session and stop the scan timer / restart both and scan |
| Scan timer | every 60 s, displays awake only (10% tolerance) | CG window scan (+ reconcile the focused window of the frontmost app) |
| Deadline timer | `plan.nextWakeAt` (one-shot, 5 s tolerance) | replan → execute due actions |
| After a close is sent | +2 s and +10 s | CG scan (detect closure) |
| Distributed notification `com.apple.accessibility.api` + app `didBecomeActive` | permission list changed | re-check `AXIsProcessTrusted()` |

There is no periodic focus sampling. Focus time is measured with event timestamps (engine.md §3).

## 6. App Target and Shell

`App/Sources/WindowCleanerApp.swift`:

```swift
@main struct WindowCleanerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene {
        // Dormant scene — exists solely to host the Cmd-Q command override.
        Window("WindowCleaner", id: "unused") { EmptyView() }
            .defaultLaunchBehavior(.suppressed)
            .commands {
                CommandGroup(replacing: .newItem) {}
                CommandGroup(replacing: .appTermination) {
                    Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                        .keyboardShortcut("q")
                }
            }
    }
}
```

**Window management — single NSWindow path.** A SwiftUI `Window` scene with `.defaultLaunchBehavior(.suppressed)` never instantiates its content, so `OpenWindowAction` is never captured. The app uses a single `NSWindow` + `NSHostingView(rootView: MainWindowRootView(...))` created by `AppDelegate`. There is no `LaunchState` or scene-based fallback — the NSWindow path is the only path.

`AppDelegate` (the composition root, main actor):

1. `applicationDidFinishLaunching`: build `Store(.onDisk(appSupportURL))`, then `AppCore(store:, ports: LivePorts.make())`. Create `StatusItemController(core:)`. Call `core.start()`. If `!store.settings.onboardingComplete`, call `showMainWindow()`.
2. `showMainWindow()`: `NSApp.setActivationPolicy(.regular)`, create or order-front the NSWindow, then defer `NSApp.activate(ignoringOtherApps: true)` + `makeKeyAndOrderFront` to the next run-loop turn (the cooperative `NSApp.activate()` is advisory and routinely refused for accessory apps; the deprecated `ignoringOtherApps:` variant still works on macOS 14/15/Tahoe).
3. Observe `NSWindow.willCloseNotification` for normal-level windows. When no visible main-capable windows remain, call `NSApp.setActivationPolicy(.accessory)`.
4. `applicationShouldHandleReopen(_:hasVisibleWindows:)` → `showMainWindow()`, return `false` (functional spec §8.3).
5. `applicationShouldTerminateAfterLastWindowClosed` → `false`.

**Sidebar.** The `NavigationSplitView` uses `columnVisibility: .constant(.all)` and `.navigationSplitViewStyle(.balanced)`. Sidebar collapse prevention is a known open item (`.toolbar(removing: .sidebarToggle)` does not work inside `NSHostingView`).

**Info.plist:** `LSUIElement = YES` (starts as a menu bar app with no Dock icon; policy switches to `.regular` only while the window is open). Bundle ID `net.scosman.windowcleaner`. There are no usage-description keys (Accessibility has none).

**Entitlements:** none (the app is not sandboxed, and hardened runtime needs no exceptions for AX/CG). The file exists and is empty.

**Build settings (`App/project.yml`, XcodeGen):** deployment target macOS 15.0, `SWIFT_VERSION 6.0`, `SWIFT_STRICT_CONCURRENCY complete`, `SWIFT_TREAT_WARNINGS_AS_ERRORS YES`, `ENABLE_HARDENED_RUNTIME YES`, `CODE_SIGN_STYLE Manual`, `DEVELOPMENT_TEAM B5L5M4B62J`. Debug uses `CODE_SIGN_IDENTITY "Apple Development"`; Release uses `"Developer ID Application"`. `make build-app` (CI) overrides to ad-hoc (`-`). `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` live in `project.yml`.

**Stable signing for local runs.** Accessibility grants are bound to the code signature. Ad-hoc builds lose the grant on every rebuild. So local runs of the app and of the ManualTestApp use the team's Apple Development identity and a fixed bundle ID (`make run-app`, `make run-manual-tests`). Reset a grant with `tccutil reset Accessibility net.scosman.windowcleaner`.

**Menu bar.** `NSStatusItem` + `NSMenu` (`MenuBarUI`), not SwiftUI `MenuBarExtra`. Reason: the UI design needs `NSMenuItem.subtitle`, native section headers (`NSMenuItem.sectionHeader(title:)`), per-item tooltips, and app icons. `MenuBarExtra(.menu)` does not expose these reliably. `statusItem.isVisible` follows `settings.showMenuBarIcon`. The icon image follows `core.menuBarIconState` (ui_design §3.1).

**Launch at login:** `SMAppService.mainApp.register()` when onboarding completes (default on). The Settings toggle calls `register()` / `unregister()` and shows `status`. Errors show inline under the toggle.

## 7. Error Handling and Logging

- **Logging:** `os.Logger(subsystem: "net.scosman.windowcleaner", category: <Component>)`, one per component (Biscotti pattern). Never `print`. Window titles are logged with `privacy: .private`.
- **System call failures are data, not exceptions.** Ports return result enums (`CloseAttemptResult`, `InspectionResult`) rather than throwing, and the engine handles each case (engine.md §6). A failure never crashes the app, and never causes a retry loop.
- **Persistence errors:** a store open failure at launch shows an error view in the main window ("WindowCleaner couldn't open its data") with **Quit** and **Reset Data** (the second deletes the store file and relaunches). Save failures after that are logged. The in-memory state stays correct, and the next save retries.
- **Permission loss** is a state, not an error: `AppCore.permission == .denied` stops execution in the planner input (`hasPermission: false`), and the UI shows banners.
- **Fatal errors:** none are expected. `fatalError` is allowed only for programmer errors, with a message (SwiftLint `fatal_error_message`).

## 8. Testing Strategy

| Layer | How | Target |
|---|---|---|
| Engine (reducer, planner, rule resolution, catalog matching) | Table-driven Swift Testing, pure values, no fakes needed | Every branch; the case list is in engine.md §8 |
| Presentation (formatters, rule summaries, MenuContent builder) | Pure unit tests with fixed dates, `Locale(identifier: "en_US_POSIX")` and fixed time zone | Every row of ui_design §7 and every menu state of ui_design §3.2 |
| Persistence | In-memory `ModelContainer` | Singleton creation, unique rule, FIFO trim at 1000, tracked-window upsert/delete, `ruleSet()` mapping, observation fires on rule edit |
| AppCore | Scenario tests with `TestSupport` fakes (`FakeWindowSystem`, `FakeWorkspaceEvents`, `FakeScheduler`, `FakePermission`, …) and an in-memory store | Full user stories: open → close after N hours; focus 4 s vs 6 s; save dialog / no retry; Always-quit after 60 s; pause/resume; permission revoked/granted; restart restore; dry run |
| View models (Onboarding, Settings, MenuBar) | Unit tests over a fake-backed `AppCore` fixture | Step flow, gating, suggestions selection, add/remove app, selection restore |
| MenuRenderer | Unit test: `MenuContent` → `NSMenu`; assert item titles, subtitles, enabled, tooltips, section headers | All states |
| SystemBridge | Pure parsing helpers unit-tested with fixture dictionaries (CG window dict → `ObservedWindow`, AXDocument string → URL). Live AX/CG behavior is covered by the ManualTestApp | Parsing only |
| App target | Build only (CI app tier) | — |

- **Time:** nothing in `Engine` or `Presentation` reads the clock; `now` is a parameter. `AppCore` gets `AppScheduler` through `AppCorePorts.scheduler` (a port in `Engine`, live in `SystemBridge`; Biscotti seam: `now() -> Date`, `sleep(until:)`, cancellable timers). `FakeScheduler` advances time by hand.
- **Fakes** live in `Tests/TestSupport` (a plain target, not a product, since SPM test targets cannot depend on each other). Fakes use a reference-type backing store so tests can mutate the scripted system state (for example, "window 12 disappears now").
- **No test touches real AX/CG/NSWorkspace.** Tests run in CI on a headless runner with no permissions.

## 9. Tooling, CI, and Agent Setup (copied from Biscotti)

### 9.1 Makefile

| Target | Runs | Gating |
|---|---|---|
| `bootstrap` | download pinned SwiftLint 0.63.3 / SwiftFormat 0.61.1 into `.tools/` (curl + `shasum -a 256 -c`), `brew bundle` | — |
| `generate` | `xcodegen generate` in `App/` and `ManualTestApp/` | — |
| `build` | `swift build --package-path Packages/WindowCleanerKit -Xswiftc -warnings-as-errors` | yes |
| `test` | `swift test --no-parallel --package-path Packages/WindowCleanerKit` (output filtered to summary/errors) | yes |
| `lint` | `swiftformat --lint` + `swiftlint lint --strict` over `Packages App ManualTestApp` | yes |
| `format` | swiftformat, then `swiftlint --fix` | — |
| `precommit-checks` | `format` → `lint` → `test` | — |
| `build-app` | `generate`, then `xcodebuild` Debug for app + ManualTestApp, ad-hoc signed | CI non-gating |
| `run-app` / `run-manual-tests` | Debug build with Apple Development signing, then `open` | — (humans only) |
| `manual-tests-check` | `swift run --package-path Packages/WindowCleanerKit manual-tests-check ManualTestApp/Results/manual_test_results.json` | CI non-gating |
| `release` | `scripts/release.sh` (§9.5) | — |
| `ci` | `lint test build` | — |
| `hooks` | `git config core.hooksPath .githooks` | — |
| `clean` | remove `.build`, generated projects, DerivedData | — |

**Brewfile:** `xcodegen`, `node` (for XcodeBuildMCP). **`.swiftlint.yml` and `.swiftformat`:** copy Biscotti's files as they are (strict, `force_unwrapping` opt-in, `todo` disabled, `--self remove`, `--importgrouping testable-bottom`), with the include paths changed.

### 9.2 CI (`.github/workflows/ci.yml`)

On push to `main` and on pull requests. `runs-on: macos-15`, `DEVELOPER_DIR` pinned to Xcode 26.3 (Biscotti's reason: the default Xcode's SDK breaks Swift 6 SwiftData `Sendable` checks). Caches: Homebrew, `.build`, `.tools`.

- **package-tier** (gating, the required check): `make ci`.
- **app-tier** (`continue-on-error: true`): `make build-app`.
- **manual-tests-check** (`continue-on-error: true`): `make manual-tests-check`.

### 9.3 Agent tooling

- `.mcp.json`: `hooks-mcp` (`uvx hooks-mcp`) and `xcodebuildmcp` (`npx -y xcodebuildmcp@latest mcp`).
- `hooks_mcp.yaml`: tools `bootstrap, generate, build, test, lint, format, precommit_checks, build_app, manual_tests_check`, each a `make` wrapper with output capped by `tail` and a 300 s timeout.
- **Sandbox gotcha:** `swift build`, `swift test`, and `xcodebuild` fail inside the Claude Code Bash sandbox (an llbuild EPERM). Agents use the `mcp__hooks-mcp__*` tools for anything that compiles.
- `.githooks/pre-commit`: if `$CLAUDECODE` is set, print the agent protocol and exit 1. Otherwise run `make precommit-checks` and `git add -u`.
- **Agent commit protocol:** run `mcp__hooks-mcp__precommit_checks`. Only if it passes, with no code changes after it, run `git commit --no-verify`.

### 9.4 CLAUDE.md

Same structure as Biscotti's: current stage, "read this first by task", doc chain, module map (§3.1), conventions and gotchas (sandbox, signing/TCC, Observation-in-scenes), the Makefile table, the CI tiers, hooks-mcp, the commit protocol, the manual-test staleness rule (§10), and the TODO policy.

### 9.5 Release (`scripts/release.sh`)

1. `xcodebuild archive` (Release, Developer ID Application, hardened runtime).
2. `xcodebuild -exportArchive` with `method: developer-id`.
3. `xcrun notarytool submit --keychain-profile "notarytool-password-scosman" --wait`, then `xcrun stapler staple` on the app.
4. `hdiutil create` a DMG (app + `/Applications` symlink). Sign it, then notarize and staple the DMG.
5. The output goes to `build/release/WindowCleaner-<version>.dmg`.

The notary keychain profile `notarytool-password-scosman` already exists on the user's machine. The script uses it by name and never handles credentials. Publishing (for example, a GitHub release) is manual in V1.

## 10. ManualTestApp (summary)

It is the same harness as Biscotti: `ManualTestKit` (pure `TestScript` / `TestStep` / `ResultsStore`), a SwiftUI tab app with one tab per script, and results committed to `ManualTestApp/Results/manual_test_results.json`. The `manual-tests-check` gate is red until every recordable step has a result.

**Staleness rule:** any change to `Sources/SystemBridge` sets all `sb_*` steps to `not-run`.

The scripts cover every hardware unknown from functional spec §15 and every design assumption in system_layer.md. See [components/manual_test_app.md](components/manual_test_app.md).

## 11. Technical Risks and Contingencies

| Risk | Detection | Contingency (designed, not built in V1) |
|---|---|---|
| `_AXUIElementGetWindow` missing on a future macOS | Resolved with `dlsym` at startup; the ManualTestApp checks it | If missing: `AXWindowService` matches windows by AX position+size against CG bounds (system_layer.md §3.3). Closing still works; accuracy drops. |
| Kept AX element cannot close a window on another Space | ManualTestApp `sb_close_other_space` | Close waits until the user visits the Space (already the V1 behavior when the element is missing). Option B from design review (`_AXUIElementCreateWithRemoteToken`) is a later project. |
| App Nap delays the deadline timer by more than 60 s | ManualTestApp `sb_timer_latency` | Hold `ProcessInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason:)` only from 60 s before a deadline until it fires. |
| Some apps do not send `kAXFocusedWindowChanged` | ManualTestApp `sb_focus_events` (Finder, Preview, Safari, an Electron app) | Also subscribe to `kAXMainWindowChanged` (already in V1). The 60 s scan re-reads the focused window. |
| `com.apple.accessibility.api` notification does not fire | ManualTestApp `sb_permission_notification` | Re-check on app activation (V1), plus a 2 s poll only while the onboarding permission screen is visible. |
| Finder does not expose a document URL | ManualTestApp `sb_document_urls` | **Triggered** (hardware_findings.md). No Reopen for Finder; "open the app" action (ui_design §3.2 fallback row). |
