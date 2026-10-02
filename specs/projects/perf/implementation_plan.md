---
status: complete
---

# Implementation Plan: Perf

Specs: [functional_spec.md](functional_spec.md), [architecture.md](architecture.md). No changes under `Kit/Sources/SystemBridge/` in any phase.

## Phases

- [x] Phase 1: Measurement tooling. Signposts in AppCore (architecture §1), `--profiling-store` launch argument (§2.1), `make profile-app` (§2.2), `scripts/profile/run.sh` + `analyze_trace.py` (§2.3–2.4), release dSYM zip (§2.5), hooks-mcp `profile_app` (§2.6), `CLAUDE.md` profiling note (§5). Prove `make profile-app` builds, and smoke-test the analyzer on a short trace.
- [x] Phase 2: Benchmark and baseline. Build `perf-bench`, `make bench`, `make bench-profile`, the analyzer `--binary` option and nits (architecture §2.7). Run `make bench-profile LABEL=baseline` on the pre-fix code, and commit `measurements/baseline.md` (the bench table, the trace report summary, and a short note on what it shows). No changes to the product code.
- [x] Phase 3: Tracked windows in memory only. Schema V2 + lightweight migration, removals, migration test, and the Squeegee spec/engine doc updates for restore (architecture §3, §5).
- [x] Phase 4: Rule set in memory. Cached `RuleSet` + observation reload, scenario tests, Squeegee architecture doc note (architecture §4, §5).
- [ ] Phase 5: Final run. Run `make bench-profile LABEL=final`, commit `measurements/final.md` with a comparison against the baseline and the pass/fail result (functional spec §4). Then discuss the next steps with the user (and offer the optional live run).
