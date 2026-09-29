import Engine
import Foundation
import os
import SystemBridge

/// Shared store of document URLs captured from windows closed in the Live
/// Inspector, so the sb_reopen wired script can reopen them.
@MainActor
final class CapturedCloseStore {
    static let shared = CapturedCloseStore()
    private(set) var entries: [(documentURL: URL, bundleID: String)] = []

    func append(documentURL: URL, bundleID: String) {
        entries.append((documentURL: documentURL, bundleID: bundleID))
    }

    func drainAll() -> [(documentURL: URL, bundleID: String)] {
        let drained = entries
        entries.removeAll()
        return drained
    }
}

/// A timestamped log entry from the monitor loop.
struct MonitorLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
}

/// A simplified stand-alone monitoring loop built only from SystemBridge ports.
/// It mirrors the shape of the AppCore event pump but has no engine logic,
/// so it can run before AppCore exists (Phase 2).
///
/// - 60 s CG window scan (stopped while displays sleep)
/// - FrontmostFocusObserver moved on each app activation
/// - Inspect previous app on each activation
@MainActor
@Observable
final class MonitorLoop {
    private(set) var windows: [ObservedWindow] = []
    private(set) var inspectionResults: [Int32: InspectionResult] = [:]
    private(set) var frontmostApp: ObservedApp?
    private(set) var focusedWindowID: UInt32?
    private(set) var logEntries: [MonitorLogEntry] = []
    private(set) var isRunning = false
    private(set) var permissionGranted = false

    /// The result of the last close attempt, shown in the Live Inspector.
    private(set) var lastCloseResult: CloseAttemptResult?

    /// Captured closes stored in the shared store, exposed for the UI badge count.
    var capturedCloses: [(documentURL: URL, bundleID: String)] {
        CapturedCloseStore.shared.entries
    }

    private let lister: CGWindowLister
    private let axService: AXWindowService
    private let focusObserver: FrontmostFocusObserver
    private let workspaceEvents: LiveWorkspaceEvents
    private let permission: LiveAccessibilityPermission

    private var workspaceTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var permissionTask: Task<Void, Never>?
    private var scanTimer: (any Cancellable)?

    private let scheduler = LiveAppScheduler()

    private static let logger = Logger(
        subsystem: "net.scosman.windowcleaner",
        category: "MonitorLoop"
    )

    init() {
        lister = CGWindowLister()
        axService = AXWindowService()
        focusObserver = FrontmostFocusObserver()
        workspaceEvents = LiveWorkspaceEvents()
        permission = LiveAccessibilityPermission()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        permissionGranted = permission.isTrusted()

        log("Monitor started (permission: \(permissionGranted ? "granted" : "denied"))")

        // Initial scan
        Task { await scan() }

        // Stream workspace events
        workspaceTask = Task { [weak self] in
            guard let self else { return }
            for await event in workspaceEvents.events() {
                await handleWorkspaceEvent(event)
            }
        }

        // Stream focus signals
        focusTask = Task { [weak self] in
            guard let self else { return }
            for await signal in focusObserver.signals() {
                await handleFocusSignal(signal)
            }
        }

        // Stream permission changes
        permissionTask = Task { [weak self] in
            guard let self else { return }
            for await _ in permission.changes() {
                let trusted = permission.isTrusted()
                log("Permission changed: \(trusted ? "granted" : "denied")")
                permissionGranted = trusted
            }
        }

        // Sync focus to current frontmost app
        Task { await syncFocus() }

        // Start the 60 s scan timer
        startScanTimer()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        workspaceTask?.cancel()
        focusTask?.cancel()
        permissionTask?.cancel()
        scanTimer?.cancel()
        focusObserver.stop()

        log("Monitor stopped")
    }

    // MARK: - Scanning

    private func scan() async {
        let listed = await lister.listWindows()
        windows = listed
        await axService.updateBounds(listed)

        // Inspect each pid
        var pids = Set<Int32>()
        for window in listed {
            pids.insert(window.key.pid)
        }
        for pid in pids {
            let result = await axService.inspect(pid: pid)
            inspectionResults[pid] = result
        }
    }

    private func startScanTimer() {
        scanTimer?.cancel()
        scanTimer = scheduler.schedule(every: 60, tolerance: 6) { [weak self] in
            guard let self else { return }
            Task { await self.scan() }
        }
    }

    // MARK: - Event handling

