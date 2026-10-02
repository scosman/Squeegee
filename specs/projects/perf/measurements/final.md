# Final Benchmark

Measured at the head of `scosman/perf` (after all four fix phases), with perf-bench in release mode.

## Benchmark Table

| Scenario | Repeats | Median CPU (ms) | Min CPU (ms) | Events | us/event (median) |
|---|---:|---:|---:|---:|---:|
| churn | 5 | 222.3 | 219.9 | 994 | 223.6 |
| idle | 5 | 15.6 | 15.3 | 60 | 260.3 |
| scale | 5 | 812.2 | 803.8 | 994 | 817.1 |

## Comparison Against Baseline

| Scenario | Baseline Median (ms) | Final Median (ms) | Change | Baseline us/event | Final us/event | Change |
|---|---:|---:|---:|---:|---:|---:|
| churn | 1204.9 | 222.3 | **-81.5%** | 1212.2 | 223.6 | -81.6% |
| idle | 224.6 | 15.6 | **-93.1%** | 3742.6 | 260.3 | -93.0% |
| scale | 6133.1 | 812.2 | **-86.8%** | 6170.1 | 817.1 | -86.8% |

## Pass/Fail

| Criterion | Threshold | Measured | Result |
|---|---|---|---|
| Churn CPU median reduction | >= 50% below baseline | 81.5% below baseline | **PASS** |
| SwiftData/CoreData trace share | < 5% of samples | SwiftData 4.4%, CoreData 1.9% | **PASS** |

**Result: PASS.** Both criteria are met.

## Trace Report Summary (churn, 10 repeats)

- **Recording length:** 3.1 s
- **Total samples:** 2,278
- **Total CPU:** 2,278 ms

### Share by Binary (inclusive)

| Binary | Samples | Share | Baseline Share |
|---|---:|---:|---:|
| SwiftData | 100 | 4.4% | 78.8% |
| CoreData | 44 | 1.9% | 40.5% |
| libsqlite3.dylib | 17 | 0.7% | 5.4% |
| perf-bench | 1,699 | 74.6% | 92.8% |

SwiftData dropped from 78.8% to 4.4% of inclusive samples. The remaining 4.4% comes from `Store.ruleSet()` calls in the settings UI and the initial load at start, not from the hot path.

### Top Inclusive Functions (perf-bench)

| Function | Samples | Share |
|---|---:|---:|
| `AppCore.reduce(_:)` | 937 | 41.1% |
| `AppCore.replan()` | 746 | 32.7% |
| `static Planner.sortSchedules(_:)` | 547 | 24.0% |
| `AppCore.handleWorkspaceEvent(_:)` | 464 | 20.4% |
| `AppCore.handleFocusSignal(_:)` | 372 | 16.3% |
| `AppCore.inspectPid(_:)` | 288 | 12.6% |
| `AppCore.syncFocus(app:)` | 202 | 8.9% |
| `outlined init with copy of TrackerState` | 155 | 6.8% |
| `static Planner.planWindows(…)` | 133 | 5.8% |
| `static TrackerReducer.recomputePresence(_:at:)` | 131 | 5.8% |

The baseline's top function was `flushTrackerState()` at 65.2% (removed in Phase 3). `Store.ruleSet()` was at 13.1% (cached in Phase 4). The hot path is now `reduce` -> `replan` -> `sortSchedules`, which is pure computation.

### Signposts

| Name | Count | Total (ms) | Mean (ms) | Baseline Mean (ms) |
|---|---:|---:|---:|---:|
| reduce | 13,150 | 895.3 | 0.07 | 0.19 |
| replan | 13,160 | 736.7 | 0.06 | 0.18 |
| scan | 960 | 107.5 | 0.11 | 0.27 |
| focusedWindowID | 9,950 | 115.3 | 0.01 | 0.01 |
| inspect | 3,190 | 72.4 | 0.02 | 0.05 |

**CPU per event:** 0.23 ms (baseline: 1.25 ms, **-81.6%**)

## What It Shows

Phases 3 and 4 achieved an 81.5% reduction in CPU for the churn scenario (the primary real-world workload). The idle scenario improved even more at 93.1%, because tracked-window persistence was the only work done on idle scan ticks.

The profile has shifted from SwiftData-dominated (78.8%) to computation-dominated. The remaining hot path is `replan` -> `sortSchedules` (Planner sorting the schedule array on every reduce). The candidates for further improvement noted in the functional spec (focus-signal debounce, skipping unchanged plan reassignment, stopping 60 s re-inspection of never-reported windows) would target this remaining computation, but are out of scope for this project.
