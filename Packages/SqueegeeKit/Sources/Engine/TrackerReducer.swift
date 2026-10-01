import Foundation

/// Pure event-sourcing reducer: processes `TrackerEvent`s to update `TrackerState`
/// and returns side-effect requests as `TrackerOutput`.
public enum TrackerReducer {
    // swiftlint:disable identifier_name cyclomatic_complexity
    public static func reduce(
        _ state: inout TrackerState,
        _ event: TrackerEvent
    ) -> [TrackerOutput] {
        switch event {
        case let .windowList(observed, at):
            handleWindowList(&state, observed, at: at)
        case let .inspected(pid, result, at):
            handleInspected(&state, pid: pid, result: result, at: at)
        case let .focusChanged(app, windowID, at):
            handleFocusChanged(&state, app: app, windowID: windowID, at: at)
        case let .displaysSlept(at):
            handleDisplaysSleep(&state, at: at)
        case let .appTerminated(pid, at):
            handleAppTerminated(&state, pid: pid, at: at)
        case let .closeSent(key, wasListed, latest, at):
            handleCloseSent(&state, key: key, wasListed: wasListed, latest: latest, at: at)
        case let .closeUnreachable(key, at):
            handleCloseUnreachable(&state, key: key, at: at)
        case let .closeFailed(key, at):
            handleCloseFailed(&state, key: key, at: at)
        case let .closeHasNoButton(key):
            handleCloseHasNoButton(&state, key: key)
        case let .closeVerification(key, at):
            handleCloseVerification(&state, key: key, at: at)
        case let .quitSent(pid, at):
            handleQuitSent(&state, pid: pid, at: at)
        case let .quitVerification(pid, at):
            handleQuitVerification(&state, pid: pid, at: at)
        case let .restore(snapshots, at):
            handleRestore(&state, snapshots: snapshots, at: at)
        }
    }

    // swiftlint:enable identifier_name cyclomatic_complexity

    // MARK: - Window list

    static func handleWindowList(
        _ state: inout TrackerState,
        _ observed: [ObservedWindow],
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        var outputs: [TrackerOutput] = []
        let observedKeys = Set(observed.map(\.key))

        insertNewWindows(&state, observed: observed, at: at)
        removeMissingWindows(&state, observedKeys: observedKeys, at: at, outputs: &outputs)
        resolveStaleCloses(&state, at: at)
        collectInspectionNeeds(state, outputs: &outputs)
        recomputePresence(&state, at: at)

        return outputs
    }

    private static func insertNewWindows(
        _ state: inout TrackerState,
        observed: [ObservedWindow],
        // swiftlint:disable:next identifier_name
        at: Date
    ) {
        for observedWindow in observed {
            if state.windows[observedWindow.key] == nil {
                state.windows[observedWindow.key] = TrackedWindow(
                    key: observedWindow.key,
                    bundleID: observedWindow.app.bundleID,
                    appName: observedWindow.app.name,
                    firstSeen: at
                )
            }
            if state.apps[observedWindow.key.pid] == nil {
                state.apps[observedWindow.key.pid] = TrackedApp(
                    pid: observedWindow.key.pid,
                    bundleID: observedWindow.app.bundleID,
                    appName: observedWindow.app.name,
                    launchDate: observedWindow.app.launchDate
                )
            }
        }
    }

    private static func removeMissingWindows(
        _ state: inout TrackerState,
        observedKeys: Set<WindowKey>,
        // swiftlint:disable:next identifier_name
        at: Date,
        outputs: inout [TrackerOutput]
    ) {
        let trackedKeys = Array(state.windows.keys)
        for key in trackedKeys where !observedKeys.contains(key) {
            guard let window = state.windows.removeValue(forKey: key) else { continue }

            if window.closeState.isSentOrDeclined {
                outputs.append(.windowClosedBySqueegee(window, at: at))
                if state.apps[key.pid] != nil {
                    let appHasPresentWindows = state.windows.values.contains { $0.key.pid == key.pid && ($0.metadata == nil || $0.metadata?.isStandard == true) }
                    if !appHasPresentWindows {
                        state.apps[key.pid]?.quitAfterSqueegeeClose = true
                    }
                }
            }

            if state.focusedKey == key { state.focusedKey = nil }
            if state.session?.key == key { state.session = nil }
        }
    }

