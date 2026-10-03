import AppCore
import CoreGraphics
import Engine
import Foundation
import Persistence
import Presentation
import Testing
import TestSupport

/// Helper to create an in-memory Store for tests.
@MainActor
private func makeStore() throws -> Store {
    try Store(configuration: .inMemory)
}

/// Helper: a standard observed window for a given app.
private func observedWindow(
    pid: Int32,
    windowID: UInt32,
    bundleID: String,
    appName: String,
    launchDate: Date? = nil
) -> ObservedWindow {
    let app = ObservedApp(pid: pid, bundleID: bundleID, name: appName, launchDate: launchDate)
    return ObservedWindow(
        key: WindowKey(pid: pid, windowID: windowID),
        app: app,
        bounds: CGRect(x: 0, y: 0, width: 800, height: 600),
        isOnScreen: true
    )
}

/// Helper: standard window metadata.
private func standardMeta(title: String? = nil, documentURL: URL? = nil) -> WindowMetadata {
    WindowMetadata(isStandard: true, title: title, documentURL: documentURL)
}

// settle() is provided by TestSupport

// MARK: - Tests

// swiftlint:disable type_body_length

@Suite("AppCore Scenarios")
struct AppCoreScenarioTests {
    @Test("35: Finder window close → resolver provides folder URL")
    @MainActor
    func finderWindowCloseAndHistory() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        let documentsURL = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        bundle.finderFolderResolver.folderURLsByTitle = ["Documents": documentsURL]
        store.settings.finderRestoreEnabled = true

        store.addAppRule(bundleID: "com.apple.finder", appName: "Finder", rule: Rule(
            isEnabled: true, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never
        ))

        let finderWindow = observedWindow(pid: 100, windowID: 1, bundleID: "com.apple.finder", appName: "Finder")
        bundle.windowLister.windows = [finderWindow]
        bundle.windowInspector.inspectionResults = [100: .inspected([
            1: standardMeta(title: "Documents")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 100, windowID: 1)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Documents"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Advance 6 hours — the window should be due and close
        bundle.scheduler.advance(by: 6 * 3600)
        await settle()

        // The window was closed. Now simulate it disappearing.
        bundle.windowLister.windows = []
        // Advance to the +2s scan
        bundle.scheduler.advance(by: 3)
        await settle()

        let closures = store.recentClosures(limit: 10)
        #expect(!closures.isEmpty, "Expected at least one closure record")
        if let first = closures.first {
            #expect(first.bundleID == "com.apple.finder")
            #expect(first.windowTitle == "Documents")
            #expect(first.documentURL == documentsURL, "Finder folder URL should be resolved")
            #expect(first.kind == .windowClosed)
        }
        #expect(bundle.finderFolderResolver.resolvedTitles == ["Documents"])
    }

    @Test("35b: Finder close with unresolvable title → nil URL, no crash")
    @MainActor
    func finderWindowCloseUnresolvable() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)
        // No folder URLs configured → resolver returns nil
        store.settings.finderRestoreEnabled = true

