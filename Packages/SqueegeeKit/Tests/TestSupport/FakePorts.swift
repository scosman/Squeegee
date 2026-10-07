import Engine
import Foundation

// MARK: - FakeWindowLister

@MainActor
public final class FakeWindowLister: WindowListing, @unchecked Sendable {
    public var windows: [ObservedWindow] = []
    public private(set) var listCallCount = 0

    public init() {}

    public nonisolated func listWindows() async -> [ObservedWindow] {
        await MainActor.run {
            listCallCount += 1
            return windows
        }
    }
}

// MARK: - FakeWindowInspector

@MainActor
public final class FakeWindowInspector: WindowInspecting, @unchecked Sendable {
    /// Scripted inspection results by pid. Return `.appUnavailable` if not set.
    public var inspectionResults: [Int32: InspectionResult] = [:]
    /// Scripted focused window IDs by pid.
    public var focusedWindowIDs: [Int32: UInt32] = [:]
    public private(set) var inspectCallCount = 0
    public private(set) var forgottenPids: [Int32] = []

    public init() {}

    public nonisolated func inspect(pid: Int32) async -> InspectionResult {
        await MainActor.run {
            inspectCallCount += 1
            return inspectionResults[pid] ?? .appUnavailable
        }
    }

    public nonisolated func focusedWindowID(pid: Int32) async -> UInt32? {
        await MainActor.run {
            focusedWindowIDs[pid]
        }
    }

    public nonisolated func forget(pid: Int32) async {
        await MainActor.run {
            forgottenPids.append(pid)
        }
    }
}

// MARK: - FakeWindowCloser

@MainActor
public final class FakeWindowCloser: WindowClosing, @unchecked Sendable {
    /// Scripted close results by WindowKey. Default: `.unreachable`.
    public var closeResults: [WindowKey: CloseAttemptResult] = [:]
    public private(set) var closedKeys: [WindowKey] = []

    public init() {}

    public nonisolated func close(_ key: WindowKey) async -> CloseAttemptResult {
        await MainActor.run {
            closedKeys.append(key)
            return closeResults[key] ?? .unreachable
        }
    }
}

// MARK: - FakeAppTerminator

@MainActor
public final class FakeAppTerminator: AppTerminating, @unchecked Sendable {
    /// Scripted terminate results by pid. Default: `true`.
    public var terminateResults: [Int32: Bool] = [:]
    public private(set) var terminatedPids: [Int32] = []

    public init() {}

    public nonisolated func terminate(pid: Int32) async -> Bool {
        await MainActor.run {
            terminatedPids.append(pid)
            return terminateResults[pid] ?? true
        }
    }
}

// MARK: - FakeWorkspaceEvents

@MainActor
public final class FakeWorkspaceEvents: WorkspaceEventSource, @unchecked Sendable {
    public var frontmost: ObservedApp?
    public var displaysAsleep = false
    private var continuation: AsyncStream<WorkspaceEvent>.Continuation?

    public init() {}

    public nonisolated func events() -> AsyncStream<WorkspaceEvent> {
        // Create the stream on the calling context but store the continuation
        // so tests can send events via MainActor.
        let (stream, cont) = AsyncStream<WorkspaceEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        MainActor.assumeIsolated {
            self.continuation = cont
        }
        return stream
    }

    public nonisolated func frontmostApp() -> ObservedApp? {
        MainActor.assumeIsolated { frontmost }
    }

    public nonisolated func areDisplaysAsleep() -> Bool {
        MainActor.assumeIsolated { displaysAsleep }
    }

    /// Send an event from tests.
    public func send(_ event: WorkspaceEvent) {
        continuation?.yield(event)
    }

    /// Signal the stream is done.
    public func finish() {
        continuation?.finish()
    }
}

// MARK: - FakeFocusObserver

@MainActor
public final class FakeFocusObserver: FocusObserving, @unchecked Sendable {
    public private(set) var observedPid: Int32?
    private var continuation: AsyncStream<FocusSignal>.Continuation?

    public init() {}

    public nonisolated func signals() -> AsyncStream<FocusSignal> {
        let (stream, cont) = AsyncStream<FocusSignal>.makeStream(bufferingPolicy: .bufferingNewest(64))
        MainActor.assumeIsolated {
            self.continuation = cont
        }
        return stream
    }

    public nonisolated func observe(pid: Int32?) async {
        await MainActor.run {
            observedPid = pid
        }
    }

    /// Send a focus signal from tests.
    public func send(_ signal: FocusSignal) {
        continuation?.yield(signal)
    }

    /// Signal the stream is done.
    public func finish() {
        continuation?.finish()
    }
}

// MARK: - FakeAccessibilityPermission

@MainActor
public final class FakeAccessibilityPermission: AccessibilityPermissionPort, @unchecked Sendable {
    public var trusted = true
    public private(set) var promptRequested = false
    public private(set) var settingsOpened = false
    private var continuation: AsyncStream<Void>.Continuation?

    public init() {}

    public nonisolated func isTrusted() -> Bool {
        MainActor.assumeIsolated { trusted }
    }

    public nonisolated func requestPrompt() {
        MainActor.assumeIsolated { promptRequested = true }
    }

