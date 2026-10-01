---
status: draft
---

# Phase 5: AppCore

## Overview

Build the `AppCore` orchestrator that wires together the Engine (tracker, planner), Persistence (Store), and Presentation (MenuContentBuilder) through injected port protocols. AppCore is the event pump, executor, and state publisher for the entire app. This phase also builds the `TestSupport` fakes (`FakeScheduler`, `FakeWindowSystem`, etc.) and the scenario tests (engine.md tests 35-47).

## Steps

1. **TestSupport fakes** (`Tests/TestSupport/`): `FakeScheduler` (manual `now`, `advance(to:)`/`advance(by:)` fires due actions in time order), `FakeWindowLister`, `FakeWindowInspector`, `FakeWindowCloser`, `FakeAppTerminator`, `FakeWorkspaceEvents`, `FakeFocusObserver`, `FakeAccessibilityPermission`, `FakeLoginItem`, `FakeInstalledAppScanner`, `FakeAppOpener`, and a helper `FakePorts` that bundles them.

2. **AppCore class** (`Sources/AppCore/AppCore.swift`): `@MainActor @Observable public final class AppCore` with the public surface from engine.md section 6.1. Init takes `Store`, `AppCorePorts`, `SuggestionCatalog`, `Calendar`.

3. **Event pump** (section 6.3): `start()` initializes permission, route, starts event stream tasks, runs initial sync (scan, restore, inspect all, syncFocus, start scan timer), starts rule observation, and calls `replan()`.

4. **Replan and executor** (section 6.4): `replan()` runs the Planner, clears expired pauses, re-arms the deadline timer, and queues actions. The executor runs one action at a time through ports, feeding results back as TrackerEvents.

5. **Rule observation** (section 6.5): `withObservationTracking` on `store.ruleSet()` triggers `replan()` on any rule change.

6. **Pause** (section 6.6): `pause(_:)` and `resume()` write to store settings and replan.

7. **Permission handling** (section 6.3): `refreshPermission()` reads `isTrusted()`, inspects all pids on grant, replans.

8. **Tracker persistence** (section 6.7): 5 s debounce on dirty tracker state, `prepareForTermination()` saves immediately.

9. **Onboarding and suggestions** (section 6.8): `suggestions()`, `applySuggestions()`, `completeOnboarding()`.

10. **Menu content, schedules, dry run, reopen, recentClosures** (section 6.9): delegate to Presentation and Store.

11. **Scenario tests** (`Tests/AppCoreTests/`): tests 35-47 from engine.md section 8.

## Tests

- Test 35: Finder window close after 6h, history record with title and no URL
- Test 36: Save dialog keeps window, focus resets deadline, closes after next period
- Test 37: Kept element on another Space, unreachable then closes on Space change
- Test 38: QuickTime Always quit after 60s grace
- Test 39: ifClosedBySqueegee quit vs user-closed
- Test 40: Pause one hour blocks closes, resumes after
- Test 41: Permission revoked stops actions, granted resumes
- Test 42: Displays sleep stops scan timer, wake restarts
- Test 43: Focus signal from non-frontmost pid ignored
- Test 44: Restart restore of tracked windows
- Test 45: Rule edit through store triggers replan
- Test 46: Onboarding suggestions filter, apply, complete
- Test 47: Reopen with URL opens file, without URL launches app, quit launches app
