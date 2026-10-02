---
status: complete
---

# Architecture: Perf

Implements [functional_spec.md](functional_spec.md). This is a small project, so one doc covers it (no component docs). Paths are relative to the repo root; `Kit/` means `Packages/SqueegeeKit/`.

**Hard rule:** no file under `Kit/Sources/SystemBridge/` changes (it would reset all `sb_*` manual test steps).

## 1. Signposts (AppCore)

### 1.1 New file `Kit/Sources/AppCore/Signposts.swift`

```swift
import OSLog

/// Points-of-Interest signposts for profiling. Near-zero cost when not recorded.
/// Metadata must never include window titles or document paths.
enum Signposts {
    static let signposter = OSSignposter(subsystem: "net.scosman.squeegee", category: .pointsOfInterest)
}
```

If the `OSLog.Category` initializer is not available, use `OSSignposter(logHandle: OSLog(subsystem: "net.scosman.squeegee", category: .pointsOfInterest))`.

Also in this file, `fileprivate`/`internal` label helpers (pure `switch`, no associated values in the output):
- `extension TrackerEvent { var signpostLabel: String }` → `"windowList"`, `"inspected"`, `"focusChanged"`, `"displaysSlept"`, `"appTerminated"`, `"closeSent"`, `"closeUnreachable"`, `"closeFailed"`, `"closeHasNoButton"`, `"closeVerification"`, `"quitSent"`, `"quitVerification"` (and `"restore"` until Phase 3 removes it).
- `extension WorkspaceEvent { var signpostLabel: String }` → one string per case (`"appActivated"`, `"appDeactivated"`, `"appLaunched"`, `"appTerminated"`, `"activeSpaceChanged"`, `"displaysSlept"`, `"sessionResigned"`, `"displaysWoke"`, `"sessionBecameActive"`, `"ownAppBecameActive"`).
- `extension FocusSignal.Kind { var signpostLabel: String }` → `"focusMayHaveChanged"`, `"windowCreated"`.

All interpolated values use `privacy: .public` (labels, pids, counts only).

### 1.2 Names and placement in `AppCore.swift`

Each interval uses `let id = Signposts.signposter.makeSignpostID()`, then `beginInterval(name, id: id, "...")` and `endInterval(name, state, "...")`. Intervals can overlap across `await`, so always use a fresh ID.

| Name (StaticString) | Type | Where | Begin / end message |
|---|---|---|---|
| `"scan"` | interval | `scan()`, around `listWindows()` + `reduce(.windowList…)` | end: `windows=\(count)` |
| `"inspect"` | interval | `inspectPid(_:)`, around `ports.windowInspector.inspect(pid:)` only | begin: `pid=\(pid)`; end: `windows=\(n)` where `n` = map count, or `-1` for `.appUnavailable`, `-2` for `.notTrusted` |
| `"focusedWindowID"` | interval | new private helper `focusedWindowID(pid:) async -> UInt32?` that wraps `ports.windowInspector.focusedWindowID(pid:)`. Replace all 3 direct call sites (`handleFocusSignal`, `syncFocus`, scan timer). | begin: `pid=\(pid)` |
| `"reduce"` | interval | `reduce(_:)`, whole body (it contains the replan) | begin: `\(event.signpostLabel)` |
| `"replan"` | interval | `replan()`, whole body | — |
| `"execute"` | interval | `executeAction(_:)`, whole body | begin: `close` or `quit` |
| `"workspaceEvent"` | event | first line of `handleWorkspaceEvent` | `\(event.signpostLabel)` |
| `"focusSignal"` | event | first line of `handleFocusSignal`, **before** the frontmost guard | `\(signal.kind.signpostLabel)` |
| `"scanTick"` | event | first line of the scan timer closure | — |

No signposts in Engine (keep it pure) or in SystemBridge.

## 2. Profiling mode and tooling

### 2.1 Launch argument `--profiling-store <dir>` (`App/Sources/AppDelegate.swift`)

