import CoreGraphics
import Foundation
import Testing
@testable import Engine

// MARK: - Test helpers

private let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000) // swiftlint:disable:this identifier_name

private func date(_ offset: TimeInterval) -> Date {
    t0.addingTimeInterval(offset)
}

private func makeApp(pid: Int32 = 1, bundleID: String = "com.test.app", name: String = "TestApp", launchDate: Date? = nil) -> ObservedApp {
    ObservedApp(pid: pid, bundleID: bundleID, name: name, launchDate: launchDate)
}

private func makeObservedWindow(
    pid: Int32 = 1,
    windowID: UInt32 = 100,
    bundleID: String = "com.test.app",
    name: String = "TestApp",
    launchDate: Date? = nil
) -> ObservedWindow {
    let app = makeApp(pid: pid, bundleID: bundleID, name: name, launchDate: launchDate)
    return ObservedWindow(
        key: WindowKey(pid: pid, windowID: windowID),
        app: app,
        bounds: .zero,
        isOnScreen: true
    )
}

private func key(_ pid: Int32 = 1, _ windowID: UInt32 = 100) -> WindowKey {
    WindowKey(pid: pid, windowID: windowID)
}

// MARK: - Test 1: New window in scan

@Test func newWindowInScan_trackedWithFirstSeen_outputsNeedsInspection() {
    var state = TrackerState()
    let observed = makeObservedWindow()
    let outputs = TrackerReducer.reduce(&state, .windowList([observed], at: t0))

    #expect(state.windows[key()] != nil)
    #expect(state.windows[key()]?.firstSeen == t0)
    #expect(state.windows[key()]?.metadata == nil)
    #expect(state.windows[key()]?.closeState == CloseState.none)
    #expect(state.apps[1] != nil)
    #expect(outputs.contains(.needsInspection(pid: 1)))
}

// MARK: - Test 2: Window missing from scan, closeState .none

@Test func windowMissingScan_closeStateNone_removedNoOutput() {
    var state = TrackerState()
    // First add a window
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))
    // Inspect it so it has metadata (and thus no needsInspection output)
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([100: WindowMetadata(isStandard: true, title: "W")]),
        at: t0
    ))

    // Now remove it by sending an empty scan
    let outputs = TrackerReducer.reduce(&state, .windowList([], at: date(10)))

    #expect(state.windows[key()] == nil)
    // No closure output since closeState was .none
    let closureOutputs = outputs.filter {
        if case .windowClosedByWindowCleaner = $0 { return true }
        return false
    }
    #expect(closureOutputs.isEmpty)
}

// MARK: - Test 3: Window missing with .sent -> closure output, app becomes empty

@Test func windowMissingScan_closeStateSent_closureOutput_appBecomesEmpty() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([100: WindowMetadata(isStandard: true, title: "Doc")]),
        at: t0
    ))

    // Mark as close sent
    _ = TrackerReducer.reduce(&state, .closeSent(key(), wasListed: true, latest: nil, at: date(100)))

    // Remove window via empty scan
    let outputs = TrackerReducer.reduce(&state, .windowList([], at: date(200)))

    let closureOutputs = outputs.filter {
        if case .windowClosedByWindowCleaner = $0 { return true }
        return false
    }
    #expect(closureOutputs.count == 1)
    // App should be marked as empty after WindowCleaner close
    #expect(state.apps[1]?.quitAfterWindowCleanerClose == true)
}

// MARK: - Test 4: Window missing with .declined -> closure output

@Test func windowMissingScan_closeStateDeclined_closureOutput() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([100: WindowMetadata(isStandard: true, title: "Doc")]),
        at: t0
    ))

    // Mark as declined (user later chose Don't Save)
    _ = TrackerReducer.reduce(&state, .closeFailed(key(), at: date(100)))

    // Now the window actually disappears (user closed it manually after the save dialog)
    let outputs = TrackerReducer.reduce(&state, .windowList([], at: date(200)))

    let closureOutputs = outputs.filter {
        if case .windowClosedByWindowCleaner = $0 { return true }
        return false
    }
    #expect(closureOutputs.count == 1)
}

// MARK: - Test 5: Focus for 4.9 s -> lastActive unchanged

@Test func focusDuration4_9s_lastActiveUnchanged() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))

    // Focus the window
    _ = TrackerReducer.reduce(&state, .focusChanged(
        app: makeApp(), windowID: 100, at: t0
    ))

    // Focus changes after 4.9 s (below the 5 s threshold)
    _ = TrackerReducer.reduce(&state, .focusChanged(
        app: nil, windowID: nil, at: date(4.9)
    ))

    #expect(state.windows[key()]?.lastActive == nil)
}

