import Engine
import Foundation
import OSLog
import Persistence
import Presentation

private let logger = Logger(subsystem: "net.scosman.squeegee", category: "AppCore")

// MARK: - Public types

/// Which screen/view the app is showing.
public enum Route: Equatable, Sendable {
    case onboarding
    case settings(SettingsSelection)
}

/// What is selected in the Settings sidebar.
public enum SettingsSelection: Hashable, Sendable {
    case general
    case globalRule
    case appRule(bundleID: String)
}

/// Whether Accessibility permission is granted.
public enum PermissionState: Sendable, Equatable {
    case granted
    case denied
}

/// Options for pausing all closures.
public enum PauseOption: Sendable, CaseIterable {
    case oneHour
    case untilTomorrow
    case untilResumed
}

/// The state of the menu bar icon.
public enum MenuBarIconState: Sendable, Equatable {
    case normal
    case paused
    case permissionMissing
}

// MARK: - AppCore

/// The central orchestrator. Wires the engine (tracker, planner), persistence
/// (Store), and presentation (MenuContentBuilder) together through injected
/// port protocols. All access is on the main actor.
@MainActor
@Observable
public final class AppCore {
    // MARK: - Published state

    public private(set) var route: Route
    public private(set) var permission: PermissionState
    public private(set) var plan: Plan

    // MARK: - Dependencies

    public let store: Store
    private let ports: AppCorePorts
    private let catalog: SuggestionCatalog
    private let calendar: Calendar

    // MARK: - Callback

    /// Set by the AppDelegate to show the main window.
    public var showMainWindow: (@MainActor () -> Void)?

    // MARK: - Internal state

    private var ruleSet: RuleSet
    private var trackerState = TrackerState()
    private var scanTimer: (any Engine.Cancellable)?
    private var deadlineTimer: (any Engine.Cancellable)?
    private var eventTasks: [Task<Void, Never>] = []

    /// Tracks pids with an inspection in progress. At most one at a time per pid.
    private var inspectionsInProgress: Set<Int32> = []
    /// Pids that need re-inspection after the current one completes.
    private var inspectionsPending: Set<Int32> = []
    /// Last inspection time per pid (to throttle needsInspection output).
    private var lastInspectionTime: [Int32: Date] = [:]

    /// Remembers the most recent pause option chosen in this session,
    /// so `currentPauseMode()` can return the exact option without a
    /// time-difference heuristic. Cleared on resume or relaunch.
    private var lastPauseOption: PauseOption?

    /// Actions currently being executed.
    private var inFlightCloses: Set<WindowKey> = []
    private var inFlightQuits: Set<Int32> = []

    /// Serial executor queue — one action at a time.
    private var executorTask: Task<Void, Never>?
    private var executorQueue: [PlannedAction] = []

    /// Retained handles for one-shot verification timers. Without these
    /// the `DispatchSourceCancellable` is released immediately and GCD
    /// *may* drop the source on some OS versions before it fires.
    private var verificationTimers: [any Engine.Cancellable] = []

    // MARK: - Constants

    private static let scanInterval: TimeInterval = 60
    private static let scanTolerance: TimeInterval = 6
    private static let deadlineTolerance: TimeInterval = 5
    private static let closeVerificationScanDelay: TimeInterval = 2
    private static let inspectionThrottleInterval: TimeInterval = 10

    // MARK: - Init

    public init(
        store: Store,
        ports: AppCorePorts,
        catalog: SuggestionCatalog = .builtIn,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.ports = ports
        self.catalog = catalog
        self.calendar = calendar
        ruleSet = store.ruleSet()
        route = .onboarding
        permission = .denied
        plan = .empty
    }

    /// Convenience for the app target composition root.
    public static func live(store: Store, ports: AppCorePorts) -> AppCore {
        AppCore(store: store, ports: ports)
    }

    // MARK: - Start

