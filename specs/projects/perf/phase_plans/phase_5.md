---
status: complete
---

# Phase 5: Final Run

## Overview

Run the benchmark and trace on the post-fix code (after Phases 3 and 4 removed tracked-window persistence and cached the rule set). Compare results against the baseline to determine pass/fail per the functional spec criteria: churn CPU median at least 50% below baseline, and SwiftData/CoreData < 5% of trace samples.

## Steps

1. Run `make bench-profile LABEL=final` outside the sandbox to produce the benchmark table and trace analysis report.
2. Collect the benchmark table and trace report from the output directory.
3. Write `specs/projects/perf/measurements/final.md` with:
   - The benchmark table (all three scenarios).
   - A comparison table showing baseline vs final: CPU median, min, us/event, and percent change.
   - The trace report summary (share by binary, top functions, signposts).
   - Pass/fail determination against the two criteria.
4. Return the results and discuss next steps with the user per the functional spec.

## Tests

- No new tests. This phase is measurement-only.
