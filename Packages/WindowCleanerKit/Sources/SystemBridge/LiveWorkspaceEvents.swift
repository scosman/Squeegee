import AppKit
import Engine
import os

/// Implements `WorkspaceEventSource` by observing NSWorkspace and NSApplication notifications.
public final class LiveWorkspaceEvents: WorkspaceEventSource, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "net.scosman.windowcleaner",
        category: "WorkspaceEvents"
    )

    private let continuation: AsyncStream<WorkspaceEvent>.Continuation
    private let stream: AsyncStream<WorkspaceEvent>
    private var tokens: [NSObjectProtocol] = []

    public init() {
        let (newStream, newContinuation) = AsyncStream<WorkspaceEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        stream = newStream
        continuation = newContinuation
        registerObservers()
    }

    deinit {
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        let defaultCenter = NotificationCenter.default
        for token in tokens {
            workspaceCenter.removeObserver(token)
            defaultCenter.removeObserver(token)
        }
        continuation.finish()
    }

    public func events() -> AsyncStream<WorkspaceEvent> {
        stream
    }

    public func frontmostApp() -> ObservedApp? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return observedApp(from: app)
    }

    public func areDisplaysAsleep() -> Bool {
        CGDisplayIsAsleep(CGMainDisplayID()) != 0
    }

    // MARK: - Notification registration

    private func registerObservers() {
        registerWorkspaceObservers()
        registerAppObservers()
    }

    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter

        tokens.append(center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = self?.runningApp(from: note) else { return }
            self?.continuation.yield(.appActivated(app))
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let nsApp = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.continuation.yield(.appDeactivated(pid: nsApp.processIdentifier))
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let app = self?.runningApp(from: note) else { return }
            self?.continuation.yield(.appLaunched(app))
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let nsApp = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self?.continuation.yield(.appTerminated(pid: nsApp.processIdentifier))
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation.yield(.activeSpaceChanged)
        })

        registerSleepAndSessionObservers(on: center)
    }

    private func registerSleepAndSessionObservers(on center: NotificationCenter) {
        tokens.append(center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation.yield(.displaysSlept)
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation.yield(.displaysWoke)
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation.yield(.sessionResigned)
        })

        tokens.append(center.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation.yield(.sessionBecameActive)
        })
    }

    private func registerAppObservers() {
        let defaultCenter = NotificationCenter.default
        tokens.append(defaultCenter.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.continuation.yield(.ownAppBecameActive)
        })
    }

    // MARK: - Helpers

    private func runningApp(from note: Notification) -> ObservedApp? {
        guard let nsApp = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
            return nil
        }
        return observedApp(from: nsApp)
    }

    private func observedApp(from nsApp: NSRunningApplication) -> ObservedApp? {
        guard let bundleID = nsApp.bundleIdentifier else { return nil }
        let name = nsApp.localizedName ?? bundleID
        return ObservedApp(
            pid: nsApp.processIdentifier,
            bundleID: bundleID,
            name: name,
            launchDate: nsApp.launchDate
        )
    }
}
