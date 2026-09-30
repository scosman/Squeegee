import Foundation
import Testing
@testable import Engine

// MARK: - Test helpers

private let t0 = Date(timeIntervalSinceReferenceDate: 700_000_000) // swiftlint:disable:this identifier_name

private func date(_ offset: TimeInterval) -> Date {
    t0.addingTimeInterval(offset)
}

private func key(_ pid: Int32 = 1, _ windowID: UInt32 = 100) -> WindowKey {
    WindowKey(pid: pid, windowID: windowID)
}

private func makeTrackedWindow(
    pid: Int32 = 1,
    windowID: UInt32 = 100,
    bundleID: String = "com.test.app",
    appName: String = "TestApp",
    firstSeen: Date = t0,
    lastActive: Date? = nil,
    metadata: WindowMetadata? = WindowMetadata(isStandard: true, title: "Test"),
    closeState: CloseState = .none
) -> TrackedWindow {
    TrackedWindow(
        key: key(pid, windowID),
        bundleID: bundleID,
        appName: appName,
        firstSeen: firstSeen,
        lastActive: lastActive,
        metadata: metadata,
        closeState: closeState
    )
}

private func makeTrackedApp(
    pid: Int32 = 1,
    bundleID: String = "com.test.app",
    appName: String = "TestApp",
    launchDate: Date? = nil,
    hadStandardWindow: Bool = true,
    noStandardWindowsSince: Date? = nil,
    quitAfterWindowCleanerClose: Bool = false,
    quitState: QuitState = .none
) -> TrackedApp {
    TrackedApp(
        pid: pid,
        bundleID: bundleID,
        appName: appName,
        launchDate: launchDate,
        hadStandardWindow: hadStandardWindow,
        noStandardWindowsSince: noStandardWindowsSince,
        quitAfterWindowCleanerClose: quitAfterWindowCleanerClose,
        quitState: quitState
    )
}

private func makeInput(
    state: TrackerState,
    ruleSet: RuleSet = RuleSet(global: .globalDefault),
    now: Date = t0,
    isPaused: Bool = false,
    pausedUntil: Date? = nil,
    hasPermission: Bool = true
) -> PlanInput {
    PlanInput(
        ruleSet: ruleSet,
        state: state,
        now: now,
        isPaused: isPaused,
        pausedUntil: pausedUntil,
        hasPermission: hasPermission
    )
}

// MARK: - Test 19: Rule disabled

@Test func ruleDisabled_statusDisabled_noAction() {
    var state = TrackerState()
    state.windows[key()] = makeTrackedWindow()
    state.apps[1] = makeTrackedApp()

    let ruleSet = RuleSet(global: Rule(
        isEnabled: false, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet))

    #expect(plan.schedules.count == 1)
    #expect(plan.schedules[0].status == .disabled)
    #expect(plan.schedules[0].deadline == nil)
    #expect(plan.actions.isEmpty)
}

// MARK: - Test 20: Global rule applies, app rule overrides

@Test func globalRuleApplies_appRuleOverrides() {
    var state = TrackerState()
    state.windows[key(1, 100)] = makeTrackedWindow(pid: 1, windowID: 100, bundleID: "com.test.global")
    state.apps[1] = makeTrackedApp(pid: 1, bundleID: "com.test.global")

    state.windows[key(2, 200)] = makeTrackedWindow(
        pid: 2, windowID: 200, bundleID: "com.test.specific",
        appName: "Specific", firstSeen: t0
    )
    state.apps[2] = makeTrackedApp(pid: 2, bundleID: "com.test.specific", appName: "Specific")

    let globalRule = Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never)
    // App rule: disabled. Should override global.
    let appRule = Rule(isEnabled: false, closeAfter: 7200, measureFrom: .lastActive, quitPolicy: .never)

    let ruleSet = RuleSet(global: globalRule, appRules: ["com.test.specific": appRule])

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet))

    let globalSchedule = plan.schedules.first { $0.bundleID == "com.test.global" }
    let appSchedule = plan.schedules.first { $0.bundleID == "com.test.specific" }

    #expect(globalSchedule?.ruleSource == .global)
    #expect(globalSchedule?.status != .disabled)
    #expect(appSchedule?.ruleSource == .app)
    #expect(appSchedule?.status == .disabled)
    #expect(plan.actions.isEmpty) // specific is disabled, global not due yet
}

