import ApplicationServices
import Engine
import os

/// Observes AX focus events for a single app at a time.
///
/// This holds **one** `AXObserver`, attached only to the frontmost app. It avoids
/// the problems of registering observers on many apps simultaneously.
@MainActor
public final class FrontmostFocusObserver: FocusObserving, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "net.scosman.windowcleaner",
        category: "FocusObserver"
    )

    // fileprivate so the C callback can access them (it runs on the main thread).
    fileprivate var currentPID: Int32?
    private var currentObserver: AXObserver?
    fileprivate let continuation: AsyncStream<FocusSignal>.Continuation
    private let stream: AsyncStream<FocusSignal>

    /// Maximum number of registration retries when the app is still launching.
    private static let retryDelays: [TimeInterval] = [0.5, 1, 2, 4]

    public init() {
        let (newStream, newContinuation) = AsyncStream<FocusSignal>.makeStream(bufferingPolicy: .bufferingNewest(64))
        stream = newStream
        continuation = newContinuation
    }

    public nonisolated func signals() -> AsyncStream<FocusSignal> {
        stream
    }

    public func observe(pid: Int32?) async {
        if pid == currentPID { return }

        removeCurrentObserver()
        currentPID = pid

        guard let pid else { return }

        await registerObserver(for: pid, retryIndex: 0)
    }

    /// Removes the current observer and finishes the stream.
    /// Called from the owner when the observer is no longer needed.
    public func stop() {
        removeCurrentObserver()
        currentPID = nil
        continuation.finish()
    }

    // MARK: - Observer management

    private func removeCurrentObserver() {
        if let observer = currentObserver {
            let source = AXObserverGetRunLoopSource(observer)
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            currentObserver = nil
        }
    }

    private func registerObserver(for pid: Int32, retryIndex: Int) async {
        guard currentPID == pid else { return }

        var observer: AXObserver?
        let createResult = AXObserverCreate(pid, focusCallback, &observer)
        guard createResult == .success, let observer else {
            Self.logger.warning("AXObserverCreate failed for pid \(pid): \(createResult.rawValue)")
            return
        }

        let appElement = AXUIElementCreateApplication(pid)
        let notifications: [(String, FocusSignal.Kind)] = [
            (kAXFocusedWindowChangedNotification, .focusMayHaveChanged),
            (kAXMainWindowChangedNotification, .focusMayHaveChanged),
            (kAXWindowCreatedNotification, .windowCreated)
        ]

        var needsRetry = false
        for (notification, _) in notifications {
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

        if needsRetry, retryIndex < Self.retryDelays.count {
            let delay = Self.retryDelays[retryIndex]
            Self.logger.info("Retrying observer registration for pid \(pid) in \(delay)s")
            try? await Task.sleep(for: .seconds(delay))
            await registerObserver(for: pid, retryIndex: retryIndex + 1)
            return
        }

        let source = AXObserverGetRunLoopSource(observer)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        currentObserver = observer
    }
}

// MARK: - C callback

/// The `@convention(c)` callback for AXObserver notifications.
/// Takes `Date()` first, then yields a `FocusSignal` into the stream.
///
/// This callback runs on the main run loop (where the AXObserver source was
/// added), so it is safe to access `@MainActor` state through `assumeIsolated`.
private func focusCallback(
    _: AXObserver,
    _: AXUIElement,
    notification: CFString,
    refcon: UnsafeMutableRawPointer?
) {
    let timestamp = Date()
    guard let refcon else { return }

    let kind: FocusSignal.Kind
    let notifString = notification as String
    if notifString == kAXWindowCreatedNotification {
        kind = .windowCreated
    } else {
        kind = .focusMayHaveChanged
    }

    // Extract the observer before entering the MainActor closure so that the
    // compiler does not flag the raw pointer as a sending risk.
    let observer = Unmanaged<FrontmostFocusObserver>.fromOpaque(refcon).takeUnretainedValue()

    // The callback runs on the main run loop, so MainActor isolation holds.
    MainActor.assumeIsolated {
        let pid = observer.currentPID ?? 0
        let signal = FocusSignal(pid: pid, kind: kind, at: timestamp)
        observer.continuation.yield(signal)
    }
}