    /// Initializes the event pump. Call once after construction.
    public func start() async {
        logger.info("AppCore.start() beginning")
        // 1. Check permission
        permission = ports.permission.isTrusted() ? .granted : .denied
        let permState = permission
        logger.info("Permission state: \(String(describing: permState), privacy: .public)")

        // 2. Set initial route
        let restoredSelection = restoreSettingsSelection()
        route = store.settings.onboardingComplete
            ? .settings(restoredSelection)
            : .onboarding

        // 3. Start event stream tasks
        startEventStreams()

        // 4. Initial sync
        await scan()
        await inspectAllPids()
        await syncFocus()
        if !ports.workspace.areDisplaysAsleep() {
            startScanTimer()
        }

        // 5. Start rule observation and plan
        observeRules()
        replan()
        let currentRoute = route
        logger.info("AppCore.start() complete, route=\(String(describing: currentRoute), privacy: .public)")
    }

    // MARK: - Pause

    public var isPaused: Bool {
        let settings = store.settings
        if settings.pauseModeRaw == "untilResumed" {
            return true
        }
        if settings.pauseModeRaw == "untilDate",
           let until = settings.pausedUntil,
           ports.scheduler.now() < until
        {
            return true
        }
        return false
    }

    public var pausedUntil: Date? {
        guard store.settings.pauseModeRaw == "untilDate" else { return nil }
        return store.settings.pausedUntil
    }