    public nonisolated func openSystemSettings() {
        MainActor.assumeIsolated { settingsOpened = true }
    }

    public nonisolated func changes() -> AsyncStream<Void> {
        let (stream, cont) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(4))
        MainActor.assumeIsolated {
            self.continuation = cont
        }
        return stream
    }

    /// Notify that permission may have changed.
    public func notifyChange() {
        continuation?.yield()
    }

    public func finish() {
        continuation?.finish()
    }
}

// MARK: - FakeLoginItem

@MainActor
public final class FakeLoginItem: LoginItemPort, @unchecked Sendable {
    public var enabled = false
    public var shouldThrow = false
    public private(set) var setEnabledCalls: [Bool] = []

    public init() {}

    public nonisolated func isEnabled() async -> Bool {
        await MainActor.run { enabled }
    }

    public nonisolated func setEnabled(_ enabled: Bool) async throws {
        try await MainActor.run {
            setEnabledCalls.append(enabled)
            if shouldThrow {
                throw FakeLoginItemError.testError
            }
            self.enabled = enabled
        }
    }

    public enum FakeLoginItemError: Error {
        case testError
    }
}

// MARK: - FakeInstalledAppScanner

@MainActor
public final class FakeInstalledAppScanner: InstalledAppScanning, @unchecked Sendable {
    public var apps: [InstalledApp] = []

    public init() {}

    public nonisolated func installedApps() async -> [InstalledApp] {
        await MainActor.run { apps }
    }
}

// MARK: - FakeAppOpener

@MainActor
public final class FakeAppOpener: AppOpening, @unchecked Sendable {
    public private(set) var openedURLs: [(url: URL, bundleID: String)] = []
    public private(set) var launchedBundleIDs: [String] = []
    public var existingFiles: Set<URL> = []
    public var shouldThrow = false

    public init() {}

    public nonisolated func open(documentURL: URL, withBundleID bundleID: String) async throws {
        try await MainActor.run {
            if shouldThrow { throw FakeOpenerError.testError }
            openedURLs.append((url: documentURL, bundleID: bundleID))
        }
    }

    public nonisolated func launch(bundleID: String) async throws {
        try await MainActor.run {
            if shouldThrow { throw FakeOpenerError.testError }
            launchedBundleIDs.append(bundleID)
        }
    }

    public nonisolated func fileExists(_ url: URL) async -> Bool {
        await MainActor.run { existingFiles.contains(url) }
    }

    public enum FakeOpenerError: Error {
        case testError
    }
}

// MARK: - FakeFinderFolderResolver

@MainActor
public final class FakeFinderFolderResolver: FinderFolderResolving, @unchecked Sendable {
    /// Scripted folder URLs by window title.
    public var folderURLsByTitle: [String: URL] = [:]
    public private(set) var resolvedTitles: [String] = []
    /// Controls what `probePermission()` returns.
    /// `true` = granted, `false` = denied, `nil` = inconclusive.
    public var permissionGranted: Bool? = true
    public private(set) var probeCount = 0
    public private(set) var automationSettingsOpened = false

    public init() {}

    public nonisolated func folderURL(windowTitle: String) async -> URL? {
        await MainActor.run {
            resolvedTitles.append(windowTitle)
            return folderURLsByTitle[windowTitle]
        }
    }

    public nonisolated func probePermission() async -> Bool? {
        await MainActor.run {
            probeCount += 1
            return permissionGranted
        }
    }

    public nonisolated func openAutomationSettings() {
        MainActor.assumeIsolated { automationSettingsOpened = true }
    }
}

// MARK: - FakePorts builder

/// Bundles all fakes into an `AppCorePorts` for test setup.
@MainActor
public struct FakePortsBundle {
    public let windowLister: FakeWindowLister
    public let windowInspector: FakeWindowInspector
    public let windowCloser: FakeWindowCloser
    public let appTerminator: FakeAppTerminator
    public let workspace: FakeWorkspaceEvents
    public let focus: FakeFocusObserver
    public let permission: FakeAccessibilityPermission
    public let loginItem: FakeLoginItem
    public let installedApps: FakeInstalledAppScanner
    public let opener: FakeAppOpener
    public let finderFolderResolver: FakeFinderFolderResolver
    public let scheduler: FakeScheduler

    public init(now: Date) {
        windowLister = FakeWindowLister()
        windowInspector = FakeWindowInspector()
        windowCloser = FakeWindowCloser()
        appTerminator = FakeAppTerminator()
        workspace = FakeWorkspaceEvents()
        focus = FakeFocusObserver()
        permission = FakeAccessibilityPermission()
        loginItem = FakeLoginItem()
        installedApps = FakeInstalledAppScanner()
        opener = FakeAppOpener()
        finderFolderResolver = FakeFinderFolderResolver()
        scheduler = FakeScheduler(now: now)
    }

    public var ports: AppCorePorts {
        AppCorePorts(
            windowLister: windowLister,
            windowInspector: windowInspector,
            windowCloser: windowCloser,
            appTerminator: appTerminator,
            workspace: workspace,
            focus: focus,
            permission: permission,
            loginItem: loginItem,
            installedApps: installedApps,
            opener: opener,
            finderFolderResolver: finderFolderResolver,
            scheduler: scheduler
        )
    }
}
