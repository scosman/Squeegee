---
status: complete
---

# Phase 2: Benchmark and Baseline

## Overview

Build the deterministic `perf-bench` benchmark executable, the `make bench` / `make bench-profile` targets, and the `bench_profile.sh` script. Update `analyze_trace.py` with the `--binary` option and fix two Phase 1 nits. Add `bench` to hooks-mcp and update `CLAUDE.md`. No product code changes.

## Steps

1. Add `.executableTarget(name: "perf-bench", ...)` to `Kit/Package.swift` with dependencies `["AppCore", "Persistence", "Engine", "TestSupport"]`, path `"Sources/PerfBench"`.

2. Move the `settle()` helper from `AppCoreScenarioTests.swift` into `TestSupport` as a public function, so both the test target and `perf-bench` can use it.

3. Create `Kit/Sources/PerfBench/main.swift` implementing:
   - CLI parsing: `--scenario churn|idle|scale|all`, `--repeat N` (defaults: `all`, `5`).
   - Setup per repeat: temp dir, on-disk `Store`, global rule (enabled, 6h, lastActive), 3 app rules for `bench.app0/1/2` (6h, 8h, 12h; lastActive; quit `.never`), fakes from TestSupport, N windows round-robin over 10 apps.
   - Three scenarios: `churn` (N=50, 300 switches), `idle` (N=50, 60 ticks), `scale` (N=300, 300 switches).
   - Measurement via `getrusage(RUSAGE_SELF)` user+system CPU delta around the timed part.
   - Markdown table output to stdout.

4. Add `make bench` and `make bench-profile` targets to `Makefile`.

5. Create `scripts/profile/bench_profile.sh` that builds release, gets binary path, runs the bench, records an xctrace trace of a churn run, runs `analyze_trace.py --binary perf-bench`, prints both.

6. Update `scripts/profile/analyze_trace.py`:
   - Add `--binary NAME` CLI option (default `Squeegee`).
   - Use the binary name in the "top inclusive functions" section heading and binary share list.
   - Fix stale `parse_time_profile()` docstring (returns 5 values, not 6).
   - Fix dead `table.find("..")` fallback in `find_table_xpath()`: replace with default `run_number = "1"`.

7. Add `bench` action to `hooks_mcp.yaml` (`make bench`, timeout 600).

8. Update `CLAUDE.md`: add `make bench` and `make bench-profile` to the Makefile table, and one line in the Profiling section.

## Tests

- No new unit tests. The benchmark is not a test target.
- Verification: `make precommit-checks` passes (lint covers the new target).