// MARK: - Test 6: Focus for 5 s exactly -> lastActive updated, closeState resets

@Test func focusDuration5s_lastActiveUpdated_closeStateResets() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([100: WindowMetadata(isStandard: true, title: "W")]),
        at: t0
    ))

    // Set closeState to declined
    _ = TrackerReducer.reduce(&state, .closeFailed(key(), at: t0))
    #expect(state.windows[key()]?.closeState == .declined(at: t0))

    // Focus the window
    _ = TrackerReducer.reduce(&state, .focusChanged(
        app: makeApp(), windowID: 100, at: date(10)
    ))

    // Focus changes after exactly 5 s
    _ = TrackerReducer.reduce(&state, .focusChanged(
        app: nil, windowID: nil, at: date(15)
    ))

    #expect(state.windows[key()]?.lastActive == date(15))
    #expect(state.windows[key()]?.closeState == CloseState.none)
}

// MARK: - Test 7: Focus then displays sleep

@Test func focusThenDisplaysSleep_lastActiveSet_sessionNil_focusedKeyKept() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))

    // Focus the window
    _ = TrackerReducer.reduce(&state, .focusChanged(
        app: makeApp(), windowID: 100, at: t0
    ))

    // Displays sleep after 10 s (well past the 5 s threshold)
    _ = TrackerReducer.reduce(&state, .displaysSlept(at: date(10)))

    #expect(state.windows[key()]?.lastActive == date(10))
    #expect(state.session == nil)
    #expect(state.focusedKey == key())
}

// MARK: - Test 8: Focus event for untracked window

@Test func focusEventForUntrackedWindow_inserted_needsInspection() {
    var state = TrackerState()

    let outputs = TrackerReducer.reduce(&state, .focusChanged(
        app: makeApp(), windowID: 200, at: t0
    ))

    #expect(state.windows[key(1, 200)] != nil)
    #expect(state.windows[key(1, 200)]?.firstSeen == t0)
    #expect(outputs.contains(.needsInspection(pid: 1)))
}

// MARK: - Test 9: Inspected unreachable window -> .none, metadata set, hadStandardWindow

@Test func inspectedUnreachableWindow_closeStateNone_metadataSet_hadStandardWindow() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))

    // Mark the window as unreachable
    _ = TrackerReducer.reduce(&state, .closeUnreachable(key(), at: t0))
    #expect(state.windows[key()]?.closeState == .unreachable(since: t0))

    // Inspect with metadata
    let meta = WindowMetadata(isStandard: true, title: "Found")
    _ = TrackerReducer.reduce(&state, .inspected(pid: 1, .inspected([100: meta]), at: date(5)))

    #expect(state.windows[key()]?.closeState == CloseState.none)
    #expect(state.windows[key()]?.metadata == meta)
    #expect(state.apps[1]?.hadStandardWindow == true)
}

// MARK: - Test 10: Inspected omits known window -> metadata kept

@Test func inspectedOmitsKnownWindow_metadataKept() {
    var state = TrackerState()
    let ow1 = makeObservedWindow(windowID: 100)
    let ow2 = makeObservedWindow(windowID: 200)
    _ = TrackerReducer.reduce(&state, .windowList([ow1, ow2], at: t0))

    let meta100 = WindowMetadata(isStandard: true, title: "Window 100")
    let meta200 = WindowMetadata(isStandard: true, title: "Window 200")
    _ = TrackerReducer.reduce(&state, .inspected(pid: 1, .inspected([100: meta100, 200: meta200]), at: t0))

    // Second inspection omits window 200 (on another Space)
    let updatedMeta = WindowMetadata(isStandard: true, title: "Updated 100")
    _ = TrackerReducer.reduce(&state, .inspected(pid: 1, .inspected([100: updatedMeta]), at: date(10)))

    #expect(state.windows[key(1, 100)]?.metadata == updatedMeta)
    #expect(state.windows[key(1, 200)]?.metadata == meta200) // kept
}

// MARK: - Test 11: Inspected .notTrusted -> permissionLost

@Test func inspectedNotTrusted_permissionLost() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))

    let outputs = TrackerReducer.reduce(&state, .inspected(pid: 1, .notTrusted, at: date(5)))
    #expect(outputs.contains(.permissionLost))
}

// MARK: - Test 12: Close verification