    private static func collectInspectionNeeds(
        _ state: TrackerState,
        outputs: inout [TrackerOutput]
    ) {
        var inspectedPids = Set<Int32>()
        for window in state.windows.values where window.metadata == nil {
            if inspectedPids.insert(window.key.pid).inserted {
                outputs.append(.needsInspection(pid: window.key.pid))
            }
        }
    }

    // MARK: - Inspected

    static func handleInspected(
        _ state: inout TrackerState,
        pid: Int32,
        result: InspectionResult,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        switch result {
        case let .inspected(map):
            for (windowID, meta) in map {
                let key = WindowKey(pid: pid, windowID: windowID)
                if state.windows[key] != nil {
                    state.windows[key]?.metadata = meta
                    if case .unreachable = state.windows[key]?.closeState {
                        state.windows[key]?.closeState = .none
                    }
                } else {
                    // AX saw it before the CG scan did
                    let appName = state.apps[pid]?.appName ?? ""
                    let bundleID = state.apps[pid]?.bundleID ?? ""
                    state.windows[key] = TrackedWindow(
                        key: key,
                        bundleID: bundleID,
                        appName: appName,
                        firstSeen: at,
                        metadata: meta
                    )
                }
                if meta.isStandard {
                    state.apps[pid]?.hadStandardWindow = true
                }
            }
            // Tracked windows of this pid NOT in the map keep their old metadata
            // (they are on another Space)
            recomputePresence(&state, at: at)
            return []

        case .appUnavailable:
            return []

        case .notTrusted:
            return [.permissionLost]
        }
    }

    // MARK: - Focus changed

    static func handleFocusChanged(
        _ state: inout TrackerState,
        app: ObservedApp?,
        windowID: UInt32?,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        var outputs: [TrackerOutput] = []

        // End the current session
        endSession(&state, at: at)

        state.frontmostPID = app?.pid

        if let app, let windowID {
            let key = WindowKey(pid: app.pid, windowID: windowID)
            if state.windows[key] == nil {
                state.windows[key] = TrackedWindow(
                    key: key,
                    bundleID: app.bundleID,
                    appName: app.name,
                    firstSeen: at
                )
                outputs.append(.needsInspection(pid: app.pid))
            }
            if state.apps[app.pid] == nil {
                state.apps[app.pid] = TrackedApp(
                    pid: app.pid,
                    bundleID: app.bundleID,
                    appName: app.name,
                    launchDate: app.launchDate
                )
            }
            state.focusedKey = key
            state.session = FocusSession(key: key, start: at)
        } else {
            state.focusedKey = nil
            state.session = nil
        }

        return outputs
    }

    // MARK: - Displays slept

    static func handleDisplaysSleep(
        _ state: inout TrackerState,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        endSession(&state, at: at)
        state.session = nil
        // Keep focusedKey and frontmostPID
        return []
    }

    // MARK: - App terminated

    static func handleAppTerminated(
        _ state: inout TrackerState,
        pid: Int32,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        var outputs: [TrackerOutput] = []

        // Remove the app's windows (not closure records, even if closeState == .sent)
        let windowKeys = state.windows.keys.filter { $0.pid == pid }
        for key in windowKeys {
            state.windows.removeValue(forKey: key)
        }

        // Output quit record if we sent the quit
        if let app = state.apps[pid], case .sent = app.quitState {
            outputs.append(.appQuitBySqueegee(app, at: at))
        }

        // Remove the app
        state.apps.removeValue(forKey: pid)

        // Clear focus/session/frontmost if they point to this app
        if state.frontmostPID == pid {
            state.frontmostPID = nil
        }
        if let focusedKey = state.focusedKey, focusedKey.pid == pid {
            state.focusedKey = nil
        }
        if let session = state.session, session.key.pid == pid {
            state.session = nil
        }

        return outputs
    }
}
