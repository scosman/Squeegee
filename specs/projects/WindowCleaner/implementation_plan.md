---
status: complete
---

# Implementation Plan: WindowCleaner

Risk goes first. Phases 1–2 build only what the hardware validation needs. Then a **hardware checkpoint** resolves every system unknown before any engine, persistence, or UI code is written. Phases 3–9 are low-risk work that can run with `/spec implement all`. Every phase leaves `make ci` green.

**How to run:** `/spec implement phase 1`, then `/spec implement phase 2`, then the hardware checkpoint (human), then `/spec implement all`.

## Phases

- [ ] Phase 1: Scaffolding. `WindowCleanerKit` package with all module skeletons and test targets (architecture §3), `TestSupport` target, Makefile with pinned lint/format tools, `.swiftlint.yml`/`.swiftformat`, CI workflow (3 tiers), `hooks_mcp.yaml`/`.mcp.json`, `.githooks/pre-commit`, a thin XcodeGen `App/` that launches as an empty menu bar app, the XcodeGen `ManualTestApp/` shell, `ManualTestKit` + the `manual-tests-check` executable (ported from Biscotti), and `CLAUDE.md` (architecture §9).
- [ ] Phase 2: System layer and hardware harness. In `Engine`, only the port protocols and their value types (system_layer.md §1, including `AppScheduler`). All `SystemBridge` live ports (including `LiveAppScheduler`), with pure-helper unit tests. The ManualTestApp Live Inspector (with the Monitor loop) and all `sb_*` scripts (manual_test_app.md).
- [ ] **Hardware checkpoint (human, not an agent phase).** Run every `sb_*` step on real hardware, commit the results and `hardware_findings.md`, and update engine.md / system_layer.md if a finding changes the design (manual_test_app.md §4). Phase 3 does not start until this is done.
- [ ] Phase 3: Engine core. Domain value types, `RuleSet` resolution, `TrackerReducer`, `Planner` + `dryRun`, `SuggestionCatalog`, with the full reducer/planner test list (engine.md §8, tests 1–34).
- [ ] Phase 4: Persistence and Presentation. SwiftData schema V1 + `Store` (FIFO 1000, tracked-window upsert, observation of rule edits), formatters, rule summaries, and `MenuContentBuilder`, with tests.
- [ ] Phase 5: AppCore. Event pump, executor, replan/timer, pause, permission handling, restore, suggestions/onboarding APIs, reopen, dry run; TestSupport fakes (including `FakeScheduler`); scenario tests (engine.md §8, tests 35–47).
- [ ] Phase 6: App shell and Settings. Composition root, window/route/activation-policy handling, reopen-to-settings, login item; `SharedUI`, `SettingsUI` (sidebar, General, Rule page with Open Windows, add-app menu, Suggestions sheet), `AppShellUI`. This is the first runnable end-to-end app.
- [ ] Phase 7: Menu bar. `MenuBarUI` (`StatusItemController`, `MenuRenderer`, icon states, hide-icon toggle), with renderer tests.
- [ ] Phase 8: Onboarding. `OnboardingUI` (scaffold, progress header, footer, 4 screens, permission row), first-launch flow, and view model tests.
- [ ] Phase 9: Release. `scripts/release.sh` + `make release` (Developer ID archive, notarize, staple, DMG), README, and final `CLAUDE.md` updates.
