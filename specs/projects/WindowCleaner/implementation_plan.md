---
status: complete
---

# Implementation Plan: WindowCleaner

Risk goes first: the system layer and its hardware harness come before any UI. Every phase leaves `make ci` green.

## Phases

- [ ] Phase 1: Scaffolding. `WindowCleanerKit` package with all module skeletons and test targets (architecture §3), `TestSupport` target, Makefile with pinned lint/format tools, `.swiftlint.yml`/`.swiftformat`, CI workflow (3 tiers), `hooks_mcp.yaml`/`.mcp.json`, `.githooks/pre-commit`, a thin XcodeGen `App/` that launches as an empty menu bar app, the XcodeGen `ManualTestApp/` shell, `ManualTestKit` + the `manual-tests-check` executable (ported from Biscotti), and `CLAUDE.md` (architecture §9).
- [ ] Phase 2: Engine core. Value types, ports, `RuleSet` resolution, `TrackerReducer`, `Planner` + `dryRun`, `SuggestionCatalog`, with the full reducer/planner test list (engine.md §8, tests 1–34).
- [ ] Phase 3: System layer and hardware harness. All `SystemBridge` live ports (system_layer.md) with pure-helper unit tests; the ManualTestApp Live Inspector and all `sb_*` scripts (manual_test_app.md). Ends with a human hardware pass and `hardware_findings.md`.
- [ ] Phase 4: Persistence and Presentation. SwiftData schema V1 + `Store` (FIFO 1000, tracked-window upsert, observation of rule edits), formatters, rule summaries, and `MenuContentBuilder`, with tests.
- [ ] Phase 5: AppCore. `AppScheduler` (live + fake), event pump, executor, replan/timer, pause, permission handling, restore, suggestions/onboarding APIs, reopen, dry run; TestSupport fakes; scenario tests (engine.md §8, tests 35–47).
- [ ] Phase 6: App shell and Settings. Composition root, window/route/activation-policy handling, reopen-to-settings, login item; `SharedUI`, `SettingsUI` (sidebar, General, Rule page with Open Windows, add-app menu, Suggestions sheet), `AppShellUI`. This is the first runnable end-to-end app.
- [ ] Phase 7: Menu bar. `MenuBarUI` (`StatusItemController`, `MenuRenderer`, icon states, hide-icon toggle), with renderer tests.
- [ ] Phase 8: Onboarding. `OnboardingUI` (scaffold, progress header, footer, 4 screens, permission row), first-launch flow, and view model tests.
- [ ] Phase 9: Release. `scripts/release.sh` + `make release` (Developer ID archive, notarize, staple, DMG), README, and final `CLAUDE.md` updates.