    public func pause(_ option: PauseOption) {
        lastPauseOption = option
        let now = ports.scheduler.now()
        switch option {
        case .oneHour:
            store.settings.pauseModeRaw = "untilDate"
            store.settings.pausedUntil = now.addingTimeInterval(3600)
        case .untilTomorrow:
            store.settings.pauseModeRaw = "untilDate"
            store.settings.pausedUntil = calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 6),
                matchingPolicy: .nextTime
            )
        case .untilResumed:
            store.settings.pauseModeRaw = "untilResumed"
            store.settings.pausedUntil = nil
        }
        store.save()
        replan()
    }

    public func resume() {
        lastPauseOption = nil
        store.settings.pauseModeRaw = nil
        store.settings.pausedUntil = nil
        store.save()
        replan()
    }

    // MARK: - Permission

    public var menuBarIconState: MenuBarIconState {
        if permission == .denied { return .permissionMissing }
        if isPaused { return .paused }
        return .normal
    }

    public func requestAccessibility() {
        ports.permission.requestPrompt()
    }

    public func openAccessibilitySettings() {
        ports.permission.openSystemSettings()
    }

    // MARK: - Finder restore

    /// Whether Finder window restore is enabled by the user.
    public var finderRestoreEnabled: Bool {
        store.settings.finderRestoreEnabled ?? false
    }

    /// Automation permission state for Finder.
    /// `true` = granted, `false` = denied, `nil` = unknown/not probed.
    public private(set) var finderAutomationGranted: Bool?

    /// True while the Automation permission probe is in progress.
    public private(set) var finderProbeInProgress = false

    /// Enables or disables Finder window restore. When enabling, probes the
    /// Automation permission first — `finderRestoreEnabled` is only persisted
    /// as true if the probe succeeds. If the probe returns false (denied),
    /// the setting stays off and `finderAutomationGranted` is set to false
    /// so the UI can show the denied state. If the probe returns nil
    /// (inconclusive, e.g. Finder not running), the setting stays off
    /// and `finderAutomationGranted` remains nil (no denied row shown).
    public func setFinderRestore(enabled: Bool) async {
        if enabled {
            finderProbeInProgress = true
            let result = await ports.finderFolderResolver.probePermission()
            finderProbeInProgress = false
            finderAutomationGranted = result
            if result == true {
                store.settings.finderRestoreEnabled = true
                store.save()
            }
        } else {
            store.settings.finderRestoreEnabled = false
            store.save()
            finderAutomationGranted = nil
        }
    }

    /// Opens System Settings at Privacy & Security > Automation.
    public func openAutomationSettings() {
        ports.finderFolderResolver.openAutomationSettings()
    }

    // MARK: - Login item

    public var launchAtLogin: Bool {
        ports.loginItem.isEnabled()
    }

    public func setLaunchAtLogin(_ enabled: Bool) throws {
        try ports.loginItem.setEnabled(enabled)
    }

    // MARK: - Navigation

    /// Opens Settings at the given selection and shows the main window.
    public func open(_ selection: SettingsSelection) {
        guard store.settings.onboardingComplete else {
            logger.info("open(\(String(describing: selection), privacy: .public)) ignored — onboarding not complete")
            return
        }
        let callbackIsSet = showMainWindow != nil
        logger.info("open(\(String(describing: selection), privacy: .public)), showMainWindow callback set: \(callbackIsSet)")
        route = .settings(selection)
        store.settings.lastSettingsSelection = selectionString(selection)
        showMainWindow?()
    }

    // MARK: - Schedules for the Open Windows list

    public func schedules(for selection: SettingsSelection) -> [WindowSchedule] {
        switch selection {
        case let .appRule(bundleID):
            plan.schedules.filter { $0.bundleID == bundleID }
        case .globalRule:
            plan.schedules.filter { $0.ruleSource == .global }
        case .general:
            []
        }
    }

    // MARK: - Dry run

    public func dryRun(_ ruleSet: RuleSet) -> DryRunResult {
        Planner.dryRun(ruleSet: ruleSet, state: trackerState, now: ports.scheduler.now())
    }

    // MARK: - Closure history

    public func recentClosures(limit: Int) -> [ClosureValue] {
        store.recentClosures(limit: limit)
    }

    // MARK: - Reopen

    public func reopen(_ closure: ClosureValue) async throws {
        if closure.kind == .appQuit {
            try await ports.opener.launch(bundleID: closure.bundleID)
            return
        }
        if let url = closure.documentURL {
            try await ports.opener.open(documentURL: url, withBundleID: closure.bundleID)
        } else {
            try await ports.opener.launch(bundleID: closure.bundleID)
        }
    }

    // MARK: - Menu content

    public func menuContent() -> MenuContent {
        let now = ports.scheduler.now()
        let activeStatuses: Set<ScheduleStatus> = [.scheduled, .dueInUse, .duePaused, .dueUnreachable, .closing]
        let activeSchedules = plan.schedules.filter { activeStatuses.contains($0.status) }
        let closures = store.recentClosures(limit: 8)

        var fileExistsByURL: [URL: Bool] = [:]
        for closure in closures {
            if let url = closure.documentURL {
                fileExistsByURL[url] = ports.opener.fileExists(url)
            }
        }

        let pauseMode = currentPauseMode()

        let input = MenuContentInput(
            schedules: activeSchedules,
            recentClosures: closures,
            fileExistsByURL: fileExistsByURL,
            isPaused: isPaused,
            pauseMode: pauseMode,
            pausedUntil: pausedUntil,
            hasPermission: permission == .granted,
            now: now,
            calendar: calendar
        )

        return MenuContentBuilder.build(input: input)
    }

    // MARK: - Suggestions

    public func suggestions(excludingExistingRules: Bool) async -> [Suggestion] {
        let installed = await ports.installedApps.installedApps()
        let excludedIDs: Set<String> = if excludingExistingRules {
            Set(store.appRules().map(\.bundleID))
        } else {
            []
        }
        return catalog.suggestions(installedApps: installed, excludingBundleIDs: excludedIDs)
    }

    public func applySuggestions(_ selected: [Suggestion]) {
        for suggestion in selected {
            store.addAppRule(
                bundleID: suggestion.entry.bundleID,
                appName: suggestion.appName,
                rule: suggestion.entry.rule
            )
        }
        store.save()
    }

    // MARK: - Onboarding

    public func completeOnboarding() {
        store.settings.onboardingComplete = true
        store.save()
        // Enable login item by default
        do {
            try ports.loginItem.setEnabled(true)
        } catch {
            logger.error("Failed to enable login item: \(error.localizedDescription, privacy: .public)")
        }
        route = .settings(.general)
    }
}

// MARK: - Event streams

extension AppCore {
    private func startEventStreams() {
        // Workspace events
        let workspaceTask = Task { [weak self] in
            guard let self else { return }
            for await event in ports.workspace.events() {
                await handleWorkspaceEvent(event)
            }
        }
        eventTasks.append(workspaceTask)

        // Focus signals
        let focusTask = Task { [weak self] in
            guard let self else { return }
            for await signal in ports.focus.signals() {
                await handleFocusSignal(signal)
            }
        }
        eventTasks.append(focusTask)

        // Permission changes
        let permTask = Task { [weak self] in
            guard let self else { return }
            for await _ in ports.permission.changes() {
                refreshPermission()
                // Re-check after 1.5 s (the trust state can lag the notification)
                let recheckAt = ports.scheduler.now().addingTimeInterval(1.5)
                _ = ports.scheduler.schedule(at: recheckAt, tolerance: 0.5) { [weak self] in
                    self?.refreshPermission()
                }
            }
        }
        eventTasks.append(permTask)
    }