@Test func closeVerification_wasListedTrue_declined_wasListedFalse_unreachable() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))

    // Case 1: wasListed = true -> declined
    _ = TrackerReducer.reduce(&state, .closeSent(key(), wasListed: true, latest: nil, at: date(1)))
    _ = TrackerReducer.reduce(&state, .closeVerification(key(), at: date(11)))
    #expect(state.windows[key()]?.closeState == .declined(at: date(11)))

    // Reset for case 2
    state.windows[key()]?.closeState = .none

    // Case 2: wasListed = false -> unreachable
    _ = TrackerReducer.reduce(&state, .closeSent(key(), wasListed: false, latest: nil, at: date(20)))
    _ = TrackerReducer.reduce(&state, .closeVerification(key(), at: date(30)))
    #expect(state.windows[key()]?.closeState == .unreachable(since: date(30)))
}

// MARK: - Test 13: Close verification after window is gone

@Test func closeVerification_windowGone_noop() {
    var state = TrackerState()
    // No window in state
    let outputs = TrackerReducer.reduce(&state, .closeVerification(key(), at: t0))
    #expect(outputs.isEmpty)
}

// MARK: - Test 14: App terminated with quitState .sent

@Test func appTerminated_quitStateSent_appQuitOutput_noClosureOutputs() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([100: WindowMetadata(isStandard: true, title: "W")]),
        at: t0
    ))

    // Send quit
    _ = TrackerReducer.reduce(&state, .quitSent(pid: 1, at: date(10)))

    // Also mark the window as close sent (to verify no closure output for terminated windows)
    _ = TrackerReducer.reduce(&state, .closeSent(key(), wasListed: true, latest: nil, at: date(10)))

    // Terminate the app
    let outputs = TrackerReducer.reduce(&state, .appTerminated(pid: 1, at: date(20)))

    let quitOutputs = outputs.filter {
        if case .appQuitByWindowCleaner = $0 { return true }
        return false
    }
    #expect(quitOutputs.count == 1)

    // No window closure outputs from termination
    let closureOutputs = outputs.filter {
        if case .windowClosedByWindowCleaner = $0 { return true }
        return false
    }
    #expect(closureOutputs.isEmpty)

    // App and windows removed
    #expect(state.apps[1] == nil)
    #expect(state.windows[key()] == nil)
}

// MARK: - Test 15: App terminated with windows in .sent -> no closure outputs

@Test func appTerminated_windowsSent_noClosureOutputs() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))
    _ = TrackerReducer.reduce(&state, .closeSent(key(), wasListed: true, latest: nil, at: date(5)))

    // App terminates (quitState is .none, so no quit output)
    let outputs = TrackerReducer.reduce(&state, .appTerminated(pid: 1, at: date(10)))

    // No closure outputs: app termination does not produce them
    let closureOutputs = outputs.filter {
        if case .windowClosedByWindowCleaner = $0 { return true }
        return false
    }
    #expect(closureOutputs.isEmpty)
}

// MARK: - Test 16: Presence

@Test func presence_unknownMetadataKeepsAppPresent_lastStandardGoneSetsNoStandardWindowsSince() {
    var state = TrackerState()
    let ow1 = makeObservedWindow(windowID: 100)
    let ow2 = makeObservedWindow(windowID: 200)
    _ = TrackerReducer.reduce(&state, .windowList([ow1, ow2], at: t0))

    // Window 100 is standard, window 200 stays unknown (nil metadata)
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([100: WindowMetadata(isStandard: true, title: "Std")]),
        at: t0
    ))
    #expect(state.apps[1]?.hadStandardWindow == true)

    // Unknown metadata window (200) keeps the app present
    #expect(state.apps[1]?.noStandardWindowsSince == nil)

    // Now inspect window 200 as non-standard
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([100: WindowMetadata(isStandard: true, title: "Std"), 200: WindowMetadata(isStandard: false)]),
        at: date(5)
    ))

    // Still present because window 100 is standard
    #expect(state.apps[1]?.noStandardWindowsSince == nil)

    // Remove window 100 from the scan
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow(windowID: 200)], at: date(10)))

    // Now only non-standard window 200 remains, hadStandardWindow is true, so noStandardWindowsSince should be set
    #expect(state.apps[1]?.noStandardWindowsSince == date(10))

    // App that never had standard windows -> noStandardWindowsSince stays nil
    var state2 = TrackerState()
    let ow3 = makeObservedWindow(pid: 2, windowID: 300, bundleID: "com.test.other", name: "Other")
    _ = TrackerReducer.reduce(&state2, .windowList([ow3], at: t0))
    _ = TrackerReducer.reduce(&state2, .inspected(
        pid: 2,
        .inspected([300: WindowMetadata(isStandard: false)]),
        at: t0
    ))
    _ = TrackerReducer.reduce(&state2, .windowList([], at: date(10)))
    #expect(state2.apps[2]?.noStandardWindowsSince == nil)
}

// MARK: - Test 17: Quit verification