- New private helper `profilingStoreURL() -> URL?`: scans `ProcessInfo.processInfo.arguments` for `--profiling-store`, and returns the next argument as a directory URL (creates it if missing). Returns `nil` if the flag is absent or has no value.
- `openStoreOrTerminate()` uses `profilingStoreURL() ?? appSupportURL()`.
- When profiling mode is on: log it once (`logger.info`, public), and do **not** show the main window at launch (skip the `LaunchClassifier.shouldShowWindow` branch). Everything else is the same.
- Read only from process arguments, not `UserDefaults` (no persisted state).

### 2.2 `make profile-app`

New Makefile target (add to `.PHONY` and `help`):

```make
PROFILE_DIR := build/profile
profile-app: generate ## Build a symbolicated Release app (Developer ID, not notarized) for profiling
	cd App && xcodebuild -quiet -project Squeegee.xcodeproj -scheme Squeegee \
	  -destination 'platform=macOS,arch=arm64' \
	  -configuration Release \
	  -derivedDataPath ../$(PROFILE_DIR)/DerivedData build
```

- Uses the project's Release signing (Developer ID Application, team `B5L5M4B62J`). A Developer ID build from this team matches the designated requirement of the installed app, so the existing Accessibility grant applies. Do **not** sign with Apple Development (TCC keeps one code requirement per bundle ID; a new grant could break the installed app's grant).
- A plain `build` (not `archive`) does not strip, so the binary keeps its symbols, and a dSYM is written next to it.
- Output: `build/profile/DerivedData/Build/Products/Release/Squeegee.app`.
- `build/` is already git-ignored (verify; add if not).

### 2.3 `scripts/profile/run.sh <label>`

Bash, `set -euo pipefail`. Steps:

1. `make profile-app`.
2. Fail if any Squeegee process runs from a path other than `/Applications/Squeegee.app` (for example, a Debug build). Use `pgrep -fl`.
3. If the installed app runs: `osascript -e 'tell application id "net.scosman.squeegee" to quit'`, then poll until its process is gone (timeout 20 s, then fail). From here on, an `EXIT` trap runs `open /Applications/Squeegee.app` (if it exists), so the installed app always starts again, also after a failure.
4. Copy the store: `~/Library/Application Support/Squeegee/Squeegee.store*` → `build/profile/<label>-<timestamp>/store/`. (Copy after the quit, so the WAL is consistent.)
5. Launch: `open -n <app path> --args --profiling-store <copied store dir>`. Poll `pgrep -f <app path>/Contents/MacOS/Squeegee` for the pid (timeout 20 s).
6. Print a clear line: "Recording 5 min — use the Mac normally". Wait 10 s (warm-up), then `xcrun xctrace record --template 'Time Profiler' --attach <pid> --time-limit 300s --output build/profile/<label>-<timestamp>/trace.trace`.
7. Quit the profiling build (`osascript … to quit`, it is the only instance), and wait until it is gone. The trap restarts the installed app.
8. `python3 scripts/profile/analyze_trace.py build/profile/<label>-<timestamp>/trace.trace > build/profile/<label>-<timestamp>/report.md`, and print the report.

The script must run outside the agent sandbox (xcodebuild, xctrace, osascript). Agents run it with `dangerouslyDisableSandbox: true`, in the background (it takes ~7 min).

### 2.4 `scripts/profile/analyze_trace.py <trace>`

Python 3, standard library only. Steps:
- `xcrun xctrace export --input <trace> --toc`, then export the `time-profile` table and the `os-signpost` table (xpath `/trace-toc/run[@number="1"]/data/table[@schema="..."]`) to temp files.
- Parse the XML. Resolve `id`/`ref` attributes (rows reference earlier elements by `ref`). A frame label is its `name`, or `<binary>+0x<offset>` when there is no name.
- Report (Markdown to stdout):
  - Total samples, total CPU ms (sum of `weight`), recording length.
  - Share by binary (inclusive): SwiftData, CoreData, libsqlite3, HIServices (AX), CoreGraphics/SkyLight, SwiftUI, AttributeGraph, Squeegee.
  - Top 25 inclusive functions in the `Squeegee` binary, and top 25 self (leaf) functions overall.
  - Signposts: count per name (and per message label for `workspaceEvent`, `focusSignal`, `reduce`), and total/mean duration per interval name.
  - **CPU per event** = total CPU ms ÷ (count of `workspaceEvent` + `focusSignal` + `scanTick`).
  - A warning line if there are zero `inspect` signposts (likely no Accessibility permission).