    private func handleWorkspaceEvent(_ event: WorkspaceEvent) async {
        Signposts.signposter.emitEvent("workspaceEvent", "\(event.signpostLabel, privacy: .public)")
        switch event {
        case let .appActivated(app):
            let previousFrontmost = trackerState.frontmostPID
            await syncFocus(app: app)
            // Inspect the app that lost focus to refresh its titles
            if let prevPid = previousFrontmost, prevPid != app.pid {
                await inspectPid(prevPid)
            }

        case .appDeactivated:
            break // The activation of the next app covers it

        case .appLaunched:
            await scan()

        case let .appTerminated(pid):
            reduce(.appTerminated(pid: pid, at: ports.scheduler.now()))
            await ports.windowInspector.forget(pid: pid)

        case .activeSpaceChanged:
            await inspectPidsNeedingReach()

        case .displaysSlept, .sessionResigned:
            reduce(.displaysSlept(at: ports.scheduler.now()))
            stopScanTimer()

        case .displaysWoke, .sessionBecameActive:
            await scan()
            await syncFocus()
            startScanTimer()

        case .ownAppBecameActive:
            refreshPermission()
        }
    }

    private func handleFocusSignal(_ signal: FocusSignal) async {
        Signposts.signposter.emitEvent("focusSignal", "\(signal.kind.signpostLabel, privacy: .public)")
        // Signals from non-frontmost pids are ignored (AltTab lesson)
        guard signal.pid == trackerState.frontmostPID else { return }

        switch signal.kind {
        case .focusMayHaveChanged:
            let windowID = await focusedWindowID(pid: signal.pid)
            let app = trackerState.apps[signal.pid].map {
                ObservedApp(pid: $0.pid, bundleID: $0.bundleID, name: $0.appName, launchDate: $0.launchDate)
            }
            reduce(.focusChanged(app: app, windowID: windowID, at: signal.at))

        case .windowCreated:
            await scan()
            await inspectPid(signal.pid)
        }
    }
}

// MARK: - Core helpers

extension AppCore {
    private func focusedWindowID(pid: Int32) async -> UInt32? {
        let focusID = Signposts.signposter.makeSignpostID()
        let focusState = Signposts.signposter.beginInterval(
            "focusedWindowID", id: focusID, "pid=\(pid, privacy: .public)"
        )
        let windowID = await ports.windowInspector.focusedWindowID(pid: pid)
        Signposts.signposter.endInterval("focusedWindowID", focusState)
        return windowID
    }

    private func scan() async {
        let scanID = Signposts.signposter.makeSignpostID()
        let scanState = Signposts.signposter.beginInterval("scan", id: scanID)
        let windows = await ports.windowLister.listWindows()
        reduce(.windowList(windows, at: ports.scheduler.now()))
        Signposts.signposter.endInterval("scan", scanState, "windows=\(windows.count, privacy: .public)")
    }

    private func inspectPid(_ pid: Int32) async {
        // At most one inspection per pid at a time
        guard !inspectionsInProgress.contains(pid) else {
            inspectionsPending.insert(pid)
            return
        }
        inspectionsInProgress.insert(pid)

        let inspectID = Signposts.signposter.makeSignpostID()
        let inspectState = Signposts.signposter.beginInterval("inspect", id: inspectID, "pid=\(pid, privacy: .public)")
        let result = await ports.windowInspector.inspect(pid: pid)
        let inspectCount: Int = switch result {
        case let .inspected(windows): windows.count
        case .appUnavailable: -1
        case .notTrusted: -2
        }
        Signposts.signposter.endInterval(
            "inspect", inspectState, "windows=\(inspectCount, privacy: .public)"
        )
        reduce(.inspected(pid: pid, result, at: ports.scheduler.now()))
        lastInspectionTime[pid] = ports.scheduler.now()

        inspectionsInProgress.remove(pid)

        // If another request came in while we were running, do one more
        if inspectionsPending.remove(pid) != nil {
            await inspectPid(pid)
        }
    }

