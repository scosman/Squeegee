---
status: complete
---

# Phase 2: System Layer and Hardware Harness

## Overview

Build the port protocols and value types in Engine, all live SystemBridge implementations, pure-helper unit tests for SystemBridge, and the ManualTestApp Live Inspector with Monitor loop and wired scripts. This phase produces everything the hardware checkpoint needs to validate real system behavior before any engine logic is written.

## Steps

### Engine: Port protocols and value types

1. Create `Engine/Types/WindowKey.swift` with `WindowKey` (pid + windowID, Hashable/Sendable/Codable).
2. Create `Engine/Types/Rule.swift` with `MeasureFrom`, `QuitPolicy`, `Rule`, `RuleSet`, `ResolvedRule`.
3. Create `Engine/Ports/PortValues.swift` with `ObservedApp`, `ObservedWindow`, `WindowMetadata`, `InspectionResult`, `CloseAttemptResult`, `WorkspaceEvent`, `FocusSignal`, `InstalledApp`.
4. Create `Engine/Ports/Ports.swift` with all port protocols: `WindowListing`, `WindowInspecting`, `WindowClosing`, `AppTerminating`, `WorkspaceEventSource`, `FocusObserving`, `AccessibilityPermissionPort`, `LoginItemPort`, `InstalledAppScanning`, `AppOpening`, `AppScheduler`, `Cancellable`, and `AppCorePorts`.

### SystemBridge: Live port implementations

5. Create `SystemBridge/CGWindowLister.swift` implementing `WindowListing` with the static `parse` function and the excluded bundle ID list.
6. Create `SystemBridge/AXWindowService.swift` (actor) implementing `WindowInspecting` + `WindowClosing`, with the private bridge, element cache, inspect, focusedWindowID, close, and the static document URL mapping helpers.
7. Create `SystemBridge/FrontmostFocusObserver.swift` (`@MainActor final class`) implementing `FocusObserving` with one AXObserver, registration retry, and the C callback.
8. Create `SystemBridge/LiveWorkspaceEvents.swift` implementing `WorkspaceEventSource` with NSWorkspace notification mapping, frontmostApp, areDisplaysAsleep.
9. Create `SystemBridge/LiveAccessibilityPermission.swift` implementing `AccessibilityPermissionPort`.
10. Create `SystemBridge/LiveLoginItem.swift` implementing `LoginItemPort` via SMAppService.
11. Create `SystemBridge/LiveInstalledAppScanner.swift` implementing `InstalledAppScanning`.
12. Create `SystemBridge/LiveAppOpener.swift` implementing `AppOpening`.
13. Create `SystemBridge/LiveAppScheduler.swift` implementing `AppScheduler` with DispatchSource timers (wall time for one-shot, regular for repeating).
14. Create `SystemBridge/LiveAppTerminator.swift` implementing `AppTerminating`.
15. Create `SystemBridge/LivePorts.swift` with `public enum LivePorts { @MainActor public static func make() -> AppCorePorts }`.

### SystemBridge: Unit tests (pure helpers only)

16. Replace `SystemBridgeTests/PlaceholderTests.swift` with tests for `CGWindowLister.parse`: every filter rule (layer, alpha, own pid, min bounds, missing bundle ID, prohibited activation policy, excluded bundle IDs), missing keys, the happy path.
17. Add tests for the document URL mapping helpers (AXDocument string to URL, AXURL to file URL, non-file URL rejected).
18. Add tests for the AX error mapping table (`AXError -> InspectionResult?`).
19. Add tests for the fallback bounds matching (unique match, no match, ambiguous).

### ManualTestApp: Live Inspector and Monitor

20. Create `ManualTestApp/Sources/LiveInspectorView.swift`: a table showing CGWindowLister output joined with AXWindowService inspect metadata, frontmost app, focused window ID, and an event log of FocusSignal and WorkspaceEvent with timestamps.
21. Create `ManualTestApp/Sources/MonitorLoop.swift`: a standalone loop using SystemBridge ports (60s CG scan, FrontmostFocusObserver moved on each activation, inspect previous app on activation). Runs from a Monitor toggle in the Live Inspector.
22. Update `ManualTestApp/Sources/ScriptTabView.swift` to add the Live Inspector tab.

### ManualTestApp: Wired scripts

23. Update `ManualTestApp/Sources/WiredScripts.swift` to replace placeholder closures with real SystemBridge calls for all action and autoCheck steps.

### Cleanup

24. Remove `Engine/Placeholder.swift` and `SystemBridge/Placeholder.swift`.

## Tests

- `CGWindowListerParseTests`: parse happy path, each filter rule independently, missing keys, excluded bundle IDs, own pid filtering (8+ cases)
- `DocumentURLMappingTests`: AXDocument file URL accepted, non-file URL rejected, nil input, AXURL file URL accepted, AXURL non-file rejected (5+ cases)
- `AXErrorMappingTests`: apiDisabled -> notTrusted, cannotComplete -> appUnavailable, noValue -> inspected empty, success pass-through (4+ cases)
- `BoundsMatchingTests`: unique match returns window ID, no match returns nil, ambiguous returns nil (3 cases)