- Filter signposts to subsystem `net.scosman.squeegee`.

### 2.5 Release dSYM (`scripts/release.sh`)

After the archive step, zip `$ARCHIVE_PATH/dSYMs/Squeegee.app.dSYM` to `$BUILD_DIR/Squeegee-<version>.dSYM.zip` (`ditto -c -k --keepParent`), and log the path in the final summary. Use the version that the script already uses for the DMG name. If the dSYM is missing, warn; do not fail the release.

### 2.6 hooks-mcp

Add a `profile_app` action (`make profile-app`, timeout 600) to `hooks_mcp.yaml`. Do not add `run.sh` (it needs the user at the Mac).

### 2.7 Benchmark: `perf-bench` (primary measure, see functional spec §4)

**Target.** New `.executableTarget(name: "perf-bench", dependencies: ["AppCore", "Persistence", "Engine", "TestSupport"], path: "Sources/PerfBench", swiftSettings: warningsAsErrors)` in `Kit/Package.swift`, next to `manual-tests-check`. `TestSupport` is already a regular `.target`, so no change there. If the scenario tests have a settle/wait helper that is local to the test target, move it into `TestSupport` and use it from both.

**Setup per repeat** (not timed):
- A fresh temp dir and `Store(configuration: .onDisk(tempDir))`. Global rule: enabled, 6 h, `lastActive`. App rules for 3 of the 10 bundle IDs (6 h, 8 h, 12 h; `lastActive`; quit policy `.never`).
- Fakes from `TestSupport`: `FakeScheduler` (start date fixed, e.g. 2026-01-01 09:00 UTC), `FakeWindowLister.windows` = N windows spread round-robin over 10 apps (pids 1001–1010, bundle IDs `bench.app0`…`bench.app9`, bounds 800×600, on screen); `FakeWindowInspector.inspectionResults[pid]` = `.inspected` with standard metadata (`isStandard: true`, title `"Window <id>"`) for each of that pid's windows; `FakeAccessibilityPermission.trusted = true`; the other fakes default.
- `AppCore(store:ports:)`, then `await core.start()` and settle. Remove the temp dir after the repeat.

**Scenarios** (timed part only):
- `churn` (N = 50): 300 switches. Switch `i` targets window index `(i * 7) % N`. Set `FakeWindowInspector.focusedWindowIDs[pid]` to the target. If the target's pid differs from the current frontmost pid, set `FakeWorkspaceEvents.frontmost` and send `.appActivated(app)`; settle. Then send two `FocusSignal(pid:, kind: .focusMayHaveChanged, at: now)` (the real focused + main window notifications); settle. Then `FakeScheduler.advance(by: dwell[i % 4])` with `dwell = [3, 8, 20, 45]` s; settle. (Dwell times above 5 s let the old persistence debounce fire, as in real use. The 60 s scan timer fires during the advances.)
- `idle` (N = 50): `advance(by: 60)` and settle, 60 times (1 hour of scan ticks).
- `scale`: `churn` with N = 300.

**Measurement.** `getrusage(RUSAGE_SELF)` user + system time, delta around the timed part. Events = workspace events + focus signals sent + scan ticks fired (derive scan ticks from the fake time advanced ÷ 60 s). Report per scenario: median and min CPU ms over the repeats, events, µs per event (median).

**CLI.** `perf-bench [--scenario churn|idle|scale|all] [--repeat N]` (defaults `all`, `5`). Prints a Markdown table to stdout. Logs nothing per event.