        store.addAppRule(bundleID: "com.apple.finder", appName: "Finder", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))

        let finderWindow = observedWindow(pid: 200, windowID: 5, bundleID: "com.apple.finder", appName: "Finder")
        bundle.windowLister.windows = [finderWindow]
        bundle.windowInspector.inspectionResults = [200: .inspected([
            5: standardMeta(title: "Recents")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 200, windowID: 5)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Recents"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        bundle.scheduler.advance(by: 3600)
        await settle()

        bundle.windowLister.windows = []
        bundle.scheduler.advance(by: 3)
        await settle()

        let closures = store.recentClosures(limit: 10)
        #expect(!closures.isEmpty)
        if let first = closures.first {
            #expect(first.documentURL == nil, "Unresolvable Finder window keeps nil URL")
        }
        #expect(bundle.finderFolderResolver.resolvedTitles == ["Recents"])
    }

    @Test("35c: Non-Finder app close → resolver not called")
    @MainActor
    func nonFinderCloseSkipsResolver() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.test.editor", appName: "Editor", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))

        let editorWindow = observedWindow(pid: 300, windowID: 10, bundleID: "com.test.editor", appName: "Editor")
        bundle.windowLister.windows = [editorWindow]
        bundle.windowInspector.inspectionResults = [300: .inspected([
            10: standardMeta(title: "readme.md", documentURL: URL(fileURLWithPath: "/tmp/readme.md"))
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 300, windowID: 10)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "readme.md", documentURL: URL(fileURLWithPath: "/tmp/readme.md")),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        bundle.scheduler.advance(by: 3600)
        await settle()

        bundle.windowLister.windows = []
        bundle.scheduler.advance(by: 3)
        await settle()

        #expect(bundle.finderFolderResolver.resolvedTitles.isEmpty, "Resolver must not be called for non-Finder apps")
    }

    @Test("35d: Finder close with restore disabled → resolver not called")
    @MainActor
    func finderCloseWithRestoreDisabled() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)
        // finderRestoreEnabled defaults to false — do not enable it

        let documentsURL = URL(fileURLWithPath: "/Users/test/Documents", isDirectory: true)
        bundle.finderFolderResolver.folderURLsByTitle = ["Documents": documentsURL]

        store.addAppRule(bundleID: "com.apple.finder", appName: "Finder", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))

        let finderWindow = observedWindow(pid: 400, windowID: 20, bundleID: "com.apple.finder", appName: "Finder")
        bundle.windowLister.windows = [finderWindow]
        bundle.windowInspector.inspectionResults = [400: .inspected([
            20: standardMeta(title: "Documents")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 400, windowID: 20)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Documents"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        bundle.scheduler.advance(by: 3600)
        await settle()

        bundle.windowLister.windows = []
        bundle.scheduler.advance(by: 3)
        await settle()

        let closures = store.recentClosures(limit: 10)
        #expect(!closures.isEmpty)
        if let first = closures.first {
            #expect(first.documentURL == nil, "Finder folder URL must not be resolved when restore is disabled")
        }
        #expect(bundle.finderFolderResolver.resolvedTitles.isEmpty, "Resolver must not be called when restore is disabled")
    }

    // MARK: - Finder restore toggle flow

    @Test("35e: Enable Finder restore — probe granted → setting persisted")
    @MainActor
    func finderRestoreEnableGranted() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.finderFolderResolver.permissionGranted = true

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        #expect(!core.finderRestoreEnabled)
        await core.setFinderRestore(enabled: true)

        #expect(core.finderRestoreEnabled, "Setting must be persisted after granted probe")
        #expect(core.finderAutomationGranted == true)
        #expect(!core.finderProbeInProgress)
        #expect(bundle.finderFolderResolver.probeCount == 1)
    }

    @Test("35f: Enable Finder restore — probe denied → setting stays off")
    @MainActor
    func finderRestoreEnableDenied() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.finderFolderResolver.permissionGranted = false

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        await core.setFinderRestore(enabled: true)

        #expect(!core.finderRestoreEnabled, "Setting must not be persisted when probe is denied")
        #expect(core.finderAutomationGranted == false)
        #expect(!core.finderProbeInProgress)
    }

    @Test("35g: Enable Finder restore — probe inconclusive → setting stays off, no denied state")
    @MainActor
    func finderRestoreEnableInconclusive() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.finderFolderResolver.permissionGranted = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        await core.setFinderRestore(enabled: true)

        #expect(!core.finderRestoreEnabled, "Setting must not be persisted when probe is inconclusive")
        #expect(core.finderAutomationGranted == nil, "Inconclusive probe must not show denied state")
        #expect(!core.finderProbeInProgress)
    }

    @Test("35h: Disable Finder restore → setting off, automation state cleared")
    @MainActor
    func finderRestoreDisable() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.finderFolderResolver.permissionGranted = true

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Enable first
        await core.setFinderRestore(enabled: true)
        #expect(core.finderRestoreEnabled)
        #expect(core.finderAutomationGranted == true)

        // Now disable
        await core.setFinderRestore(enabled: false)
        #expect(!core.finderRestoreEnabled)
        #expect(core.finderAutomationGranted == nil, "Automation state must reset on disable")
    }

    @Test("36: Save dialog keeps window, focus resets deadline")
    @MainActor
    func saveDialogKeepsWindow() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.test.app", appName: "TestApp", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))

        let window = observedWindow(pid: 200, windowID: 10, bundleID: "com.test.app", appName: "TestApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [200: .inspected([
            10: standardMeta(title: "Untitled")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 200, windowID: 10)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Untitled"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Advance 1 hour — due, close sent
        bundle.scheduler.advance(by: 3600)
        await settle()

        // The executor should have run the close and scheduled verification.
        // Advance to +10s verification. Window is still listed (app kept it).
        bundle.scheduler.advance(by: 11)
        await settle()

        let schedules = core.plan.schedules.filter { $0.key == key }
        #expect(schedules.first?.status == .keptOpen, "Window should be kept open after save dialog")

        // The user focuses the window for 6 seconds → resets deadline
        let app = ObservedApp(pid: 200, bundleID: "com.test.app", name: "TestApp", launchDate: nil)
        bundle.workspace.frontmost = app
        bundle.windowInspector.focusedWindowIDs = [200: 10]
        bundle.workspace.send(.appActivated(app))
        await settle()

        // Advance 6 seconds (qualifying focus)
        bundle.scheduler.advance(by: 6)

        // Unfocus
        let other = ObservedApp(pid: 1, bundleID: "com.other.app", name: "Other", launchDate: nil)
        bundle.workspace.frontmost = other
        bundle.windowInspector.focusedWindowIDs = [:]
        bundle.workspace.send(.appActivated(other))
        await settle()

        let updatedSchedules = core.plan.schedules.filter { $0.key == key }
        #expect(updatedSchedules.first?.status == .scheduled, "Window should be scheduled after focus reset")
    }

    @Test("37: Kept element on another Space → unreachable → closes on Space change")
    @MainActor
    func keptElementOtherSpace() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.test.app", appName: "TestApp", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))

        let window = observedWindow(pid: 300, windowID: 20, bundleID: "com.test.app", appName: "TestApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [300: .inspected([
            20: standardMeta(title: "Doc")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 300, windowID: 20)
        // Close is pressed but wasListed = false (other Space)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Doc"),
            wasListed: false
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Advance past deadline
        bundle.scheduler.advance(by: 3600)
        await settle()

        // Advance to +10s verification. wasListed=false → .unreachable
        bundle.scheduler.advance(by: 11)
        await settle()

        let sched1 = core.plan.schedules.filter { $0.key == key }
        #expect(sched1.first?.status == .dueUnreachable, "Should be unreachable after other-Space close")

        // Space change: now the window is reachable
        bundle.windowInspector.inspectionResults = [300: .inspected([
            20: standardMeta(title: "Doc")
        ])]
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Doc"),
            wasListed: true
        )]
        bundle.workspace.send(.activeSpaceChanged)
        await settle()

        // The inspection should have cleared unreachable and replan should close
        let closedCount = bundle.windowCloser.closedKeys.count
        #expect(closedCount >= 2, "Window should be closed again after Space change reveals it")
    }

    @Test("38: QuickTime Always quit after 60s grace")
    @MainActor
    func alwaysQuitAfterGrace() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.apple.QuickTimePlayerX", appName: "QuickTime Player", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .always
        ))

        let window = observedWindow(pid: 400, windowID: 30, bundleID: "com.apple.QuickTimePlayerX", appName: "QuickTime Player")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [400: .inspected([
            30: standardMeta(title: "Movie.mov")
        ])]
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // The user closes the window themselves (disappears from scan)
        bundle.windowLister.windows = []
        // Trigger a scan via the timer. The scan interval is 60s.
        bundle.scheduler.advance(by: 61)
        await settle()

        // The app should now have hadStandardWindow=true and noStandardWindowsSince set.
        // After 60s grace, a quit should fire.
        // The planner sets a wake at noStandardWindowsSince + 60.
        // Advance another 61s to pass the grace period.
        bundle.scheduler.advance(by: 61)
        await settle()

        #expect(bundle.appTerminator.terminatedPids.contains(400), "QuickTime should be quit after 60s with no windows")
    }

    @Test("39: ifClosedBySqueegee quit vs user-closed")
    @MainActor
    func ifClosedBySqueegeeQuit() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.apple.systempreferences", appName: "System Settings", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .ifClosedBySqueegee
        ))

        let window = observedWindow(pid: 500, windowID: 40, bundleID: "com.apple.systempreferences", appName: "System Settings")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [500: .inspected([
            40: standardMeta(title: "General")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 500, windowID: 40)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "General"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Advance past deadline so Squeegee closes the window
        bundle.scheduler.advance(by: 3600)
        await settle()

        // Window disappears (Squeegee closed it)
        bundle.windowLister.windows = []
        bundle.scheduler.advance(by: 3)
        await settle()

        // The app should be quit because WC closed the last window
        // ifClosedBySqueegee quits immediately when present count = 0
        // after quitAfterSqueegeeClose is set
        bundle.scheduler.advance(by: 1)
        await settle()

        #expect(bundle.appTerminator.terminatedPids.contains(500),
                "System Settings should be quit after Squeegee closed its last window")
    }

    @Test("39b: ifClosedBySqueegee — user closes last window → no quit")
    @MainActor
    func ifClosedBySqueegeeUserCloseNoQuit() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.apple.systempreferences", appName: "System Settings", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .ifClosedBySqueegee
        ))

        let window = observedWindow(
            pid: 510, windowID: 41,
            bundleID: "com.apple.systempreferences", appName: "System Settings"
        )
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [510: .inspected([
            41: standardMeta(title: "General")
        ])]
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // The user closes the window before the deadline (disappears without closeSent)
        bundle.windowLister.windows = []
        bundle.scheduler.advance(by: 61)
        await settle()

        // Wait past any quit grace period
        bundle.scheduler.advance(by: 120)
        await settle()

        #expect(!bundle.appTerminator.terminatedPids.contains(510),
                "App should NOT be quit when the user closes the last window")
    }

    @Test("40: Pause one hour blocks closes, resumes after")
    @MainActor
    func pauseBlocksCloses() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.test.app", appName: "TestApp", rule: Rule(
            isEnabled: true, closeAfter: 1800, measureFrom: .lastActive, quitPolicy: .never
        ))

        let window = observedWindow(pid: 600, windowID: 50, bundleID: "com.test.app", appName: "TestApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [600: .inspected([
            50: standardMeta(title: "Test")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 600, windowID: 50)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Test"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        core.pause(.oneHour)
        #expect(core.isPaused)

        // Advance past the window's deadline (30 min) — should NOT close
        bundle.scheduler.advance(by: 1800)
        await settle()

        let sched = core.plan.schedules.filter { $0.key == key }
        #expect(sched.first?.status == .duePaused, "Window should be duePaused while paused")
        #expect(bundle.windowCloser.closedKeys.isEmpty, "No close should happen while paused")

        // Advance past the 1-hour pause
        bundle.scheduler.advance(by: 1801)
        await settle()

        #expect(!core.isPaused, "Pause should have expired")
        #expect(!bundle.windowCloser.closedKeys.isEmpty,
                "Due window should close after pause expires")
    }

    @Test("41: Permission revoked stops actions, granted resumes")
    @MainActor
    func permissionRevokedAndGranted() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.test.app", appName: "TestApp", rule: Rule(
            isEnabled: true, closeAfter: 1800, measureFrom: .lastActive, quitPolicy: .never
        ))

        let window = observedWindow(pid: 700, windowID: 60, bundleID: "com.test.app", appName: "TestApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [700: .inspected([
            60: standardMeta(title: "Test")
        ])]
        bundle.workspace.frontmost = nil
        bundle.permission.trusted = true

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        #expect(core.permission == .granted)

        // Revoke permission
        bundle.permission.trusted = false
        bundle.workspace.send(.ownAppBecameActive)
        await settle()

        #expect(core.permission == .denied)
        #expect(core.menuBarIconState == .permissionMissing)

        // Grant permission back
        bundle.permission.trusted = true
        bundle.windowInspector.inspectionResults = [700: .inspected([
            60: standardMeta(title: "Test")
        ])]
        bundle.workspace.send(.ownAppBecameActive)
        await settle()

        #expect(core.permission == .granted)
        #expect(core.menuBarIconState == .normal)
    }

    @Test("42: Displays sleep stops scan timer, wake restarts")
    @MainActor
    func displaysSleepAndWake() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        bundle.windowLister.windows = []
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        let callsAfterStart = bundle.windowLister.listCallCount

        // Sleep
        bundle.workspace.send(.displaysSlept)
        await settle()

        // Advance past a scan interval — should NOT trigger scans
        let callsBeforeSleep = bundle.windowLister.listCallCount
        bundle.scheduler.advance(by: 120)
        await settle()

        let callsDuringSleep = bundle.windowLister.listCallCount
        #expect(callsDuringSleep == callsBeforeSleep, "No scans should happen during display sleep")

        // Wake
        bundle.workspace.send(.displaysWoke)
        await settle()

        let callsAfterWake = bundle.windowLister.listCallCount
        #expect(callsAfterWake > callsDuringSleep, "A scan should run on wake")
        _ = callsAfterStart // suppress unused warning
    }

    @Test("43: Focus signal from non-frontmost pid is ignored")
    @MainActor
    func focusSignalFromNonFrontmostIgnored() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        let window = observedWindow(pid: 800, windowID: 70, bundleID: "com.test.app", appName: "TestApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [800: .inspected([
            70: standardMeta(title: "Doc")
        ])]
        let app = ObservedApp(pid: 800, bundleID: "com.test.app", name: "TestApp", launchDate: nil)
        bundle.workspace.frontmost = app
        bundle.windowInspector.focusedWindowIDs = [800: 70]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // The frontmost pid is 800. Send a focus signal from pid 999.
        let inspectCountBefore = bundle.windowInspector.inspectCallCount
        bundle.focus.send(FocusSignal(pid: 999, kind: .focusMayHaveChanged, at: epoch.addingTimeInterval(10)))
        await settle()

        #expect(bundle.windowInspector.inspectCallCount == inspectCountBefore,
                "Focus signal from non-frontmost pid should be ignored")
    }

    // Test 44: (removed: perf project — restart restore removed, tracked windows are in memory only)

    @Test("45: Rule edit through store triggers replan")
    @MainActor
    func ruleEditTriggersReplan() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        let window = observedWindow(pid: 1000, windowID: 90, bundleID: "com.test.app", appName: "TestApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [1000: .inspected([
            90: standardMeta(title: "Doc")
        ])]
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        let key = WindowKey(pid: 1000, windowID: 90)
        let sched1 = core.plan.schedules.filter { $0.key == key }
        #expect(sched1.first?.status == .disabled, "Window should be disabled before rule edit")

        // Enable the global rule through the store
        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 1800

        // Give observation tracking time to fire
        await settle(rounds: 20)

        let sched2 = core.plan.schedules.filter { $0.key == key }
        #expect(sched2.first?.status == .scheduled, "Window should be scheduled after global rule is enabled")
    }

    @Test("46: Onboarding — suggestions filter, apply, completeOnboarding")
    @MainActor
    func onboardingSuggestions() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        bundle.installedApps.apps = [
            InstalledApp(bundleID: "com.apple.finder", name: "Finder",
                         url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")),
            InstalledApp(bundleID: "com.apple.Preview", name: "Preview",
                         url: URL(fileURLWithPath: "/System/Applications/Preview.app"))
        ]

        bundle.windowLister.windows = []
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        #expect(core.route == .onboarding)

        let suggestions = await core.suggestions(excludingExistingRules: false)
        #expect(suggestions.count == 2)

        let finderSuggestion = suggestions.filter { $0.entry.bundleID == "com.apple.finder" }
        core.applySuggestions(finderSuggestion)

        let finderRule = store.appRule(bundleID: "com.apple.finder")
        #expect(finderRule != nil)
        #expect(finderRule?.isEnabled == true)

        core.completeOnboarding()
        #expect(store.settings.onboardingComplete)
        #expect(bundle.loginItem.enabled)

        if case .settings = core.route {
            // Route changed to settings
        } else {
            Issue.record("Route should be .settings after completing onboarding")
        }

        let filtered = await core.suggestions(excludingExistingRules: true)
        #expect(filtered.count == 1)
        #expect(filtered.first?.entry.bundleID == "com.apple.Preview")
    }

    @Test("48: pauseMode returns untilTomorrow even when close to 6 AM")
    @MainActor
    func pauseModeUntilTomorrowNear6AM() async throws {
        // 5:59 AM — "until tomorrow" resolves to 6:00 AM, only ~60 s away.
        // Without the in-memory fix, the heuristic would misidentify it as oneHour.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let components = DateComponents(
            calendar: cal, timeZone: cal.timeZone,
            year: 2026, month: 9, day: 30, hour: 5, minute: 59
        )
        let epoch = try #require(cal.date(from: components))

        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)
        bundle.windowLister.windows = []
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn, calendar: cal)
        await core.start()

        core.pause(.untilTomorrow)
        #expect(core.isPaused)

        let menu = core.menuContent()
        // Pause options are inside a "Pause" submenu in the footer section
        let pauseItem = menu.sections.flatMap(\.items).first { $0.title == "Pause" }
        let pauseChildren = try #require(pauseItem?.submenu)
        let tomorrowItem = pauseChildren.first { $0.action == .pauseUntilTomorrow }
        let oneHourItem = pauseChildren.first { $0.action == .pauseOneHour }
        #expect(tomorrowItem?.isChecked == true,
                "Until Tomorrow should be checked when pause(.untilTomorrow) was called")
        #expect(oneHourItem?.isChecked == false,
                "For 1 Hour should NOT be checked")
    }

    @Test("47: Reopen — URL opens file, no URL launches app, quit launches app")
    @MainActor
    func reopenBehavior() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        bundle.windowLister.windows = []
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        let fileURL = URL(fileURLWithPath: "/Users/test/doc.pdf")

        // Reopen with URL
        let closureWithURL = ClosureValue(
            bundleID: "com.apple.Preview", appName: "Preview",
            windowTitle: "doc.pdf", documentURL: fileURL,
            kind: .windowClosed, closedAt: epoch
        )
        try await core.reopen(closureWithURL)
        #expect(bundle.opener.openedURLs.count == 1)
        #expect(bundle.opener.openedURLs.first?.url == fileURL)
        #expect(bundle.opener.openedURLs.first?.bundleID == "com.apple.Preview")

        // Reopen without URL (e.g. Finder)
        let closureNoURL = ClosureValue(
            bundleID: "com.apple.finder", appName: "Finder",
            windowTitle: "Documents", documentURL: nil,
            kind: .windowClosed, closedAt: epoch
        )
        try await core.reopen(closureNoURL)
        #expect(bundle.opener.launchedBundleIDs.contains("com.apple.finder"))

        // Reopen a quit record
        let quitClosure = ClosureValue(
            bundleID: "com.apple.QuickTimePlayerX", appName: "QuickTime Player",
            windowTitle: nil, documentURL: nil,
            kind: .appQuit, closedAt: epoch
        )
        try await core.reopen(quitClosure)
        #expect(bundle.opener.launchedBundleIDs.contains("com.apple.QuickTimePlayerX"))
    }

    @Test("49: Close sent then window gone on scan — menuContent has no closing items")
    @MainActor
    func closeSentWindowGoneClearsClosingFromMenu() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.addAppRule(bundleID: "com.apple.finder", appName: "Finder", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))

        let finderWindow = observedWindow(pid: 100, windowID: 1, bundleID: "com.apple.finder", appName: "Finder")
        bundle.windowLister.windows = [finderWindow]
        bundle.windowInspector.inspectionResults = [100: .inspected([
            1: standardMeta(title: "Documents")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 100, windowID: 1)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Documents"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Advance past the deadline — close action fires
        bundle.scheduler.advance(by: 3600)
        await settle()

        // Before the window disappears, menu should show "closing…"
        let menuBefore = core.menuContent()
        let closingBefore = menuBefore.sections.flatMap(\.items).filter {
            $0.subtitle?.contains("closing") == true
        }
        #expect(!closingBefore.isEmpty, "Menu should show 'closing' right after close sent")

        // Window disappears from the CG list
        bundle.windowLister.windows = []
        // Advance past the +2 s verification scan
        bundle.scheduler.advance(by: 3)
        await settle()

        // Menu must no longer show any "closing…" items
        let menuAfter = core.menuContent()
        let closingAfter = menuAfter.sections.flatMap(\.items).filter {
            $0.subtitle?.contains("closing") == true
        }
        #expect(closingAfter.isEmpty,
                "Menu must not show 'closing' after the window is gone from the CG list")

        // Settings Open Windows list for Finder must also be empty
        let finderSchedules = core.schedules(for: .appRule(bundleID: "com.apple.finder"))
        #expect(finderSchedules.isEmpty,
                "Settings Open Windows should show no Finder windows")
    }

    // MARK: - In-memory RuleSet cache tests (perf Phase 4)

    @Test("50: Edit global rule closeAfter updates deadline")
    @MainActor
    func ruleEditCloseAfterUpdatesDeadline() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        // Enable the global rule with a 2-hour deadline
        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 7200

        let window = observedWindow(pid: 1100, windowID: 101, bundleID: "com.test.app", appName: "TestApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [1100: .inspected([
            101: standardMeta(title: "Doc")
        ])]
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        let key = WindowKey(pid: 1100, windowID: 101)
        let sched1 = core.plan.schedules.filter { $0.key == key }
        #expect(sched1.first?.status == .scheduled, "Window should be scheduled with 2h rule")

        // Change closeAfter to 30 minutes
        store.settings.globalCloseAfterSeconds = 1800
        await settle(rounds: 20)

        let sched2 = core.plan.schedules.filter { $0.key == key }
        #expect(sched2.first?.status == .scheduled, "Window should still be scheduled after edit")
        // The deadline should now be at epoch + 1800, not epoch + 7200
        if let deadline = sched2.first?.deadline {
            let expected = epoch.addingTimeInterval(1800)
            #expect(abs(deadline.timeIntervalSince(expected)) < 1,
                    "Deadline should reflect the new 30-minute closeAfter")
        } else {
            Issue.record("Expected a deadline on the schedule")
        }
    }

    @Test("51: Add app rule shows ruleSource .app")
    @MainActor
    func addAppRuleShowsAppRuleSource() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        // Enable the global rule
        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 7200

        let window = observedWindow(pid: 1200, windowID: 102, bundleID: "com.test.myapp", appName: "MyApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [1200: .inspected([
            102: standardMeta(title: "File")
        ])]
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        let key = WindowKey(pid: 1200, windowID: 102)
        let sched1 = core.plan.schedules.filter { $0.key == key }
        #expect(sched1.first?.ruleSource == .global, "Before app rule, source should be .global")

        // Add an app rule with a 1-hour deadline
        store.addAppRule(bundleID: "com.test.myapp", appName: "MyApp", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))
        store.save()
        await settle(rounds: 20)

        let sched2 = core.plan.schedules.filter { $0.key == key }
        #expect(sched2.first?.ruleSource == .app, "After app rule, source should be .app")
        if let deadline = sched2.first?.deadline {
            let expected = epoch.addingTimeInterval(3600)
            #expect(abs(deadline.timeIntervalSince(expected)) < 1,
                    "Deadline should match the app rule's 1-hour closeAfter")
        }
    }

    @Test("52: Remove app rule falls back to global")
    @MainActor
    func removeAppRuleFallsBackToGlobal() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        // Enable the global rule
        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 7200

        // Add an app rule
        store.addAppRule(bundleID: "com.test.myapp", appName: "MyApp", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))
        store.save()

        let window = observedWindow(pid: 1300, windowID: 103, bundleID: "com.test.myapp", appName: "MyApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [1300: .inspected([
            103: standardMeta(title: "File")
        ])]
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        let key = WindowKey(pid: 1300, windowID: 103)
        let sched1 = core.plan.schedules.filter { $0.key == key }
        #expect(sched1.first?.ruleSource == .app, "With app rule, source should be .app")

        // Remove the app rule
        store.removeAppRule(bundleID: "com.test.myapp")
        store.save()
        await settle(rounds: 20)

        let sched2 = core.plan.schedules.filter { $0.key == key }
        #expect(sched2.first?.ruleSource == .global, "After removing app rule, source should be .global")
    }

    @Test("53: Disable app rule via direct property edit marks schedule disabled")
    @MainActor
    func disableAppRuleMakesScheduleDisabled() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        // Enable the global rule
        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 7200

        // Add an enabled app rule
        store.addAppRule(bundleID: "com.test.myapp", appName: "MyApp", rule: Rule(
            isEnabled: true, closeAfter: 1800, measureFrom: .lastActive, quitPolicy: .never
        ))
        store.save()

        let window = observedWindow(pid: 1400, windowID: 104, bundleID: "com.test.myapp", appName: "MyApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [1400: .inspected([
            104: standardMeta(title: "File")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 1400, windowID: 104)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "File"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Verify it starts as scheduled with the app rule
        let sched1 = core.plan.schedules.filter { $0.key == key }
        #expect(sched1.first?.status == .scheduled, "Window should be scheduled before disabling")

        // Disable the app rule via direct @Model property edit + notifyRuleChanged(),
        // simulating the effect of the SettingsUI onChange(of:) modifier
        let appRule = store.appRule(bundleID: "com.test.myapp")
        appRule?.isEnabled = false
        store.notifyRuleChanged()
        await settle(rounds: 20)

        let sched2 = core.plan.schedules.filter { $0.key == key }
        #expect(sched2.first?.status == .disabled, "Disabled app rule should give .disabled status")

        // Advance well past what would have been the deadline — no close should fire
        bundle.scheduler.advance(by: 3600)
        await settle()

        #expect(bundle.windowCloser.closedKeys.isEmpty,
                "No close action should fire for a disabled app rule")
    }

    @Test("54: Edit app rule closeAfterSeconds via direct property edit updates deadline")
    @MainActor
    func editAppRuleCloseAfterViaPropertyEdit() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 7200

        store.addAppRule(bundleID: "com.test.myapp", appName: "MyApp", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))
        store.save()

        let window = observedWindow(pid: 1500, windowID: 110, bundleID: "com.test.myapp", appName: "MyApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [1500: .inspected([
            110: standardMeta(title: "Doc")
        ])]
        bundle.workspace.frontmost = nil

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        let key = WindowKey(pid: 1500, windowID: 110)
        let sched1 = core.plan.schedules.filter { $0.key == key }
        if let deadline = sched1.first?.deadline {
            let expected = epoch.addingTimeInterval(3600)
            #expect(abs(deadline.timeIntervalSince(expected)) < 1, "Initial deadline should be 1h")
        }

        // Edit closeAfterSeconds via direct property edit + notifyRuleChanged()
        let record = store.appRule(bundleID: "com.test.myapp")
        record?.closeAfterSeconds = 1800
        store.notifyRuleChanged()
        await settle(rounds: 20)

        let sched2 = core.plan.schedules.filter { $0.key == key }
        if let deadline = sched2.first?.deadline {
            let expected = epoch.addingTimeInterval(1800)
            #expect(abs(deadline.timeIntervalSince(expected)) < 1,
                    "Deadline should update to 30min after closeAfterSeconds edit")
        } else {
            Issue.record("Expected a deadline on the schedule")
        }
    }

    @Test("55: Edit app rule measureFromRaw via property edit shifts plan deadline")
    @MainActor
    func editAppRuleMeasureFromViaPropertyEdit() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 7200

        store.addAppRule(bundleID: "com.test.myapp", appName: "MyApp", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))
        store.save()

        let window = observedWindow(pid: 1600, windowID: 120, bundleID: "com.test.myapp", appName: "MyApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [1600: .inspected([
            120: standardMeta(title: "Doc")
        ])]
        // Focus the window so lastActive diverges from firstSeen (opened)
        let app = ObservedApp(pid: 1600, bundleID: "com.test.myapp", name: "MyApp", launchDate: nil)
        bundle.workspace.frontmost = app
        bundle.windowInspector.focusedWindowIDs = [1600: 120]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Advance 100s with focus to build qualifying focus time
        bundle.scheduler.advance(by: 100)
        await settle()

        // Unfocus — lastActive is now ~epoch+100, firstSeen stays at epoch
        let other = ObservedApp(pid: 1, bundleID: "com.other.app", name: "Other", launchDate: nil)
        bundle.workspace.frontmost = other
        bundle.windowInspector.focusedWindowIDs = [:]
        bundle.workspace.send(.appActivated(other))
        await settle()

        let key = WindowKey(pid: 1600, windowID: 120)
        let sched1 = core.plan.schedules.filter { $0.key == key }
        let lastActiveDeadline = sched1.first?.deadline
        // With measureFrom: .lastActive, deadline = ~epoch+100+3600
        #expect(lastActiveDeadline != nil)

        // Switch measureFrom to .opened (simulating the SettingsUI onChange effect)
        let record = store.appRule(bundleID: "com.test.myapp")
        record?.measureFromRaw = "opened"
        store.notifyRuleChanged()
        await settle(rounds: 20)

        let sched2 = core.plan.schedules.filter { $0.key == key }
        let openedDeadline = sched2.first?.deadline
        // With measureFrom: .opened, deadline = epoch+3600 (earlier than lastActive-based)
        #expect(openedDeadline != nil)
        if let opened = openedDeadline, let lastActive = lastActiveDeadline {
            #expect(opened < lastActive,
                    "Opened-based deadline should be earlier than lastActive-based deadline")
            let expectedOpened = epoch.addingTimeInterval(3600)
            #expect(abs(opened.timeIntervalSince(expectedOpened)) < 1,
                    "Opened-based deadline should be firstSeen + closeAfter")
        }
    }

    @Test("56: Edit app rule quitPolicyRaw via property edit enables quit in plan")
    @MainActor
    func editAppRuleQuitPolicyViaPropertyEdit() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 7200

        // Start with quitPolicy: .never
        store.addAppRule(bundleID: "com.test.myapp", appName: "MyApp", rule: Rule(
            isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
        ))
        store.save()

        let window = observedWindow(pid: 1700, windowID: 130, bundleID: "com.test.myapp", appName: "MyApp")
        bundle.windowLister.windows = [window]
        bundle.windowInspector.inspectionResults = [1700: .inspected([
            130: standardMeta(title: "Doc")
        ])]
        bundle.workspace.frontmost = nil

        let key = WindowKey(pid: 1700, windowID: 130)
        bundle.windowCloser.closeResults = [key: .pressed(
            latest: standardMeta(title: "Doc"),
            wasListed: true
        )]

        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()

        // Change quitPolicy to .always (simulating the SettingsUI onChange effect)
        let record = store.appRule(bundleID: "com.test.myapp")
        record?.quitPolicyRaw = "always"
        store.notifyRuleChanged()
        await settle(rounds: 20)

        // Advance past deadline so Squeegee closes the window
        bundle.scheduler.advance(by: 3600)
        await settle()

        // Window disappears from CG list (closed successfully)
        bundle.windowLister.windows = []
        bundle.scheduler.advance(by: 3)
        await settle()

        // With quitPolicy .always, after 60s grace the app should be quit.
        // If the cached ruleSet were stale (.never), no quit would happen.
        bundle.scheduler.advance(by: 61)
        await settle()

        #expect(bundle.appTerminator.terminatedPids.contains(1700),
                "App should be quit after rule changed to .always via cached ruleSet")
    }
}

// swiftlint:enable type_body_length
