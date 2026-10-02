---
status: complete
---

# Functional Spec: Perf

Lower Squeegee's CPU use without a change to what the user sees, except one accepted change: tracked window times no longer survive a Squeegee restart. See [project_overview.md](project_overview.md) for the trace data that drives this work.

## 1. Tracked windows: in memory only

### Behavior

- Squeegee keeps all tracked window state (opened time, last-active time, close state) in memory only. It never writes this state to disk.
- When Squeegee starts, every open window is new: "opened = first seen". This is the current behavior for a first launch and after a Mac restart. It now also applies after a Squeegee restart (quit and relaunch, crash, update).
- **Accepted change:** the Squeegee functional spec §3.2 restore rule ("If Squeegee quits and restarts while the target app keeps running, it restores the saved opened/last-active times…") is removed. Squeegee is always on and starts at login, so a restart while other apps keep running is rare.
- A window that declined a close (for example, it showed a save dialog) before a restart starts fresh after the restart. Its clock starts again from "now", so no close attempt happens until its full rule time passes. This is safe: a restart never causes an early close.

### What stays on disk (SwiftData)

No change to these:
- App rules and global rule settings.
- App settings (pause state, onboarding, menu bar icon, last Settings selection, rule version).
- Closure history (the FIFO of 1,000 records).

### Removal

- Remove the tracked-window table (`TrackedWindowRecord`) from the SwiftData schema through a new schema version and a migration stage. On first launch after the update, the migration drops the table. The rules, settings and closure history stay intact.
- Remove all code that only exists for tracked-window persistence and restore: the save/load API in `Store`, the restore event and its reducer handler, the snapshot type and helper, the dirty flag, the persistence debounce timer, the flush on termination, and their tests.
- If the migration fails, the existing store-open failure path applies ("Squeegee couldn't open its data" with **Quit** and **Reset Data**). No new error UI.

## 2. Rule set: in memory

- AppCore keeps the current `RuleSet` in memory. Each replan and each executor re-check uses this copy. They do not fetch from SwiftData.
- AppCore loads the `RuleSet` once at start, and again each time a rule changes. A rule change is any edit to the global rule, an app rule's properties, or an app rule insert or delete. The existing rule observation already detects all of these.
- A rule edit in Settings has the same effect as today: the plan updates at once, with no restart. The in-memory copy must never be stale after the observation fires.
- Settings and the menu read rules as they do today. This change is internal to AppCore.

## 3. Signposts

- Squeegee emits `os_signpost` intervals and events. They show in Instruments (Time Profiler template, "Points of Interest" track) without extra setup.
- Signposts ship in release builds. They have close to zero cost when nothing records them.
- All signposts are in AppCore, around the port calls and the core steps. There are no changes to `SystemBridge` (a change there resets all `sb_*` manual test steps).
- **Intervals** (each one has a duration):
  - Window list scan.
  - AX inspection of one app (include the pid and the number of windows returned).
  - Focused-window lookup.
  - Reduce (include the event kind).
  - Replan.
  - Execute one action (close or quit).
- **Events** (each one is a point in time):
  - Each workspace event (include the kind).
  - Each focus signal (include the kind).
  - Each scan timer tick.
- Signpost metadata never includes window titles or document paths (privacy, the same rule as `os.Logger`).

## 4. Measurement and the final test

### Profiling build

- The release build configuration emits a dSYM, so a profile of a release-optimized build shows function names. The release archive keeps the dSYM.

### Benchmark (primary measure)

A live-app run depends on how many window changes the user makes in the 5 minutes, which can be zero. So the primary measure is a **deterministic benchmark**, `perf-bench`:
- It drives the real `AppCore` and a real on-disk SwiftData `Store` (in a temp dir) with the existing test fakes, through scripted event sequences on a fake clock. Every run gets the same input.
- It runs with release optimization, needs no user, and does not touch the installed app or the user's store.
- Scenarios:
  - **churn:** 50 windows in 10 apps; 300 app/window switches with varied dwell times; scan ticks every 60 s of fake time.
  - **idle:** 50 windows; 1 hour of fake time with only scan ticks.
  - **scale:** churn with 300 windows.
- Output: process CPU time per scenario (median and min of several repeats) and µs per event.
- A Time Profiler trace of the benchmark (launched by `xctrace`, symbolicated) gives the SwiftData share and the top paths.
- It does not measure real AX, CG or system-notification costs. The investigation trace put those at about 1% and 0%.
- Not a CI gate (CI runners are too noisy).

There are two benchmark runs:
- **Baseline:** on the code before any fix (Phase 2).
- **Final:** after all fixes (last phase).

### Live profiling run (diagnostic, optional)

The Phase 1 tooling (`scripts/profile/run.sh`) stays as a diagnostic for the real app. The agent drives it end to end: build a symbolicated Release app (Developer ID, the same signing as the installed app, so the Accessibility grant stays valid), quit the installed app, run the profiling build on a copy of the store, record 5 minutes while the user uses the Mac, then restart the installed app. It is not a pass gate. It runs in the last phase only if the user asks for it.

### Final test (last phase)

1. Run the benchmark and its trace on the final code.
2. Compare with the baseline. Report per scenario: CPU (median, min), µs per event, and the change in %. From the trace: the SwiftData / Core Data share and the top paths.
3. **Pass:** churn CPU (median) at least 50% below the baseline, and SwiftData / Core Data < 5% of the benchmark trace samples.
4. If it passes, or if it does not, discuss the possible next steps with the user, based on the data. Candidates already known: focus-signal debounce, stopping the 60 s re-inspection of windows AX never reports, and skipping `plan` reassignment when it did not change. Offer the optional live run.

## 5. Out of scope

- Focus-signal debounce, the change to the 60 s re-inspection, and skipping `plan` reassignment. These wait until the final test shows they matter.
- Any change to `SystemBridge`.
- The `updateBounds` bug (nothing calls it, so the bounds-match fallback for window IDs never works). This goes to the Squeegee backlog.

## 6. Docs to update

- Squeegee `functional_spec.md`: remove the §3.2 restore rule and the "tracked window times" item in the stored-data list.
- Squeegee `architecture.md`: remove `TrackedWindowRecord`, and describe the schema V2 and the in-memory rule set.
- Squeegee `components/engine.md`: remove the restore event and test 44 (restart restore).
- `CLAUDE.md`: mention the signposts and how to profile (one short note).
