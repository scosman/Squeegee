import Foundation

// MARK: - Window ports

/// Lists all visible windows via the Core Graphics window server.
public protocol WindowListing: Sendable {
    func listWindows() async -> [ObservedWindow]
}

/// Inspects windows of a running app through the Accessibility framework.
public protocol WindowInspecting: Sendable {
    func inspect(pid: Int32) async -> InspectionResult
    func focusedWindowID(pid: Int32) async -> UInt32?
    func forget(pid: Int32) async
}

/// Closes a window through its AX close button.
public protocol WindowClosing: Sendable {
    func close(_ key: WindowKey) async -> CloseAttemptResult
}

/// Sends a normal quit request to a running app.
public protocol AppTerminating: Sendable {
    /// Returns true if the terminate request was delivered.
    func terminate(pid: Int32) async -> Bool
}

// MARK: - Event source ports

/// Streams workspace events from NSWorkspace and NSApplication.
public protocol WorkspaceEventSource: Sendable {
    func events() -> AsyncStream<WorkspaceEvent>
    func frontmostApp() -> ObservedApp?
    func areDisplaysAsleep() -> Bool
}

/// Observes AX focus events for a single app at a time.
public protocol FocusObserving: Sendable {
    func signals() -> AsyncStream<FocusSignal>
    /// Moves the single observer to the given pid. Pass nil to stop observing.
    func observe(pid: Int32?) async
}

// MARK: - Permission and system ports

/// Checks and requests Accessibility permission.
public protocol AccessibilityPermissionPort: Sendable {
    func isTrusted() -> Bool
    /// Shows the system prompt and opens System Settings at Accessibility.
    func requestPrompt()
    func openSystemSettings()
    /// Fires when the system AX trust list may have changed.
    func changes() -> AsyncStream<Void>
}

/// Controls the Launch at Login state via ServiceManagement.
public protocol LoginItemPort: Sendable {
    func isEnabled() -> Bool
    func setEnabled(_ enabled: Bool) throws
}

/// Scans the file system for installed applications.
public protocol InstalledAppScanning: Sendable {
    func installedApps() async -> [InstalledApp]
}

/// Opens files and launches apps through NSWorkspace.
public protocol AppOpening: Sendable {
    func open(documentURL: URL, withBundleID: String) async throws
    /// Activates the app if running, or launches it.
    func launch(bundleID: String) async throws
    func fileExists(_ url: URL) -> Bool
}

/// Resolves the folder URL shown in a Finder window, given the window title.
/// Only called at close time (not during polling) to keep overhead low.
/// The live implementation requires Automation TCC permission for Finder.
public protocol FinderFolderResolving: Sendable {
    /// Returns the file URL of the folder shown in a Finder window with the
    /// given title, or nil if the window cannot be matched unambiguously.
    func folderURL(windowTitle: String) async -> URL?

    /// Sends a trivial Apple Event to Finder to test (and trigger) the
    /// Automation permission prompt. Returns true if permission is granted.
    func probePermission() async -> Bool

    /// Opens System Settings at Privacy & Security > Automation.
    func openAutomationSettings()
}

// MARK: - Scheduling

/// An abstraction for the system clock and timers, enabling deterministic tests.
public protocol AppScheduler: Sendable {
    func now() -> Date

    @MainActor
    func schedule(
        at date: Date,
        tolerance: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any Cancellable

    @MainActor
    func schedule(
        every interval: TimeInterval,
        tolerance: TimeInterval,
        _ action: @escaping @MainActor () -> Void
    ) -> any Cancellable
}

/// A handle that can cancel a scheduled timer.
public protocol Cancellable: Sendable {
    func cancel()
}

// MARK: - Port bag

/// All ports required by AppCore, bundled for injection.
public struct AppCorePorts: Sendable {
    public var windowLister: any WindowListing
    public var windowInspector: any WindowInspecting
    public var windowCloser: any WindowClosing
    public var appTerminator: any AppTerminating
    public var workspace: any WorkspaceEventSource
    public var focus: any FocusObserving
    public var permission: any AccessibilityPermissionPort
    public var loginItem: any LoginItemPort
    public var installedApps: any InstalledAppScanning
    public var opener: any AppOpening
    public var finderFolderResolver: any FinderFolderResolving
    public var scheduler: any AppScheduler

    public init(
        windowLister: any WindowListing,
        windowInspector: any WindowInspecting,
        windowCloser: any WindowClosing,
        appTerminator: any AppTerminating,
        workspace: any WorkspaceEventSource,
        focus: any FocusObserving,
        permission: any AccessibilityPermissionPort,
        loginItem: any LoginItemPort,
        installedApps: any InstalledAppScanning,
        opener: any AppOpening,
        finderFolderResolver: any FinderFolderResolving,
        scheduler: any AppScheduler
    ) {
        self.windowLister = windowLister
        self.windowInspector = windowInspector
        self.windowCloser = windowCloser
        self.appTerminator = appTerminator
        self.workspace = workspace
        self.focus = focus
        self.permission = permission
        self.loginItem = loginItem
        self.installedApps = installedApps
        self.opener = opener
        self.finderFolderResolver = finderFolderResolver
        self.scheduler = scheduler
    }
}