// MARK: - Test 21: Opened deadline vs lastActive deadline

@Test func openedDeadline_lastActiveDeadline() {
    let firstSeen = t0
    let lastActiveTime = date(1000)
    let closeAfter: TimeInterval = 3600

    // Measure from opened
    var state1 = TrackerState()
    state1.windows[key()] = makeTrackedWindow(firstSeen: firstSeen, lastActive: lastActiveTime)
    state1.apps[1] = makeTrackedApp()

    let openedRuleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .opened, quitPolicy: .never
    ))
    let plan1 = Planner.plan(makeInput(state: state1, ruleSet: openedRuleSet))
    #expect(plan1.schedules[0].deadline == firstSeen.addingTimeInterval(closeAfter))

    // Measure from lastActive
    var state2 = TrackerState()
    state2.windows[key()] = makeTrackedWindow(firstSeen: firstSeen, lastActive: lastActiveTime)
    state2.apps[1] = makeTrackedApp()

    let lastActiveRuleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))
    let plan2 = Planner.plan(makeInput(state: state2, ruleSet: lastActiveRuleSet))
    #expect(plan2.schedules[0].deadline == lastActiveTime.addingTimeInterval(closeAfter))

    // lastActive nil -> falls back to firstSeen
    var state3 = TrackerState()
    state3.windows[key()] = makeTrackedWindow(firstSeen: firstSeen, lastActive: nil)
    state3.apps[1] = makeTrackedApp()

    let plan3 = Planner.plan(makeInput(state: state3, ruleSet: lastActiveRuleSet))
    #expect(plan3.schedules[0].deadline == firstSeen.addingTimeInterval(closeAfter))
}

// MARK: - Test 22: Focused window with qualifying session -> deadline moves with now

@Test func focusedWindowQualifyingSession_deadlineMovesWithNow() {
    let closeAfter: TimeInterval = 3600
    let now = date(10000)

    var state = TrackerState()
    state.windows[key()] = makeTrackedWindow(firstSeen: t0, lastActive: date(100))
    state.apps[1] = makeTrackedApp()
    state.focusedKey = key()
    // Session started 10 s before now -> qualifies (>= 5 s)
    state.session = FocusSession(key: key(), start: date(10000 - 10))

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet, now: now))

    // Effective lastActive = now, so deadline = now + closeAfter, which is in the future
    #expect(plan.schedules[0].deadline == now.addingTimeInterval(closeAfter))
    #expect(plan.schedules[0].status == .scheduled)
    #expect(plan.actions.isEmpty)
}

// MARK: - Test 23: Due focused window with short session -> dueInUse, no action

@Test func dueFocusedWindowShortSession_dueInUse_noAction() {
    let closeAfter: TimeInterval = 100
    let now = date(10000)

    var state = TrackerState()
    state.windows[key()] = makeTrackedWindow(firstSeen: t0, lastActive: date(100))
    state.apps[1] = makeTrackedApp()
    state.focusedKey = key()
    // Session under 5 s -> does not qualify -> effective lastActive stays at date(100)
    state.session = FocusSession(key: key(), start: date(10000 - 2))

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet, now: now))

    // deadline = date(100) + 100 = date(200), which is < now (10000)
    #expect(plan.schedules[0].status == .dueInUse)
    #expect(plan.actions.isEmpty)
}

// MARK: - Test 24: Due + paused -> duePaused, no action, pause end in nextWakeAt

@Test func duePaused_statusDuePaused_noAction_pauseEndInWake() {
    let closeAfter: TimeInterval = 100
    let now = date(10000)
    let pauseEnd = date(15000)

    var state = TrackerState()
    state.windows[key()] = makeTrackedWindow(firstSeen: t0, lastActive: date(100))
    state.apps[1] = makeTrackedApp()

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(
        state: state, ruleSet: ruleSet, now: now,
        isPaused: true, pausedUntil: pauseEnd
    ))

    #expect(plan.schedules[0].status == .duePaused)
    #expect(plan.actions.isEmpty)
    #expect(plan.nextWakeAt == pauseEnd)
}

// MARK: - Test 25: Due + no permission -> no action