    private func inspectAllPids() async {
        for pid in trackerState.apps.keys {
            await inspectPid(pid)
        }
    }

    private func inspectPidsNeedingReach() async {
        let pids = Set(trackerState.windows.values.compactMap { window -> Int32? in
            if window.metadata == nil { return window.key.pid }
            if case .unreachable = window.closeState { return window.key.pid }
            return nil
        })
        for pid in pids {
            await inspectPid(pid)
        }
    }

    private func syncFocus(app: ObservedApp? = nil) async {
        let now = ports.scheduler.now()
        let frontApp = app ?? ports.workspace.frontmostApp()
        await ports.focus.observe(pid: frontApp?.pid)
        let windowID: UInt32? = if let frontApp {
            await focusedWindowID(pid: frontApp.pid)
        } else {
            nil
        }
        reduce(.focusChanged(app: frontApp, windowID: windowID, at: now))
    }

    private func reduce(_ event: TrackerEvent) {
        let reduceID = Signposts.signposter.makeSignpostID()
        let reduceState = Signposts.signposter.beginInterval(
            "reduce", id: reduceID, "\(event.signpostLabel, privacy: .public)"
        )
        let outputs = TrackerReducer.reduce(&trackerState, event)
        handleOutputs(outputs)
        replan()
        Signposts.signposter.endInterval("reduce", reduceState)
    }

    private func handleOutputs(_ outputs: [TrackerOutput]) {
        for output in outputs {
            switch output {
            case let .windowClosedBySqueegee(window, closedAt):
                store.appendClosure(ClosureValue(
                    bundleID: window.bundleID,
                    appName: window.appName,
                    windowTitle: window.metadata?.title,
                    documentURL: window.metadata?.documentURL,
                    kind: .windowClosed,
                    closedAt: closedAt
                ))

            case let .appQuitBySqueegee(app, closedAt):
                store.appendClosure(ClosureValue(
                    bundleID: app.bundleID,
                    appName: app.appName,
                    windowTitle: nil,
                    documentURL: nil,
                    kind: .appQuit,
                    closedAt: closedAt
                ))

            case let .needsInspection(pid):
                // Throttle: at most one per pid per 10 s from this output
                if let last = lastInspectionTime[pid],
                   ports.scheduler.now().timeIntervalSince(last) < Self.inspectionThrottleInterval
                {
                    break
                }
                Task { await inspectPid(pid) }

            case .permissionLost:
                refreshPermission()
            }
        }
    }
}

// MARK: - Replan and executor

extension AppCore {
    private func replan() {
        let replanID = Signposts.signposter.makeSignpostID()
        let replanState = Signposts.signposter.beginInterval("replan", id: replanID)
        defer { Signposts.signposter.endInterval("replan", replanState) }

        let now = ports.scheduler.now()

        // Clear an expired pause
        if store.settings.pauseModeRaw == "untilDate",
           let until = store.settings.pausedUntil,
           now >= until
        {
            store.settings.pauseModeRaw = nil
            store.settings.pausedUntil = nil
        }

        plan = Planner.plan(PlanInput(
            ruleSet: ruleSet,
            state: trackerState,
            now: now,
            isPaused: isPaused,
            pausedUntil: pausedUntil,
            hasPermission: permission == .granted
        ))

        // Re-arm deadline timer
        deadlineTimer?.cancel()
        deadlineTimer = nil
        if let wakeAt = plan.nextWakeAt {
            deadlineTimer = ports.scheduler.schedule(at: wakeAt, tolerance: Self.deadlineTolerance) { [weak self] in
                self?.replan()
            }
        }

        // Enqueue actions that are not already in flight
        for action in plan.actions {
            switch action {
            case let .closeWindow(key) where !inFlightCloses.contains(key):
                executorQueue.append(action)
            case let .quitApp(pid) where !inFlightQuits.contains(pid):
                executorQueue.append(action)
            default:
                break
            }
        }

        drainExecutor()
    }

