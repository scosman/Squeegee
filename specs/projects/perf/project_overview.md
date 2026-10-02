---
status: complete
---

# Perf: Lower Squeegee's CPU Usage

Squeegee's CPU usage is not awful (1m24s of CPU in 18 hours, with 7+ hours of that asleep), but it could be better. Lower it.

- Stop writing tracked windows to SwiftData, and only store them in memory. Remove the whole table if justified. It is okay that they are lost across restarts. Squeegee is designed to be always on, started at login. SwiftData is reserved for history (and rules/settings).
- Keep the `RuleSet` in memory.
- Add signposts. The last phase of the plan runs a 5 minute test and confirms the fix (or identifies the next issue).

## Decisions

- **Out of scope until measurements show they matter:** a focus-signal debounce, stopping the 60 s re-inspection of windows AX never reports, and skipping `plan` reassignment when it did not change.
- **No changes to `Packages/SqueegeeKit/Sources/SystemBridge`** (they reset all `sb_*` manual test steps). Signposts go in AppCore, around the port calls.
- **Schema:** dropping `TrackedWindowRecord` through a schema V2, or leaving it unused, are both fine. The app has not shipped to anyone but the author.
- **Final test build:** fix the release config so it emits a dSYM, and profile a symbolicated release build.
- **Final test pass criteria:** SwiftData < 5% of samples, and total CPU per 5 minutes at least 50% below a new signposted baseline run, also reported as CPU per event from the signpost counts. With the measurements in hand, discuss possible next steps.

## Context: investigation (2026-10-02)

A 5 minute Time Profiler trace of the installed release build (attached to the running app, normal use, Settings window closed) gave about 1.3 s of CPU (1,313 samples):

| Path | Share of CPU |
|---|---|
| Any SwiftData / Core Data | ~67% |
| Persistence debounce timer → `flushTrackerState` → `saveTrackedWindows` | 43.6% |
| `replan()` → `store.ruleSet()` SwiftData fetch (from event tasks) | ~7% direct, 24% for the full task path |
| AX calls | 1.1% |
| `CGWindowListCopyWindowInfo` | ~0% |

The CPU is spread across user activity (app switches, focus changes), not 60 s spikes. Each `reduce()` marks the tracker dirty; 5 s later `saveTrackedWindows` fetches every `TrackedWindowRecord`, sets every property on every row (each set faults the row in from SQLite and encodes the value), and saves.