**Make / hooks.**
- `make bench`: `swift run -c release --package-path $(PACKAGE) perf-bench`.
- `make bench-profile LABEL=<label>`: runs `scripts/profile/bench_profile.sh <label>`: builds `-c release`, gets the binary path with `swift build -c release --show-bin-path`, runs `perf-bench` once and saves its table to `build/profile/bench-<label>-<ts>/bench.md`, then `xcrun xctrace record --template 'Time Profiler' --launch -- <bin> --scenario churn --repeat 10 --output build/profile/bench-<label>-<ts>/trace.trace`, then `analyze_trace.py --binary perf-bench <trace> > …/report.md`, and prints both.
- `hooks_mcp.yaml`: add a `bench` action (`make bench`, timeout 600).
- `CLAUDE.md`: add `make bench` and `make bench-profile` to the Makefile table, and one line in the Profiling section.
- Agents run `make bench-profile` outside the sandbox (`dangerouslyDisableSandbox: true`).

**`analyze_trace.py` changes.** Add `--binary NAME` (default `Squeegee`), used for the "top inclusive functions in the app binary" section and the binary share list. Also fix two Phase 1 review nits: the stale `parse_time_profile()` docstring (it returns 5 values), and the dead `table.find("..")` fallback in `find_table_xpath()` (replace with the default `run_number = "1"`).

**Checks.** The benchmark is not a test and is not in `make test` or CI. `make precommit-checks` must still pass (lint covers the new target).

## 3. Tracked windows in memory only

### 3.1 Schema V2 (`Kit/Sources/Persistence/Schema/`)

- New `SchemaV2.swift`: `SqueegeeSchemaV2: VersionedSchema`, `versionIdentifier = Schema.Version(2, 0, 0)`, `models = [AppRuleRecord, AppSettingsRecord, ClosureRecord]`. Define the three `@Model` classes again as nested types of V2, the same as V1 (same properties, `@Attribute(.unique)`, `#Index`, and doc comments). Nested copies per version are the standard SwiftData pattern. They prevent version-checksum problems from shared classes.
- `SchemaV1.swift` does not change (it must still describe the on-disk V1 store, including `TrackedWindowRecord`).
- `MigrationPlan.swift`: `schemas = [SqueegeeSchemaV1.self, SqueegeeSchemaV2.self]`, `stages = [.lightweight(fromVersion: SqueegeeSchemaV1.self, toVersion: SqueegeeSchemaV2.self)]`. A lightweight migration can drop an entity.
- `Store.swift`: the typealiases point to `SqueegeeSchemaV2.*`; delete the `TrackedWindowRecord` typealias. `Schema(versionedSchema: SqueegeeSchemaV2.self)`.

### 3.2 Removals

| File | Remove |
|---|---|
| `Store.swift` | `saveTrackedWindows`, `loadTrackedWindows`, `loadTrackedWindowRecords` |
| `Engine/Types/TrackerTypes.swift` | `TrackerEvent.restore`, `TrackedWindowSnapshot` |
| `Engine/TrackerReducer.swift` | the `.restore` case |
| `Engine/TrackerReducer+Lifecycle.swift` | `handleRestore` |
| `Engine/TrackerState+Snapshots.swift` | delete the file |
| `AppCore/AppCore.swift` | `reduce(.restore…)` in `start()`; `trackerDirty`, `persistenceDebounce`, `persistenceDebounceInterval`, `markTrackerDirty()`, `flushTrackerState()`, `prepareForTermination()`, and the "Tracker persistence" extension; the `markTrackerDirty()` call in `reduce` |
| `AppCore/Signposts.swift` | the `"restore"` label |
| `App/Sources/AppDelegate.swift` | `applicationWillTerminate` (its only job was the flush) |
| Tests | restore tests in `TrackerReducerTests`, tracked-window tests in `StoreTests`, the restart-restore scenario in `AppCoreScenarioTests` |

Then search for leftovers (`restore(`, `Snapshot`, `TrackedWindow` in Persistence, `prepareForTermination`) and remove dead code. `TrackedWindow` (the in-memory Engine type) stays.

### 3.3 Migration test (`Kit/Tests/PersistenceTests/`)