    private func drainExecutor() {
        guard executorTask == nil, !executorQueue.isEmpty else { return }
        executorTask = Task { [weak self] in
            while let self, !self.executorQueue.isEmpty {
                let action = executorQueue.removeFirst()
                // Re-check against a fresh plan before executing
                let freshPlan = Planner.plan(PlanInput(
                    ruleSet: ruleSet,
                    state: trackerState,
                    now: ports.scheduler.now(),
                    isPaused: isPaused,
                    pausedUntil: pausedUntil,
                    hasPermission: permission == .granted
                ))
                guard freshPlan.actions.contains(action) else { continue }

                await executeAction(action)
            }
            self?.executorTask = nil
        }
    }

    private func executeAction(_ action: PlannedAction) async {
        let actionLabel = switch action {
        case .closeWindow: "close"
        case .quitApp: "quit"
        }
        let execID = Signposts.signposter.makeSignpostID()
        let execState = Signposts.signposter.beginInterval(
            "execute", id: execID, "\(actionLabel, privacy: .public)"
        )
        defer { Signposts.signposter.endInterval("execute", execState) }

        switch action {
        case let .closeWindow(key):
            inFlightCloses.insert(key)

            // Finder special case: resolve the folder URL before closing,
            // because AXDocument is not populated for Finder windows.
            let finderFolderURL = await resolveFinderFolderURL(for: key)

            let result = await ports.windowCloser.close(key)
            let now = ports.scheduler.now()

            switch result {
            case let .pressed(latest, wasListed):
                let enriched = enrichMetadata(latest, finderFolderURL: finderFolderURL)
                reduce(.closeSent(key, wasListed: wasListed, latest: enriched, at: now))
                // Schedule verification scans at +2s and +10s
                scheduleVerificationScans(key: key, at: now)

            case .unreachable:
                reduce(.closeUnreachable(key, at: now))

            case .noCloseButton:
                reduce(.closeHasNoButton(key))

            case .failed:
                reduce(.closeFailed(key, at: now))

            case .notTrusted:
                refreshPermission()
            }
            inFlightCloses.remove(key)

        case let .quitApp(pid):
            inFlightQuits.insert(pid)
            let terminated = await ports.appTerminator.terminate(pid: pid)
            let now = ports.scheduler.now()

            if terminated {
                reduce(.quitSent(pid: pid, at: now))
                // Schedule quit verification at +30s
                let verifyAt = now.addingTimeInterval(Tracker.quitVerificationDelay)
                _ = ports.scheduler.schedule(at: verifyAt, tolerance: Self.deadlineTolerance) { [weak self] in
                    self?.reduce(.quitVerification(pid: pid, at: self?.ports.scheduler.now() ?? verifyAt))
                }
            } else {
                // Treat as declined immediately
                reduce(.quitVerification(pid: pid, at: now))
            }
            inFlightQuits.remove(pid)
        }
    }

    private func scheduleVerificationScans(key: WindowKey, at closeTime: Date) {
        // Cap retained handles to avoid unbounded growth. Each close adds
        // two one-shot timers (2s + 10s). Dropping old entries is safe
        // because GCD retains a resumed DispatchSource internally; the
        // handle here is only a keep-alive for edge-case OS scheduling.
        if verificationTimers.count > 20 {
            verificationTimers.removeFirst(verificationTimers.count - 20)
        }

        // Scan at +2s
        let scan2 = closeTime.addingTimeInterval(Self.closeVerificationScanDelay)
        let timer2 = ports.scheduler.schedule(at: scan2, tolerance: 1) { [weak self] in
            Task { await self?.scan() }
        }
        verificationTimers.append(timer2)

        // Scan at +10s, then verification
        let scan10 = closeTime.addingTimeInterval(Tracker.closeVerificationDelay)
        let timer10 = ports.scheduler.schedule(at: scan10, tolerance: 1) { [weak self] in
            Task {
                await self?.scan()
                self?.reduce(.closeVerification(key, at: self?.ports.scheduler.now() ?? scan10))
            }
        }
        verificationTimers.append(timer10)
    }
}

