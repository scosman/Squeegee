---
status: complete
---

# Implementation Plan: Perf

Specs: [functional_spec.md](functional_spec.md), [architecture.md](architecture.md). No changes under `Kit/Sources/SystemBridge/` in any phase.

## Phases

- [x] Phase 1: Measurement tooling. Signposts in AppCore (architecture §1), `--profiling-store` launch argument (§2.1), `make profile-app` (§2.2), `scripts/profile/run.sh` + `analyze_trace.py` (§2.3–2.4), release dSYM zip (§2.5), hooks-mcp `profile_app` (§2.6), `CLAUDE.md` profiling note (§5). Prove `make profile-app` builds, and smoke-test the analyzer on a short trace.
- [ ] Phase 2: Baseline run. Run `scripts/profile/run.sh baseline` (agent-driven, user uses the Mac for 5 min). Commit the report as `measurements/baseline.md`, with a short summary of what it shows. No code changes.
- [ ] Phase 3: Tracked windows in memory only. Schema V2 + lightweight migration, removals, migration test, and the Squeegee spec/engine doc updates for restore (architecture §3, §5).
- [ ] Phase 4: Rule set in memory. Cached `RuleSet` + observation reload, scenario tests, Squeegee architecture doc note (architecture §4, §5).
- [ ] Phase 5: Final run. Run `scripts/profile/run.sh final`, commit `measurements/final.md` with a comparison against the baseline and the pass/fail result (functional spec §4). Then discuss the next steps with the user.
