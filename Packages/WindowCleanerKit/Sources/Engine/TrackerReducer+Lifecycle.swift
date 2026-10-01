import Foundation

// MARK: - Close/quit lifecycle, restore, and shared helpers

extension TrackerReducer {
    // MARK: - Close lifecycle

    static func handleCloseSent(
        _ state: inout TrackerState,
        key: WindowKey,
        wasListed: Bool,
        latest: WindowMetadata?,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        guard state.windows[key] != nil else { return [] }
        state.windows[key]?.closeState = .sent(at: at, wasListed: wasListed)
        if let latest {
            state.windows[key]?.metadata = latest
        }
        return []
    }

    static func handleCloseUnreachable(
        _ state: inout TrackerState,
        key: WindowKey,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        state.windows[key]?.closeState = .unreachable(since: at)
        return []
    }

    static func handleCloseFailed(
        _ state: inout TrackerState,
        key: WindowKey,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        state.windows[key]?.closeState = .declined(at: at)
        return []
    }

    static func handleCloseHasNoButton(
        _ state: inout TrackerState,
        key: WindowKey
    ) -> [TrackerOutput] {
        state.windows[key]?.metadata?.isStandard = false
        return []
    }

    static func handleCloseVerification(
        _ state: inout TrackerState,
        key: WindowKey,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        guard let window = state.windows[key],
              case let .sent(_, wasListed) = window.closeState
        else {
            return []
        }

        if wasListed {
            state.windows[key]?.closeState = .declined(at: at)
        } else {
            state.windows[key]?.closeState = .unreachable(since: at)
        }
        return []
    }

    // MARK: - Quit lifecycle

    static func handleQuitSent(
        _ state: inout TrackerState,
        pid: Int32,
        // swiftlint:disable:next identifier_name
        at: Date
    ) -> [TrackerOutput] {
        state.apps[pid]?.quitState = .sent(at: at)
        return []
    }

    static func handleQuitVerification(
        _ state: inout TrackerState,
        pid: Int32,
        at _: Date
    ) -> [TrackerOutput] {
        guard state.apps[pid] != nil, case .sent = state.apps[pid]?.quitState else {
            return []
        }
        state.apps[pid]?.quitState = .declined
        return []
    }

    // MARK: - Restore

    static func handleRestore(
        _ state: inout TrackerState,
        snapshots: [TrackedWindowSnapshot],
        at _: Date
    ) -> [TrackerOutput] {
        for snapshot in snapshots {
            guard let window = state.windows[snapshot.key],
                  window.bundleID == snapshot.bundleID
            else {
                continue
            }

            // Check that the app's launchDate matches (within 1 s, or both nil)
            let app = state.apps[snapshot.key.pid]
            let launchDatesMatch: Bool = switch (app?.launchDate, snapshot.processLaunchDate) {
            case (nil, nil):
                true
            case let (appDate?, snapDate?):
                abs(appDate.timeIntervalSince(snapDate)) <= 1
            default:
                false
            }

            guard launchDatesMatch else { continue }

            state.windows[snapshot.key]?.firstSeen = snapshot.firstSeen
            state.windows[snapshot.key]?.lastActive = snapshot.lastActive
            if let closeSentAt = snapshot.closeSentAt {
                state.windows[snapshot.key]?.closeState = .declined(at: closeSentAt)
            }
        }
        return []
    }

    // MARK: - Stale close resolution

    // Safety net: if a window has been in `.sent` state for longer than the
    // close-verification delay and a window-list scan still sees it, the
    // scheduled verification callback may have failed to fire. Resolve these
    // windows the same way `handleCloseVerification` would.
    // swiftlint:disable:next identifier_name
    static func resolveStaleCloses(_ state: inout TrackerState, at: Date) {
        for key in state.windows.keys {
            guard let window = state.windows[key],
                  case let .sent(sentAt, wasListed) = window.closeState,
                  at.timeIntervalSince(sentAt) > Tracker.closeVerificationDelay
            else { continue }

            if wasListed {
                state.windows[key]?.closeState = .declined(at: at)
            } else {
                state.windows[key]?.closeState = .unreachable(since: at)
            }
        }
    }

    // MARK: - Shared helpers

    // Ends the current focus session. If it qualifies (>= 5 s),
    // updates lastActive and resets closeState to .none.
    // swiftlint:disable:next identifier_name
    static func endSession(_ state: inout TrackerState, at: Date) {
        guard let session = state.session else { return }
        let duration = at.timeIntervalSince(session.start)
        if duration >= Tracker.focusQualifyingDuration {
            state.windows[session.key]?.lastActive = at
            if let closeState = state.windows[session.key]?.closeState, closeState.isDeclined {
                state.windows[session.key]?.closeState = .none
            }
        }
    }

    // Recomputes the presence of each app.
    // swiftlint:disable:next identifier_name
    static func recomputePresence(_ state: inout TrackerState, at: Date) {
        for pid in state.apps.keys {
            let presentCount = state.windows.values.count(where: { window in
                window.key.pid == pid && (window.metadata == nil || window.metadata?.isStandard == true)
            })

            if presentCount > 0 {
                state.apps[pid]?.noStandardWindowsSince = nil
                state.apps[pid]?.quitAfterWindowCleanerClose = false
                if state.apps[pid]?.quitState == .declined {
                    state.apps[pid]?.quitState = .none
                }
            } else if state.apps[pid]?.hadStandardWindow == true,
                      state.apps[pid]?.noStandardWindowsSince == nil
            {
                state.apps[pid]?.noStandardWindowsSince = at
            }
        }
    }
}

// MARK: - CloseState helpers

extension CloseState {
    var isSentOrDeclined: Bool {
        switch self {
        case .sent, .declined: true
        default: false
        }
    }

    var isDeclined: Bool {
        if case .declined = self { return true }
        return false
    }
}
