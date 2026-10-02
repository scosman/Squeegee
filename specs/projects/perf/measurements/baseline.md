# Baseline Benchmark

Measured at commit `0724bf4` (Phase 1: profiling infrastructure), before any performance fixes.

## Benchmark Table

| Scenario | Repeats | Median CPU (ms) | Min CPU (ms) | Events | us/event (median) |
|---|---:|---:|---:|---:|---:|
| churn | 5 | 1204.9 | 1195.3 | 994 | 1212.2 |
| idle | 5 | 224.6 | 221.1 | 60 | 3742.6 |
| scale | 5 | 6133.1 | 6029.7 | 994 | 6170.1 |

Event breakdown for churn/scale: 299 workspace (appActivated) + 600 focus (focusMayHaveChanged) + 95 scan ticks (5700 s total dwell / 60 s interval) = 994.

## Trace Report Summary (churn, 10 repeats)

- **Recording length:** 13.2 s
- **Total samples:** 12,469
- **Total CPU:** 12,469 ms

### Share by Binary (inclusive)

| Binary | Samples | Share |
|---|---:|---:|
| SwiftData | 9,826 | 78.8% |
| CoreData | 5,047 | 40.5% |
| libsqlite3.dylib | 676 | 5.4% |
| perf-bench | 11,566 | 92.8% |

### Top Inclusive Functions (perf-bench)

| Function | Samples | Share |
|---|---:|---:|
| `AppCore.flushTrackerState()` | 8,131 | 65.2% |
| `Store.save()` | 5,245 | 42.1% |
| `Store.saveTrackedWindows(_:)` | 2,663 | 21.4% |
| `Store.loadTrackedWindowRecords()` | 2,650 | 21.3% |
| `AppCore.reduce(_:)` | 2,536 | 20.3% |
| `AppCore.replan()` | 2,314 | 18.6% |
| `Store.ruleSet()` | 1,634 | 13.1% |
| `Store.appRules()` | 1,613 | 12.9% |

### Signposts

| Name | Count | Total (ms) | Mean (ms) |
|---|---:|---:|---:|
| reduce | 13,160 | 2,540.5 | 0.19 |
| replan | 13,170 | 2,359.9 | 0.18 |
| scan | 960 | 255.8 | 0.27 |
| inspect | 3,190 | 148.3 | 0.05 |
| focusedWindowID | 9,950 | 125.3 | 0.01 |

**CPU per event:** 1.25 ms (12,469 ms / 9,940 events)

## What It Shows

The benchmark confirms the investigation findings from the live app trace. SwiftData dominates at 78.8% of inclusive samples. The single largest cost is `flushTrackerState()` (65.2%), which fires on every persistence debounce and calls `saveTrackedWindows` (fetches all records, sets every property, saves). `Store.ruleSet()` at 13.1% shows the re-fetch pattern in `replan()` and `drainExecutor()` adds up.

Phase 3 (remove tracked-window persistence) should eliminate the 65% `flushTrackerState` path. Phase 4 (cache rule set in memory) should eliminate the 13% `Store.ruleSet()` path. Together they target roughly 78% of the current CPU, well above the 50% reduction goal.
