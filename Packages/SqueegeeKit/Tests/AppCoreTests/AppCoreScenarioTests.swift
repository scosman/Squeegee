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
    @Test("35: Finder window close → history record with title, no URL")
    @MainActor
    func finderWindowCloseAndHistory() async throws {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try makeStore()
        let bundle = FakePortsBundle(now: epoch)

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
            #expect(first.documentURL == nil, "Finder exposes no document URL")
            #expect(first.kind == .windowClosed)
        }
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
}

// swiftlint:enable type_body_length
