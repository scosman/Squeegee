---
status: complete
---

# Phase 3: Engine Core

## Overview

Implements the pure decision core of Squeegee: the domain value types for tracker state, the `TrackerReducer` (event sourcing over `TrackerState`), the `Planner` (state + rules + time -> schedules + actions + wake time), `dryRun`, and the `SuggestionCatalog`. All code lives in the `Engine` module (Foundation only, pure). `RuleSet` resolution was already built in Phase 2. Tests 1-34 from engine.md section 8 cover every reducer and planner branch.

## Steps

1. **Engine/Types/TrackerTypes.swift** -- Domain value types from engine.md section 2:
   - `CloseState` enum (none, sent, declined, unreachable)
   - `TrackedWindow` struct (key, bundleID, appName, firstSeen, lastActive, metadata, closeState)
   - `QuitState` enum (none, sent, declined)
   - `TrackedApp` struct (pid, bundleID, appName, launchDate, hadStandardWindow, noStandardWindowsSince, quitAfterSqueegeeClose, quitState)
   - `FocusSession` struct (key, start)
   - `TrackerState` struct (windows, apps, frontmostPID, focusedKey, session)
   - `TrackerEvent` enum (all 13 cases from the spec)
   - `TrackerOutput` enum (4 cases)
   - `TrackedWindowSnapshot` struct (for persistence restore)
   - `ClosureValue` struct (bundleID, appName, windowTitle, documentURL, kind, closedAt)

2. **Engine/Types/PlannerTypes.swift** -- Planner types from engine.md section 5:
   - `ScheduleStatus` enum (7 cases)
   - `WindowSchedule` struct (Identifiable via key)
   - `PlannedAction` enum (closeWindow, quitApp)
   - `PlanInput` struct
   - `Plan` struct with `.empty` static
   - `DryRunResult` struct

3. **Engine/Types/SuggestionTypes.swift** -- Types for the suggestion catalog:
   - `SuggestionCategory` enum (5 cases in display order)
   - `CatalogEntry` struct (bundleID, category, rule)
   - `Suggestion` struct (entry, appName, appURL)

4. **Engine/TrackerReducer.swift** -- `enum TrackerReducer` with `static func reduce(_ state: inout TrackerState, _ event: TrackerEvent) -> [TrackerOutput]`. Implements all event handlers from engine.md section 4: windowList, inspected, focusChanged, displaysSlept, appTerminated, close lifecycle events, quit lifecycle events, restore. Plus the constants enum `Tracker` (focusQualifyingDuration = 5, alwaysQuitGrace = 60, closeVerificationDelay = 10, quitVerificationDelay = 30).

5. **Engine/Planner.swift** -- `enum Planner` with `static func plan(_ input: PlanInput) -> Plan` and `static func dryRun(...)`. Implements per-window scheduling, per-app quit logic, nextWakeAt, sorting, and effectiveLastActive helper.

6. **Engine/SuggestionCatalog.swift** -- `struct SuggestionCatalog` with static entries from functional spec section 11 (19 apps across 5 categories). The `suggestions(installedApps:excludingBundleIDs:) -> [Suggestion]` matching method.

7. **Engine/TrackerState+Snapshots.swift** -- Extension on `TrackerState` for `snapshots() -> [TrackedWindowSnapshot]` used by persistence.

## Tests

Tests 1-18 (TrackerReducer):
- test 1: newWindowInScan_trackedWithFirstSeen_outputsNeedsInspection
- test 2: windowMissingScan_closeStateNone_removedNoOutput
- test 3: windowMissingScan_closeStateSent_closureOutput_appBecomesEmpty
- test 4: windowMissingScan_closeStateDeclined_closureOutput
- test 5: focusDuration4_9s_lastActiveUnchanged
- test 6: focusDuration5s_lastActiveUpdated_closeStateResets
- test 7: focusThenDisplaysSleep_lastActiveSet_sessionNil_focusedKeyKept
- test 8: focusEventForUntrackedWindow_inserted_needsInspection
- test 9: inspectedUnreachableWindow_closeStateNone_metadataSet_hadStandardWindow
- test 10: inspectedOmitsKnownWindow_metadataKept
- test 11: inspectedNotTrusted_permissionLost
- test 12: closeVerification_wasListedTrue_declined_wasListedFalse_unreachable
- test 13: closeVerification_windowGone_noop
- test 14: appTerminated_quitStateSent_appQuitOutput_noClosureOutputs
- test 15: appTerminated_windowsSent_noClosureOutputs
- test 16: presence_unknownMetadataKeepsAppPresent_lastStandardGoneSetNoStandardWindowsSince
- test 17: quitVerification_appAlive_declined_thenGetsWindow_none
- test 18: restore_matchingPidLaunchDate_restoresTimes_mismatchDropped_closeSentDeclined

Tests 19-34 (Planner):
- test 19: ruleDisabled_statusDisabled_noAction
- test 20: globalRuleApplies_appRuleOverrides
- test 21: openedDeadline_lastActiveDeadline
- test 22: focusedWindowQualifyingSession_deadlineMovesWithNow
- test 23: dueFocusedWindowShortSession_dueInUse_noAction
- test 24: duePaused_statusDuePaused_noAction_pauseEndInWake
- test 25: dueNoPermission_noAction
- test 26: dueUnreachable_statusDueUnreachable_noAction
- test 27: dueCloseStateNone_closeWindowAction
- test 28: closeStateSent_closing_declined_keptOpen
- test 29: nonStandardOrUnknownMetadata_noSchedule
- test 30: alwaysQuit_noWindowsSince60s_quitAction_notFrontmost_notGlobal_notFinder
- test 31: ifClosedBySqueegee_quitAfterFlagAndEmpty
- test 32: nextWakeAt_earliestFutureDeadline
- test 33: scheduleSortOrder
- test 34: dryRun_ignoresPausePermission_draftRuleChanges