@Test func dueNoPermission_noAction() {
    let closeAfter: TimeInterval = 100
    let now = date(10000)

    var state = TrackerState()
    state.windows[key()] = makeTrackedWindow(firstSeen: t0, lastActive: date(100))
    state.apps[1] = makeTrackedApp()

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(
        state: state, ruleSet: ruleSet, now: now, hasPermission: false
    ))

    #expect(plan.schedules[0].status == .duePaused)
    #expect(plan.actions.isEmpty)
}

// MARK: - Test 26: Due + unreachable -> dueUnreachable, no action

@Test func dueUnreachable_statusDueUnreachable_noAction() {
    let closeAfter: TimeInterval = 100
    let now = date(10000)

    var state = TrackerState()
    state.windows[key()] = makeTrackedWindow(
        firstSeen: t0, lastActive: date(100),
        closeState: .unreachable(since: date(5000))
    )
    state.apps[1] = makeTrackedApp()

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet, now: now))

    #expect(plan.schedules[0].status == .dueUnreachable)
    #expect(plan.actions.isEmpty)
}

// MARK: - Test 27: Due + closeState .none -> closeWindow action

@Test func dueCloseStateNone_closeWindowAction() {
    let closeAfter: TimeInterval = 100
    let now = date(10000)

    var state = TrackerState()
    state.windows[key()] = makeTrackedWindow(firstSeen: t0, lastActive: date(100))
    state.apps[1] = makeTrackedApp()

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet, now: now))

    #expect(plan.schedules[0].status == .closing)
    #expect(plan.actions.contains(.closeWindow(key())))
}

// MARK: - Test 28: closeState .sent -> closing, .declined -> keptOpen

@Test func closeStateSent_closing_declined_keptOpen() {
    let closeAfter: TimeInterval = 100
    let now = date(10000)

    // .sent -> .closing
    var state1 = TrackerState()
    state1.windows[key()] = makeTrackedWindow(
        firstSeen: t0, lastActive: date(100),
        closeState: .sent(at: date(5000), wasListed: true)
    )
    state1.apps[1] = makeTrackedApp()

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan1 = Planner.plan(makeInput(state: state1, ruleSet: ruleSet, now: now))
    #expect(plan1.schedules[0].status == .closing)
    #expect(plan1.actions.isEmpty) // no duplicate action

    // .declined -> .keptOpen
    var state2 = TrackerState()
    state2.windows[key()] = makeTrackedWindow(
        firstSeen: t0, lastActive: date(100),
        closeState: .declined(at: date(5000))
    )
    state2.apps[1] = makeTrackedApp()

    let plan2 = Planner.plan(makeInput(state: state2, ruleSet: ruleSet, now: now))
    #expect(plan2.schedules[0].status == .keptOpen)
    #expect(plan2.actions.isEmpty)
}

// MARK: - Test 29: Non-standard or unknown metadata -> no schedule

@Test func nonStandardOrUnknownMetadata_noSchedule() {
    var state = TrackerState()

    // Non-standard window
    state.windows[key(1, 100)] = makeTrackedWindow(
        pid: 1, windowID: 100,
        metadata: WindowMetadata(isStandard: false, title: "Panel")
    )
    // Unknown metadata window
    state.windows[key(1, 200)] = makeTrackedWindow(
        pid: 1, windowID: 200, metadata: nil
    )
    state.apps[1] = makeTrackedApp()

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet))
    #expect(plan.schedules.isEmpty)
    #expect(plan.actions.isEmpty)
}

// MARK: - Test 30: Always quit