// MARK: - Finder folder resolution

extension AppCore {
    private static let finderBundleID = "com.apple.finder"

    /// Queries the Finder folder URL for a window about to be closed.
    /// Returns nil for non-Finder windows, when the feature is off,
    /// or when the title cannot be resolved.
    private func resolveFinderFolderURL(for key: WindowKey) async -> URL? {
        guard store.settings.finderRestoreEnabled == true,
              let tracked = trackerState.windows[key],
              tracked.bundleID == Self.finderBundleID,
              tracked.metadata?.documentURL == nil,
              let title = tracked.metadata?.title
        else { return nil }
        return await ports.finderFolderResolver.folderURL(windowTitle: title)
    }

    /// Returns metadata with the Finder folder URL set, if one was resolved.
    private func enrichMetadata(
        _ metadata: WindowMetadata?,
        finderFolderURL: URL?
    ) -> WindowMetadata? {
        guard let finderFolderURL, var enriched = metadata, enriched.documentURL == nil else {
            return metadata
        }
        enriched.documentURL = finderFolderURL
        return enriched
    }
}

// MARK: - Rule observation

extension AppCore {
    private func observeRules() {
        ruleSet = withObservationTracking {
            store.ruleSet()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeRules()
                self?.replan()
            }
        }
    }
}

// MARK: - Permission

extension AppCore {
    private func refreshPermission() {
        let wasDenied = permission == .denied
        permission = ports.permission.isTrusted() ? .granted : .denied
        if wasDenied, permission == .granted {
            Task {
                await inspectAllPids()
                await syncFocus()
            }
        }
        replan()
    }
}

// MARK: - Scan timer

extension AppCore {
    private func startScanTimer() {
        stopScanTimer()
        scanTimer = ports.scheduler.schedule(
            every: Self.scanInterval,
            tolerance: Self.scanTolerance
        ) { [weak self] in
            Signposts.signposter.emitEvent("scanTick")
            Task {
                await self?.scan()
                // Reconcile focus: re-read the focused window of the frontmost app
                guard let self, let pid = self.trackerState.frontmostPID else { return }
                let windowID = await self.focusedWindowID(pid: pid)
                if let focusedKey = self.trackerState.focusedKey,
                   focusedKey.windowID != windowID ?? 0
                {
                    let app = self.trackerState.apps[pid].map {
                        ObservedApp(pid: $0.pid, bundleID: $0.bundleID, name: $0.appName, launchDate: $0.launchDate)
                    }
                    self.reduce(.focusChanged(app: app, windowID: windowID, at: self.ports.scheduler.now()))
                }
            }
        }
    }

    private func stopScanTimer() {
        scanTimer?.cancel()
        scanTimer = nil
    }
}

// MARK: - Settings selection

extension AppCore {
    private func restoreSettingsSelection() -> SettingsSelection {
        guard let raw = store.settings.lastSettingsSelection else { return .general }
        switch raw {
        case "general": return .general
        case "global": return .globalRule
        default: return .appRule(bundleID: raw)
        }
    }

    private func selectionString(_ selection: SettingsSelection) -> String {
        switch selection {
        case .general: "general"
        case .globalRule: "global"
        case let .appRule(bundleID): bundleID
        }
    }
}

// MARK: - Pause mode

extension AppCore {
    private func currentPauseMode() -> PauseMode {
        let settings = store.settings
        guard let raw = settings.pauseModeRaw else { return .none }
        switch raw {
        case "untilResumed":
            return .untilResumed
        case "untilDate":
            guard let until = settings.pausedUntil else { return .none }
            // Use the in-memory option when available (same session).
            // Fall back to a time-based heuristic after relaunch.
            if let option = lastPauseOption {
                switch option {
                case .oneHour: return .untilDate(.oneHour)
                case .untilTomorrow: return .untilDate(.untilTomorrow)
                case .untilResumed: break // handled by the "untilResumed" case above
                }
            }
            let now = ports.scheduler.now()
            let diff = until.timeIntervalSince(now)
            if diff > 0, diff <= 3660 {
                return .untilDate(.oneHour)
            }
            return .untilDate(.untilTomorrow)
        default:
            return .none
        }
    }
}