@Test func quitVerification_appAlive_declined_thenGetsWindow_none() {
    var state = TrackerState()
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow()], at: t0))
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([100: WindowMetadata(isStandard: true, title: "W")]),
        at: t0
    ))

    // Send quit, then verify -> declined
    _ = TrackerReducer.reduce(&state, .quitSent(pid: 1, at: date(10)))
    _ = TrackerReducer.reduce(&state, .quitVerification(pid: 1, at: date(40)))
    #expect(state.apps[1]?.quitState == .declined)

    // App gets a new window -> quitState resets because presence > 0
    let ow2 = makeObservedWindow(windowID: 200)
    _ = TrackerReducer.reduce(&state, .windowList([makeObservedWindow(), ow2], at: date(50)))
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([
            100: WindowMetadata(isStandard: true, title: "W"),
            200: WindowMetadata(isStandard: true, title: "W2")
        ]),
        at: date(50)
    ))
    #expect(state.apps[1]?.quitState == QuitState.none)
}

// MARK: - Test 18: Restore

@Test func restore_matchingPidLaunchDate_restoresTimesAndCloseSent() {
    let launchDate = date(-1000)
    var state = TrackerState()
    let observed = makeObservedWindow(launchDate: launchDate)
    _ = TrackerReducer.reduce(&state, .windowList([observed], at: t0))

    let matchingSnapshot = TrackedWindowSnapshot(
        key: key(),
        bundleID: "com.test.app",
        processLaunchDate: launchDate,
        firstSeen: date(-500),
        lastActive: date(-100),
        closeSentAt: nil
    )

    // Test matching snapshot restores times
    _ = TrackerReducer.reduce(&state, .restore([matchingSnapshot], at: t0))
    #expect(state.windows[key()]?.firstSeen == date(-500))
    #expect(state.windows[key()]?.lastActive == date(-100))

    // Reset and test closeSentAt -> declined
    state.windows[key()]?.firstSeen = t0
    state.windows[key()]?.lastActive = nil
    state.windows[key()]?.closeState = .none
    let closeSentSnapshot = TrackedWindowSnapshot(
        key: key(),
        bundleID: "com.test.app",
        processLaunchDate: launchDate,
        firstSeen: date(-500),
        lastActive: date(-100),
        closeSentAt: date(-50)
    )
    _ = TrackerReducer.reduce(&state, .restore([closeSentSnapshot], at: t0))
    #expect(state.windows[key()]?.firstSeen == date(-500))
    #expect(state.windows[key()]?.lastActive == date(-100))
    #expect(state.windows[key()]?.closeState == .declined(at: date(-50)))
}

@Test func restore_mismatchedLaunchDate_droppedSnapshot() {
    var state = TrackerState()
    let obs = makeObservedWindow(launchDate: date(-3000))
    _ = TrackerReducer.reduce(&state, .windowList([obs], at: t0))

    let mismatchSnapshot = TrackedWindowSnapshot(
        key: key(),
        bundleID: "com.test.app",
        processLaunchDate: date(-2000), // different from app launch date
        firstSeen: date(-500),
        lastActive: date(-100),
        closeSentAt: nil
    )
    _ = TrackerReducer.reduce(&state, .restore([mismatchSnapshot], at: t0))
    #expect(state.windows[key()]?.firstSeen == t0) // not restored
}

// MARK: - Test 19: Non-standard sibling does not prevent quitAfterWindowCleanerClose

@Test func windowMissingScan_nonStandardSibling_quitAfterWindowCleanerCloseTrue() {
    var state = TrackerState()
    let ow1 = makeObservedWindow(windowID: 100)
    let ow2 = makeObservedWindow(windowID: 200)
    _ = TrackerReducer.reduce(&state, .windowList([ow1, ow2], at: t0))
    _ = TrackerReducer.reduce(&state, .inspected(
        pid: 1,
        .inspected([
            100: WindowMetadata(isStandard: true, title: "Doc"),
            200: WindowMetadata(isStandard: false)
        ]),
        at: t0
    ))

    // Mark window 100 as close sent
    _ = TrackerReducer.reduce(&state, .closeSent(key(1, 100), wasListed: true, latest: nil, at: date(100)))

    // Remove window 100 (window 200, non-standard, remains)
    let outputs = TrackerReducer.reduce(&state, .windowList([ow2], at: date(200)))

    let closureOutputs = outputs.filter {
        if case .windowClosedByWindowCleaner = $0 { return true }
        return false
    }
    #expect(closureOutputs.count == 1)
    // Non-standard sibling should not prevent the quit flag
    #expect(state.apps[1]?.quitAfterWindowCleanerClose == true)
}
