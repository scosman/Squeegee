---
status: complete
---

# Phase 3: Tracked Windows in Memory Only

## Overview

Remove tracked-window persistence from SwiftData. Window state (opened time, last-active time, close state) lives in memory only and resets on Squeegee restart. This eliminates the biggest SwiftData write path (the 5 s debounce save of all tracked windows), which the baseline trace showed as the dominant CPU cost.

## Steps

1. Create `SchemaV2.swift` with `SqueegeeSchemaV2: VersionedSchema` containing `AppRuleRecord`, `AppSettingsRecord`, and `ClosureRecord` (no `TrackedWindowRecord`). `versionIdentifier = Schema.Version(2, 0, 0)`.

2. Update `MigrationPlan.swift`: `schemas = [SqueegeeSchemaV1.self, SqueegeeSchemaV2.self]`, `stages = [.lightweight(fromVersion: SqueegeeSchemaV1.self, toVersion: SqueegeeSchemaV2.self)]`.

3. Update `Store.swift`: point typealiases to `SqueegeeSchemaV2.*`; delete `TrackedWindowRecord` typealias; change schema to `SqueegeeSchemaV2`; remove `saveTrackedWindows`, `loadTrackedWindows`, `loadTrackedWindowRecords`, and the "Tracked windows" MARK section.

4. Remove `TrackerEvent.restore` case and `TrackedWindowSnapshot` from `TrackerTypes.swift`.

5. Remove `handleRestore` from `TrackerReducer+Lifecycle.swift`; remove the `.restore` case from the switch in `TrackerReducer.swift`.

6. Delete `TrackerState+Snapshots.swift`.

7. In `AppCore.swift`: remove `trackerDirty`, `persistenceDebounce`, `persistenceDebounceInterval`; remove `markTrackerDirty()` call in `reduce`; remove the entire "Tracker persistence" extension (`markTrackerDirty`, `flushTrackerState`); remove `prepareForTermination()`; remove `reduce(.restore(...))` line from `start()`.

8. Remove `"restore"` label from `Signposts.swift`.

9. In `AppDelegate.swift`: remove `applicationWillTerminate`.

10. Remove restore tests (Test 18) from `TrackerReducerTests.swift`; remove tracked-window tests from `StoreTests.swift`; remove Test 44 (restart restore) from `AppCoreScenarioTests.swift`.

11. Write migration test `migratesV1StoreToV2KeepingRulesSettingsAndHistory` in `PersistenceTests/StoreTests.swift`.

12. Update Squeegee docs: `functional_spec.md` (remove restore rule, update stored data), `architecture.md` (remove TrackedWindowRecord, note schema V2), `components/engine.md` (remove restore event, tests 18 and 44), `backlog.md` (add updateBounds bug).

## Tests

- `migratesV1StoreToV2KeepingRulesSettingsAndHistory`: opens a V1 store with all four model types populated, reopens as V2 via `Store`, verifies rules/settings/closures survived and tracked windows are gone.
- Existing tests pass after removing the restore and tracked-window tests.