New test `migratesV1StoreToV2KeepingRulesSettingsAndHistory`:
1. Temp dir. Open a `ModelContainer` with `Schema(versionedSchema: SqueegeeSchemaV1.self)` only (no migration plan) at `<dir>/Squeegee.store`. Insert one `SqueegeeSchemaV1.AppRuleRecord`, change one setting on a new `SqueegeeSchemaV1.AppSettingsRecord`, insert one `ClosureRecord` and one `TrackedWindowRecord`. Save. Release the container (end its scope).
2. `Store(configuration: .onDisk(dir))`. Expect: no throw; `appRules()` has the rule with the same values; the setting keeps its value; `recentClosures(limit: 10)` has the closure.
3. Clean up the temp dir.

## 4. Rule set in memory (AppCore)

- New stored property `private var ruleSet: RuleSet`. Set it in `init` from `store.ruleSet()`.
- `observeRules()` becomes:

```swift
private func observeRules() {
    ruleSet = withObservationTracking {
        store.ruleSet()
    } onChange: { [weak self] in
        Task { @MainActor in
            self?.observeRules()   // reload + re-subscribe first
            self?.replan()
        }
    }
}
```

- `replan()` and the executor re-check in `drainExecutor()` use `ruleSet` (not `store.ruleSet()`). `dryRun` does not change (it takes its rule set as an argument).
- No other caller of `store.ruleSet()` changes.
- **Known gap (accepted):** `onChange` fires on `willSet`, so the reload runs in the next main-actor Task. A replan between the edit and that Task uses the old rules. This is the same window as today: today's `onChange` replan is also the first one that sees the new values. The Task's replan corrects the plan at once.

### Tests (`AppCoreScenarioTests`)

Using the existing fakes and in-memory store (wait for the observation Task the same way the existing rule-edit tests do):
1. Edit the global rule's `closeAfter` after `start()` → the next plan uses the new deadline.
2. Add an app rule → the window's schedule shows `ruleSource == .app` with the app rule's deadline.
3. Remove the app rule → the schedule goes back to `.global`.
4. Disable an app rule → the schedule status is `.disabled`, and no close action is planned for a past-due window.

If equivalent tests already exist, keep them and add only the missing cases.

## 5. Docs (Phase 3 and Phase 4 update the docs for their own changes)

- `specs/projects/Squeegee/functional_spec.md`: remove the §3.2 restore rule (line "If Squeegee quits and restarts…") and the "Tracked window times…" stored-data item. Add one line: tracked window times are in memory only and reset when Squeegee restarts.
- `specs/projects/Squeegee/architecture.md`: remove `TrackedWindowRecord`; note schema V2 + the lightweight migration; note the in-memory `RuleSet` in AppCore; note the signposts.
- `specs/projects/Squeegee/components/engine.md`: remove the `.restore` event (§ around line 160), the `reduce(.restore…)` start step, test 18 (restore), and test 44 (restart restore). Mark removed tests "(removed: perf project)" so the test numbers stay stable.
- `specs/projects/Squeegee/backlog.md` (create if missing): add the `updateBounds` bug (see functional spec §5).
- `CLAUDE.md`: in "Build and checks", add `make profile-app` to the table, plus a short "Profiling" note: signposts on the Points of Interest track, `scripts/profile/run.sh <label>` (agent-driven, needs the user at the Mac, runs outside the sandbox).

## 6. Error handling

- Migration failure → the existing store-open alert (Quit / Reset Data). No new code.
- `run.sh` failures → non-zero exit, and the `EXIT` trap always starts the installed app again.
- Signposts cannot fail.

## 7. Testing summary

- `make precommit-checks` (format + lint + test) must pass for each phase, through `mcp__hooks-mcp__precommit_checks`.
- Phases that touch `App/` must also pass `mcp__hooks-mcp__build_app`.
- Phase 1 also builds `make profile-app` (outside the sandbox) to prove the Release build works.
- Scripts are checked by use: Phase 2 (baseline run) is the first real run. `analyze_trace.py` can be smoke-tested in Phase 1 against any short trace (for example, a 15 s `xctrace record --attach` of the profiling build).