@Test func alwaysQuit_noWindowsSince60s_quitAction_guards() {
    let closeAfter: TimeInterval = 3600
    let bundleID = "com.test.qt"

    /// Base setup: app with hadStandardWindow = true, no windows since s
    func makeQuitState(
        sinceOffset: TimeInterval,
        nowOffset: TimeInterval,
        frontmostPID: Int32? = nil,
        ruleSource: ResolvedRule.Source = .app,
        quitState: QuitState = .none,
        hadStandardWindow: Bool = true,
        isFinder: Bool = false
    ) -> Plan {
        var state = TrackerState()
        let bid = isFinder ? "com.apple.finder" : bundleID
        state.apps[2] = TrackedApp(
            pid: 2, bundleID: bid, appName: "QT", launchDate: nil,
            hadStandardWindow: hadStandardWindow,
            noStandardWindowsSince: date(sinceOffset),
            quitAfterWindowCleanerClose: false,
            quitState: quitState
        )
        state.frontmostPID = frontmostPID

        var appRules: [String: Rule] = [:]
        if ruleSource == .app {
            appRules[bid] = Rule(
                isEnabled: true, closeAfter: closeAfter,
                measureFrom: .lastActive, quitPolicy: .always
            )
        }
        let globalRule = ruleSource == .global
            ? Rule(isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .always)
            : .globalDefault
        let ruleSet = RuleSet(global: globalRule, appRules: appRules)

        return Planner.plan(makeInput(state: state, ruleSet: ruleSet, now: date(nowOffset)))
    }

    // At s+59, no action, wake at s+60
    let plan59 = makeQuitState(sinceOffset: 0, nowOffset: 59)
    #expect(!plan59.actions.contains(.quitApp(pid: 2)))
    #expect(plan59.nextWakeAt == date(60))

    // At s+60, quit action
    let plan60 = makeQuitState(sinceOffset: 0, nowOffset: 60)
    #expect(plan60.actions.contains(.quitApp(pid: 2)))

    // Not while frontmost
    let planFrontmost = makeQuitState(sinceOffset: 0, nowOffset: 60, frontmostPID: 2)
    #expect(!planFrontmost.actions.contains(.quitApp(pid: 2)))

    // Not for global-rule app (source must be .app)
    let planGlobal = makeQuitState(sinceOffset: 0, nowOffset: 60, ruleSource: .global)
    #expect(!planGlobal.actions.contains(.quitApp(pid: 2)))

    // Not for Finder
    let planFinder = makeQuitState(sinceOffset: 0, nowOffset: 60, isFinder: true)
    #expect(!planFinder.actions.contains(.quitApp(pid: 2)))

    // Not if quitState != .none
    let planDeclined = makeQuitState(sinceOffset: 0, nowOffset: 60, quitState: .declined)
    #expect(!planDeclined.actions.contains(.quitApp(pid: 2)))

    // Not if !hadStandardWindow
    let planNoStd = makeQuitState(sinceOffset: 0, nowOffset: 60, hadStandardWindow: false)
    #expect(!planNoStd.actions.contains(.quitApp(pid: 2)))
}

// MARK: - Test 31: ifClosedByWindowCleaner quit

@Test func ifClosedByWindowCleaner_quitAfterFlagAndEmpty() {
    let bundleID = "com.test.qt"

    var state = TrackerState()
    state.apps[2] = TrackedApp(
        pid: 2, bundleID: bundleID, appName: "QT",
        hadStandardWindow: true,
        quitAfterWindowCleanerClose: true,
        quitState: .none
    )

    let ruleSet = RuleSet(global: .globalDefault, appRules: [
        bundleID: Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive,
                       quitPolicy: .ifClosedByWindowCleaner)
    ])

    // No present windows (empty app) + flag set -> quit
    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet))
    #expect(plan.actions.contains(.quitApp(pid: 2)))

    // Flag not set -> no quit
    state.apps[2]?.quitAfterWindowCleanerClose = false
    let plan2 = Planner.plan(makeInput(state: state, ruleSet: ruleSet))
    #expect(!plan2.actions.contains(.quitApp(pid: 2)))
}

// MARK: - Test 32: nextWakeAt = earliest future deadline

@Test func nextWakeAt_earliestFutureDeadline() {
    let closeAfter: TimeInterval = 3600
    let now = t0

    var state = TrackerState()
    // Window 1: deadline at t0 + 100 + 3600
    state.windows[key(1, 100)] = makeTrackedWindow(
        pid: 1, windowID: 100, bundleID: "com.test.a", appName: "A",
        firstSeen: date(100), lastActive: date(100)
    )
    // Window 2: deadline at t0 + 200 + 3600
    state.windows[key(1, 200)] = makeTrackedWindow(
        pid: 1, windowID: 200, bundleID: "com.test.a", appName: "A",
        firstSeen: date(200), lastActive: date(200)
    )
    state.apps[1] = makeTrackedApp(bundleID: "com.test.a", appName: "A")

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet, now: now))

    #expect(plan.nextWakeAt == date(100 + closeAfter))
}

// MARK: - Test 33: Schedule sort order

