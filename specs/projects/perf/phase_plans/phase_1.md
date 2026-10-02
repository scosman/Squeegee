---
status: complete
---

# Phase 1: Measurement Tooling

## Overview

Add signposts to AppCore for profiling in Instruments, create the profiling build target and scripts (`run.sh`, `analyze_trace.py`), add dSYM archiving to the release script, and register `profile_app` in hooks-mcp. This phase provides the measurement infrastructure that Phase 2 (baseline run) and Phase 5 (final run) depend on.

## Steps

1. Create `Kit/Sources/AppCore/Signposts.swift` with `OSSignposter` on the Points of Interest category, plus signpost-label extensions on `TrackerEvent`, `WorkspaceEvent`, and `FocusSignal.Kind`.

2. Instrument `AppCore.swift`:
   - Wrap `scan()` body in a `"scan"` interval (end message: window count).
   - Wrap `inspectPid(_:)` call to `ports.windowInspector.inspect(pid:)` in an `"inspect"` interval (begin: pid, end: window count or -1/-2).
   - Extract a `focusedWindowID(pid:)` helper that wraps `ports.windowInspector.focusedWindowID(pid:)` in a `"focusedWindowID"` interval; replace the three direct call sites.
   - Wrap `reduce(_:)` body in a `"reduce"` interval (begin: event label).
   - Wrap `replan()` body in a `"replan"` interval.
   - Wrap `executeAction(_:)` body in an `"execute"` interval (begin: "close" or "quit").
   - Emit `"workspaceEvent"` event at the start of `handleWorkspaceEvent`.
   - Emit `"focusSignal"` event at the start of `handleFocusSignal`, before the frontmost guard.
   - Emit `"scanTick"` event at the start of the scan timer closure.

3. Add `--profiling-store <dir>` support to `App/Sources/AppDelegate.swift`:
   - `profilingStoreURL() -> URL?` that reads `ProcessInfo.processInfo.arguments`.
   - `openStoreOrTerminate()` uses `profilingStoreURL() ?? appSupportURL()`.
   - When profiling: log it, skip the `shouldShowWindow` branch.

4. Add `make profile-app` to the Makefile (Release config, Developer ID signing, output under `build/profile/`).

5. Create `scripts/profile/run.sh` — orchestrates a profiling run (build, swap installed app, xctrace record, analyze).

6. Create `scripts/profile/analyze_trace.py` — parses xctrace XML exports and produces a Markdown report.

7. Add dSYM zip step to `scripts/release.sh` after the archive.

8. Add `profile_app` action to `hooks_mcp.yaml`.

9. Add `make profile-app` row and "Profiling" note to `CLAUDE.md`.

## Tests

- No new unit tests for signposts (they are zero-cost annotations, not behavioral code). Existing tests still pass — the signposts are inert when not recorded.
- `make profile-app` must build successfully (verified outside sandbox).
- `analyze_trace.py` is smoke-tested in Phase 2 against a real trace.
