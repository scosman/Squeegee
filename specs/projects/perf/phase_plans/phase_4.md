---
status: complete
---

# Phase 4: Rule Set in Memory

## Overview

Cache the `RuleSet` as a stored property in `AppCore` so that `replan()` and the executor re-check in `drainExecutor()` use the cached copy instead of calling `store.ruleSet()` (which reads from SwiftData). The observation-based reload in `observeRules()` keeps the cache current. This removes two SwiftData round-trips per replan cycle.

## Steps

1. Add `private var ruleSet: RuleSet` to `AppCore`, initialized from `store.ruleSet()` in `init`.
2. Rewrite `observeRules()` to reload `ruleSet` from `store.ruleSet()` first, then re-subscribe, then replan — matching the architecture spec section 4 pattern.
3. Replace `store.ruleSet()` with `ruleSet` in the `replan()` `PlanInput`.
4. Replace `store.ruleSet()` with `ruleSet` in the `drainExecutor()` fresh-plan re-check.
5. Leave other callers of `store.ruleSet()` unchanged (e.g. `dryRun` takes its rule set as a parameter).
6. Update the Squeegee `architecture.md` to note the in-memory `RuleSet` cache in AppCore (architecture spec section 5).

## Tests

- `ruleEditCloseAfterUpdatesDeadline`: edit the global rule's `closeAfter` after `start()` — verify the next plan uses the new deadline.
- `addAppRuleShowsAppRuleSource`: add an app rule — verify the window's schedule shows `ruleSource == .app` with the app rule's deadline.
- `removeAppRuleFallsBackToGlobal`: remove an app rule — verify the schedule goes back to `.global`.
- `disableAppRuleMakesScheduleDisabled`: disable an app rule — verify the schedule status is `.disabled` and no close action is planned for a past-due window.
