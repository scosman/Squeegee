import ApplicationServices
import Engine
import Foundation
import os

/// Observes AX focus events for a single app at a time.
///
/// This holds **one** `AXObserver`, attached only to the frontmost app. It avoids
/// the problems of registering observers on many apps simultaneously.
///
/// ## Threading
///
/// `AXObserverCreate` and `AXObserverAddNotification` send blocking messages to
/// the target app. A busy app can stall the caller for the full messaging
/// timeout, so all AX work runs on a dedicated `AXRunLoopThread`, never on the
/// main thread. The observer's run-loop source is also attached to that thread,
/// so the callback runs there. All mutable state is confined to that thread.
public final class FrontmostFocusObserver: FocusObserving, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "net.scosman.squeegee",
        category: "FocusObserver"
    )

    /// Maximum number of registration retries when the app is still launching.
    private static let retryDelays: [TimeInterval] = [0.5, 1, 2, 4]

    /// AX messaging timeout for registration calls, in seconds.
    private static let messagingTimeout: Float = 0.5

    private let ownPID: Int32
    private let worker = AXRunLoopThread(name: "net.scosman.squeegee.focus-observer")
    fileprivate let continuation: AsyncStream<FocusSignal>.Continuation
    private let stream: AsyncStream<FocusSignal>

    // Confined to `worker`. fileprivate so the C callback can read it.
    fileprivate var currentPID: Int32?
    private var currentObserver: AXObserver?

    public init(ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
        let (newStream, newContinuation) = AsyncStream<FocusSignal>.makeStream(bufferingPolicy: .bufferingNewest(64))
        stream = newStream
        continuation = newContinuation
    }

    public func signals() -> AsyncStream<FocusSignal> {
        stream
    }

    /// Moves the observer to `pid`. Our own process is never observed: its AX
    /// requests are served by our main thread, and its windows are not tracked.
    public func observe(pid: Int32?) async {
        let target = pid == ownPID ? nil : pid
        let changed = await worker.perform { self.switchTarget(to: target) }
        guard changed, let target else { return }

        for retryIndex in 0 ... Self.retryDelays.count {
            let needsRetry = await worker.perform { self.attachObserver(pid: target) }
            guard needsRetry, retryIndex < Self.retryDelays.count else { return }
            let delay = Self.retryDelays[retryIndex]
            Self.logger.info("Retrying observer registration for pid \(target) in \(delay)s")
            try? await Task.sleep(for: .seconds(delay))
        }
    }

    /// Removes the current observer and finishes the stream.
    /// Called from the owner when the observer is no longer needed.
    public func stop() {
        worker.enqueue {
            self.removeCurrentObserver()
            self.currentPID = nil
        }
        continuation.finish()
    }

    // MARK: - Observer management (worker thread only)

    /// Sets the target pid and drops the old observer. Returns false when the
    /// target is unchanged.
    private func switchTarget(to pid: Int32?) -> Bool {
        if pid == currentPID { return false }
        removeCurrentObserver()
        currentPID = pid
        return true
    }

    private func removeCurrentObserver() {
        if let observer = currentObserver {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
            currentObserver = nil
        }
    }

    /// Creates and attaches an observer for `pid`. Returns true when the app is
    /// not ready yet and the caller should retry.
    private func attachObserver(pid: Int32) -> Bool {
        // A later observe(pid:) call replaced this target.
        guard currentPID == pid, currentObserver == nil else { return false }

        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, focusCallback, &observer)
        guard createResult == .success, let observer else {
            Self.logger.warning("AXObserverCreate failed for pid \(pid): \(createResult.rawValue)")
            return false
        }

        let appElement = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(appElement, Self.messagingTimeout)
        let notifications = [
            kAXFocusedWindowChangedNotification,
            kAXMainWindowChangedNotification,
            kAXWindowCreatedNotification
        ]

        var needsRetry = false
        for notification in notifications {
            let addResult = AXObserverAddNotification(
                observer,
                appElement,
                notification as CFString,
                Unmanaged.passUnretained(self).toOpaque()
            )
            switch addResult {
            case .success, .notificationAlreadyRegistered:
                break
            case .notificationUnsupported:
                // Some apps do not support all notifications; accept and continue.
                Self.logger.info("Notification \(notification) unsupported for pid \(pid)")
            case .cannotComplete, .notImplemented:
                needsRetry = true
            default:
                Self.logger.warning(
                    "AXObserverAddNotification(\(notification)) failed for pid \(pid): \(addResult.rawValue)"
                )
            }
        }

        if needsRetry { return true }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
        currentObserver = observer
        return false
    }
}

// MARK: - C callback

/// The `@convention(c)` callback for AXObserver notifications.
/// Takes `Date()` first, then yields a `FocusSignal` into the stream.
///
/// This callback runs on the observer's worker thread (where the AXObserver
/// source was added), so reading `currentPID` is safe.
private func focusCallback(
    _: AXObserver,
    _: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    let timestamp = Date()
    guard let refcon else { return }

    let kind: FocusSignal.Kind = if (notification as String) == kAXWindowCreatedNotification {
        .windowCreated
    } else {
        .focusMayHaveChanged
    }

    let observer = Unmanaged<FrontmostFocusObserver>.fromOpaque(refcon).takeUnretainedValue()
    let pid = observer.currentPID ?? 0
    observer.continuation.yield(FocusSignal(pid: pid, kind: kind, at: timestamp))
}