    private func handleWorkspaceEvent(_ event: WorkspaceEvent) async {
        switch event {
        case let .appActivated(app):
            await handleAppActivated(app)
        case let .appDeactivated(pid):
            log("appDeactivated: pid \(pid)")
        case let .appLaunched(app):
            await handleAppLaunched(app)
        case let .appTerminated(pid):
            await handleAppTerminated(pid)
        case .activeSpaceChanged:
            log("activeSpaceChanged")
            await scan()
        case .displaysSlept:
            handleDisplaysSleep()
        case .displaysWoke:
            await handleDisplaysWake()
        case .sessionResigned:
            handleDisplaysSleep()
        case .sessionBecameActive:
            await handleDisplaysWake()
        case .ownAppBecameActive:
            handleOwnAppActivated()
        }
    }

    private func handleAppActivated(_ app: ObservedApp) async {
        let previousPID = frontmostApp?.pid
        frontmostApp = app
        log("appActivated: \(app.name) (pid \(app.pid))")

        await focusObserver.observe(pid: app.pid)

        // Inspect previous app for title changes
        if let previousPID, previousPID != app.pid {
            let result = await axService.inspect(pid: previousPID)
            inspectionResults[previousPID] = result
        }

        // Query focused window of new app
        focusedWindowID = await axService.focusedWindowID(pid: app.pid)
    }

    private func handleAppLaunched(_ app: ObservedApp) async {
        log("appLaunched: \(app.name) (pid \(app.pid))")
        await scan()
    }

    private func handleAppTerminated(_ pid: Int32) async {
        log("appTerminated: pid \(pid)")
        await axService.forget(pid: pid)
        inspectionResults[pid] = nil
        await scan()
    }

    private func handleDisplaysSleep() {
        log("displaysSlept / sessionResigned")
        scanTimer?.cancel()
    }

    private func handleDisplaysWake() async {
        log("displaysWoke / sessionBecameActive")
        await scan()
        startScanTimer()
    }

    private func handleOwnAppActivated() {
        let trusted = permission.isTrusted()
        if trusted != permissionGranted {
            log("Permission changed on app activation: \(trusted ? "granted" : "denied")")
            permissionGranted = trusted
        }
    }

    private func handleFocusSignal(_ signal: FocusSignal) async {
        switch signal.kind {
        case .focusMayHaveChanged:
            log("focusMayHaveChanged: pid \(signal.pid)")
            if signal.pid == frontmostApp?.pid {
                focusedWindowID = await axService.focusedWindowID(pid: signal.pid)
            }
        case .windowCreated:
            log("windowCreated: pid \(signal.pid)")
            await scan()
        }
    }

    private func syncFocus() async {
        if let app = workspaceEvents.frontmostApp() {
            frontmostApp = app
            await focusObserver.observe(pid: app.pid)
            focusedWindowID = await axService.focusedWindowID(pid: app.pid)
        }
    }

    // MARK: - Logging

    func clearLog() {
        logEntries.removeAll()
    }

    private func log(_ message: String) {
        let entry = MonitorLogEntry(timestamp: Date(), message: message)
        logEntries.append(entry)
        // Keep the log bounded
        if logEntries.count > 500 {
            logEntries.removeFirst(logEntries.count - 500)
        }
        Self.logger.info("\(message)")
    }

    // MARK: - Actions for manual test scripts

    /// Closes the window with the given key, captures document URL for reopen.
    func closeWindow(_ key: WindowKey) async -> CloseAttemptResult {
        // Capture document URL and bundle ID before closing.
        let window = windows.first { $0.key == key }
        let bundleID = window?.app.bundleID
        var docURL: URL?
        if let pid = window?.key.pid,
           let inspection = inspectionResults[pid],
           case let .inspected(map) = inspection,
           let meta = map[key.windowID]
        {
            docURL = meta.documentURL
        }

        let result = await axService.close(key)
        lastCloseResult = result
        if let docURL, let bundleID {
            CapturedCloseStore.shared.append(documentURL: docURL, bundleID: bundleID)
        }
        log("close(\(key)): \(result)")
        await scan()
        return result
    }

    /// Reopens all captured closed documents using LiveAppOpener, then clears the list.
    func reopenCapturedDocuments() async {
        let entries = CapturedCloseStore.shared.drainAll()
        guard !entries.isEmpty else {
            log("reopen: no captured document URLs")
            return
        }
        let opener = LiveAppOpener()
        for entry in entries {
            do {
                try await opener.open(
                    documentURL: entry.documentURL,
                    withBundleID: entry.bundleID
                )
                log("reopen: opened \(entry.documentURL.lastPathComponent) in \(entry.bundleID)")
            } catch {
                log("reopen failed for \(entry.documentURL.lastPathComponent): \(error)")
            }
        }
    }

    /// Terminates the app with the given pid.
    func terminateApp(pid: Int32) async -> Bool {
        let terminator = LiveAppTerminator()
        let delivered = await terminator.terminate(pid: pid)
        log("terminate(pid: \(pid)): \(delivered)")
        return delivered
    }
}
