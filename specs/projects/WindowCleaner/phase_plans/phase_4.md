---
status: complete
---

# Phase 4: Persistence and Presentation

## Overview

This phase builds two modules that Phase 3 left as stubs: **Persistence** (SwiftData schema V1 with the Store API) and **Presentation** (formatters, rule summaries, and the MenuContentBuilder). Together they provide the data layer and the pure text/menu logic that Phase 5 (AppCore) and Phase 6 (UI) will consume.

## Steps

### Persistence module

1. **SwiftData schema V1** (`Persistence/Schema/SchemaV1.swift`): Define `WindowCleanerSchemaV1: VersionedSchema` with the four `@Model` types: `AppRuleRecord`, `AppSettingsRecord`, `ClosureRecord`, `TrackedWindowRecord` — fields exactly as architecture.md section 4.2.

2. **Migration plan** (`Persistence/Schema/MigrationPlan.swift`): `WindowCleanerMigrationPlan: SchemaMigrationPlan` with a single stage (V1, no migrations yet).

3. **Store** (`Persistence/Store.swift`): `@MainActor public final class Store` with:
   - `StoreConfiguration` enum (`.onDisk(URL)`, `.inMemory`)
   - `init(configuration:) throws` — creates `ModelContainer` with the schema and migration plan
   - `settings` computed property returning the singleton `AppSettingsRecord`
   - `appRules() -> [AppRuleRecord]` sorted by appName
   - `appRule(bundleID:) -> AppRuleRecord?`
   - `addAppRule(bundleID:appName:rule:) -> AppRuleRecord`
   - `removeAppRule(bundleID:)`
   - `ruleSet() -> RuleSet` mapping records to Engine values
   - `appendClosure(_ value: ClosureValue)` with FIFO trim to 1000
   - `recentClosures(limit:) -> [ClosureValue]`
   - `saveTrackedWindows(_:)` — upsert by (pid,windowID), delete rows not in input
   - `loadTrackedWindows() -> [TrackedWindowSnapshot]`
   - `save()` — explicit context save

### Presentation module

4. **Time formatters** (`Presentation/TimeFormatting.swift`): Functions for the formats in ui_design section 7:
   - `formatTimeLeft(deadline:now:) -> String` — e.g. "in 2h 10m", "in <1m"
   - `formatTimeAgo(date:now:calendar:) -> String` — e.g. "just now", "20m ago", "yesterday", "Sep 12"
   - `formatPausedUntil(date:now:calendar:) -> String` — e.g. "Paused until 3:40 PM"
   - `formatScheduleStatus(_:deadline:now:) -> String` — status text for Up Next and Open Windows

5. **Rule summaries** (`Presentation/RuleSummary.swift`): Two formats:
   - `sidebarSummary(rule:) -> String` — "6h . last active", "Off", "2h . opened . quits"
   - `suggestionSummary(rule:) -> String` — "Close windows 6h after last use, then quit"

6. **MenuContent types** (`Presentation/MenuContent.swift`): Value types `MenuContent`, `MenuSection`, `MenuItem`, `MenuAction` for the pure menu description.

7. **MenuContentBuilder** (`Presentation/MenuContentBuilder.swift`): `MenuContentBuilder.build(input:) -> MenuContent` that assembles the menu structure from plan schedules, recent closures, pause/permission state (ui_design section 3.2).

## Tests

### PersistenceTests

- `testSettingsSingletonCreated`: A new store creates one `AppSettingsRecord` with defaults.
- `testAddAndFetchAppRules`: Add rules, fetch sorted by name.
- `testAddDuplicateReturnsExisting`: Adding a rule for the same bundle ID returns the existing one.
- `testRemoveAppRule`: Remove a rule, verify it's gone.
- `testRuleSetMapping`: `ruleSet()` produces the correct `Engine.RuleSet`.
- `testAppendClosureFIFOTrim`: Append 1005 closures, verify only 1000 remain and the oldest are trimmed.
- `testRecentClosuresOrder`: Recent closures come newest-first.
- `testSaveAndLoadTrackedWindows`: Upsert + delete-stale round trip.
- `testObservationFires`: Verify `withObservationTracking` on `ruleSet()` fires for insert, delete, and property edit.

### PresentationTests

- `testTimeLeftFormatting`: Table-driven for every format row in ui_design section 7.
- `testTimeAgoFormatting`: Table-driven for "just now", minutes, hours, yesterday, and date formats.
- `testPausedUntilFormatting`: Today vs other day.
- `testScheduleStatusText`: Each `ScheduleStatus` value produces the correct string.
- `testSidebarSummary`: Off, enabled with defaults, with quit.
- `testSuggestionSummary`: With and without quit.
- `testMenuContentUpNext`: Schedules produce sorted menu items with correct status text.
- `testMenuContentRecentlyClosed`: Closures with/without URL produce correct items and actions.
- `testMenuContentPaused`: Pause banner and resume item appear.
- `testMenuContentPermissionMissing`: Permission banner appears.
- `testMenuContentEmpty`: Empty states produce placeholder items.