@Test func scheduleSortOrder() {
    var state = TrackerState()

    // Three windows with different deadlines
    state.windows[key(1, 100)] = makeTrackedWindow(
        pid: 1, windowID: 100, bundleID: "com.test.b", appName: "Bravo",
        firstSeen: date(200), lastActive: date(200),
        metadata: WindowMetadata(isStandard: true, title: "Z")
    )
    state.windows[key(1, 200)] = makeTrackedWindow(
        pid: 1, windowID: 200, bundleID: "com.test.a", appName: "Alpha",
        firstSeen: date(100), lastActive: date(100),
        metadata: WindowMetadata(isStandard: true, title: "A")
    )
    state.windows[key(2, 300)] = makeTrackedWindow(
        pid: 2, windowID: 300, bundleID: "com.test.a", appName: "Alpha",
        firstSeen: date(100), lastActive: date(100),
        metadata: WindowMetadata(isStandard: true, title: "B")
    )
    state.apps[1] = makeTrackedApp(bundleID: "com.test.b", appName: "Bravo")
    state.apps[2] = makeTrackedApp(pid: 2, bundleID: "com.test.a", appName: "Alpha")

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never
    ))

    let plan = Planner.plan(makeInput(state: state, ruleSet: ruleSet))

    // Sorted by deadline ascending, then appName, then title
    // Windows 200, 300: deadline = date(100+3600) = same; Alpha A, Alpha B
    // Window 100: deadline = date(200+3600) later
    #expect(plan.schedules.count == 3)
    #expect(plan.schedules[0].key == key(1, 200)) // Alpha A
    #expect(plan.schedules[1].key == key(2, 300)) // Alpha B
    #expect(plan.schedules[2].key == key(1, 100)) // Bravo Z
}

// MARK: - Test 34: dryRun

@Test func dryRun_ignoresPausePermission_draftRuleChanges() {
    let closeAfter: TimeInterval = 100
    let now = date(10000)

    var state = TrackerState()
    state.windows[key(1, 100)] = makeTrackedWindow(
        pid: 1, windowID: 100, bundleID: "com.test.a", appName: "A",
        firstSeen: t0, lastActive: date(100)
    )
    state.windows[key(2, 200)] = makeTrackedWindow(
        pid: 2, windowID: 200, bundleID: "com.test.b", appName: "B",
        firstSeen: t0, lastActive: date(100)
    )
    state.apps[1] = makeTrackedApp(bundleID: "com.test.a", appName: "A")
    state.apps[2] = makeTrackedApp(pid: 2, bundleID: "com.test.b", appName: "B")

    let ruleSet = RuleSet(global: Rule(
        isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never
    ))

    // dryRun ignores pause and permission
    let result = Planner.dryRun(ruleSet: ruleSet, state: state, now: now)
    #expect(result.windowsToClose.count == 2) // Both due

    // A draft that turns off a rule produces no closes for that app
    let draftRuleSet = RuleSet(
        global: Rule(isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never),
        appRules: ["com.test.a": Rule(isEnabled: false, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never)]
    )
    let result2 = Planner.dryRun(ruleSet: draftRuleSet, state: state, now: now)
    #expect(result2.windowsToClose.count == 1)
    #expect(result2.windowsToClose[0].bundleID == "com.test.b")

    // A draft that removes an "off" app rule while global is on -> lists that app's windows
    // Setup: app A has an "off" app rule, global is on
    var state2 = TrackerState()
    state2.windows[key(1, 100)] = makeTrackedWindow(
        pid: 1, windowID: 100, bundleID: "com.test.a", appName: "A",
        firstSeen: t0, lastActive: date(100)
    )
    state2.apps[1] = makeTrackedApp(bundleID: "com.test.a", appName: "A")

    // With the app rule off
    let ruleSetOff = RuleSet(
        global: Rule(isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never),
        appRules: ["com.test.a": Rule(isEnabled: false, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never)]
    )
    let resultOff = Planner.dryRun(ruleSet: ruleSetOff, state: state2, now: now)
    #expect(resultOff.windowsToClose.isEmpty)

    // Without the app rule (removed from draft) -> global rule applies -> due
    let ruleSetRemoved = RuleSet(
        global: Rule(isEnabled: true, closeAfter: closeAfter, measureFrom: .lastActive, quitPolicy: .never)
    )
    let resultRemoved = Planner.dryRun(ruleSet: ruleSetRemoved, state: state2, now: now)
    #expect(resultRemoved.windowsToClose.count == 1)
}
