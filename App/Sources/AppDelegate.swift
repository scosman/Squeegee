import AppCore
import AppKit
import AppShellUI
import MenuBarUI
import OSLog
import Persistence
import SwiftUI
import SystemBridge

private let logger = Logger(subsystem: "net.scosman.squeegee", category: "AppDelegate")

/// Reads the `keyAELaunchedAsLogInItem` ('lgit') descriptor from the
/// current `kAEOpenApplication` Apple event.
///
/// Must be called during `applicationDidFinishLaunching` — the event is
/// only accessible synchronously within AppKit's launch notifications.
/// Returns `nil` when the descriptor is absent. See `LaunchClassifier`
/// for how that maps to a launch kind.
private func readLoginItemDescriptor() -> Bool? {
    guard let event = NSAppleEventManager.shared().currentAppleEvent else {
        return nil
    }
    return event.paramDescriptor(
        forKeyword: AEKeyword(keyAELaunchedAsLogInItem)
    )?.booleanValue
}

/// The composition root. Creates the Store, ports, and AppCore, then starts
/// the engine. Manages the main window's visibility and the app's activation
/// policy (architecture section 6).
///
/// The main window is an `NSWindow` hosting `MainWindowRootView` in an
/// `NSHostingView`. A SwiftUI `Window` scene with
/// `.defaultLaunchBehavior(.suppressed)` never instantiates its content, so
/// `OpenWindowAction` is never captured. The NSWindow path is therefore the
/// single canonical window path — there is no fallback or scene-based
/// alternative.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var core: AppCore?
    private var statusItemController: StatusItemController?
    private var windowObserver: NSObjectProtocol?
    /// The one main window managed by AppDelegate.
    private var mainWindow: NSWindow?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
        logger.info("applicationDidFinishLaunching")

        guard let store = openStoreOrTerminate() else { return }

        let ports = LivePorts.make()
        let appCore = AppCore(store: store, ports: ports)
        core = appCore

        appCore.showMainWindow = { [weak self] in
            self?.showMainWindow()
        }
        statusItemController = StatusItemController(core: appCore)
        observeWindowClose()

        #if DEBUG
            registerSelfCheckObservers()
        #endif

        // Classify this launch before starting the engine; the Apple
        // event descriptor is only valid during applicationDidFinishLaunching.
        let descriptorValue = readLoginItemDescriptor()
        let launchKind = LaunchClassifier.classify(
            loginItemDescriptorValue: descriptorValue
        )
        let kindLabel = launchKind == .user ? "user" : "loginItem"
        let descriptorLabel = descriptorValue.map { String($0) } ?? "nil"
        logger.info(
            "Launch classified: kind=\(kindLabel, privacy: .public), descriptor=\(descriptorLabel, privacy: .public)"
        )

        // Start the engine
        Task { @MainActor in
            await appCore.start()
            logger.info("AppCore started, onboardingComplete=\(store.settings.onboardingComplete)")

            // User-initiated launches (Dock, Finder, Spotlight, Xcode Run)
            // open the main window at the current route. Login-item launches
            // (SMAppService.mainApp at login) start silently — menu bar only.
            if !isProfilingMode, LaunchClassifier.shouldShowWindow(for: launchKind) {
                showMainWindow()
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        showMainWindow()
        return false
    }

    func applicationWillTerminate(_: Notification) {
        core?.prepareForTermination()
    }

    // MARK: - Launch helpers

    /// Opens the store, or shows an error alert and terminates.
    /// Returns `nil` when the app is about to terminate (architecture section 7).
    private func openStoreOrTerminate() -> Store? {
        let storeURL = profilingStoreURL() ?? appSupportURL()
        do {
            return try Store(configuration: .onDisk(storeURL))
        } catch {
            logger.error("Failed to open store: \(error.localizedDescription, privacy: .public)")
            let alert = NSAlert()
            alert.messageText = "Squeegee couldn\u{2019}t open its data."
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Reset Data")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                resetStoreAndRelaunch(at: storeURL)
            }
            NSApp.terminate(nil)
            return nil
        }
    }

    /// Observes window close to switch the activation policy back to accessory.
    private func observeWindowClose() {
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkActivationPolicy()
            }
        }
    }

    // MARK: - Window management

    private func showMainWindow() {
        logger.info("showMainWindow called")
        #if DEBUG
            let requestTime = CFAbsoluteTimeGetCurrent()
        #endif

        NSApp.setActivationPolicy(.regular)

        ensureMainWindow()

        // Defer activation to the next run-loop turn so it happens after
        // any menu tracking or status-item event handling completes.
        // Use activate(ignoringOtherApps:) because the cooperative
        // NSApp.activate() is advisory and routinely refused for
        // accessory (menu-bar) apps that are not the active app.
        DispatchQueue.main.async { [weak self] in
            NSApp.activate(ignoringOtherApps: true)
            self?.mainWindow?.makeKeyAndOrderFront(nil)

            #if DEBUG
                SelfCheck.logWindowOpen(window: self?.mainWindow, requestTime: requestTime)
            #endif
        }
    }

    /// Creates the main window if it does not exist, or orders it front.
    private func ensureMainWindow() {
        if let existing = mainWindow {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        guard let appCore = core else {
            logger.error("ensureMainWindow called before AppCore is ready")
            return
        }

        let rootView = MainWindowRootView(core: appCore)
        let hostingView = NSHostingView(rootView: rootView)
        // Block SwiftUI from bridging its toolbar into the window.
        // NavigationSplitView adds a sidebar toggle button through
        // toolbar bridging; this removes the button deterministically.
        // An AppKit-owned empty NSToolbar (below) keeps the unified
        // toolbar-area visual.
        hostingView.sceneBridgingOptions = []

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Squeegee"
        window.contentView = hostingView
        window.center()
        window.contentMinSize = NSSize(width: 640, height: 440)
        // Prevent the system from releasing the window on close; we manage
        // the lifetime ourselves via the mainWindow property.
        window.isReleasedWhenClosed = false

        // Install an empty AppKit-owned NSToolbar so the window keeps
        // its unified toolbar visual (title in the toolbar row) without
        // any sidebar toggle button.
        let toolbar = NSToolbar(identifier: "MainWindowToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        logger.info("Created main window via NSWindow + NSHostingView")
    }

    // MARK: - Sidebar collapse prevention

    /// Intercepts the View > Toggle Sidebar (Ctrl-Cmd-S) action.
    /// The sidebar must always be visible; this blocks the action at
    /// the end of the responder chain as a safety net alongside
    /// `columnVisibility: .constant(.all)` in SettingsRootView.
    @objc func toggleSidebar(_: Any?) {
        logger.info("toggleSidebar: action blocked")
    }

    private func checkActivationPolicy() {
        let hasVisibleMainWindow = NSApp.windows.contains { window in
            window.isVisible && window.level == .normal && window.canBecomeKey
        }
        if !hasVisibleMainWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: - Self-check (DEBUG only)

    #if DEBUG
        private func registerSelfCheckObservers() {
            SelfCheck.registerTriggers { [weak self] in
                self?.showMainWindow()
            }

            NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    SelfCheck.logBecomeActive()
                }
            }
        }
    #endif

    // MARK: - Store recovery

    /// Deletes the store files and relaunches the app (architecture section 7).
    private func resetStoreAndRelaunch(at directory: URL) {
        let storeFile = directory.appendingPathComponent("Squeegee.store")
        let fileManager = FileManager.default
        // SwiftData may create .store, .store-shm, .store-wal
        for suffix in ["", "-shm", "-wal"] {
            let path = storeFile.path + suffix
            try? fileManager.removeItem(atPath: path)
        }
        // Relaunch via NSTask-style open
        let executableURL = Bundle.main.bundleURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", executableURL.path]
        try? process.run()
    }

    // MARK: - Profiling store

    /// Returns a store directory when `--profiling-store <dir>` is passed, nil otherwise.
    private func profilingStoreURL() -> URL? {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--profiling-store"),
              flagIndex + 1 < args.count
        else {
            return nil
        }
        let dir = URL(fileURLWithPath: args[flagIndex + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        logger.info("Profiling mode: store at \(dir.path, privacy: .public)")
        return dir
    }

    /// True when the app was launched with `--profiling-store <dir>`.
    private var isProfilingMode: Bool {
        let args = ProcessInfo.processInfo.arguments
        guard let flagIndex = args.firstIndex(of: "--profiling-store") else {
            return false
        }
        return flagIndex + 1 < args.count
    }

    // MARK: - Paths

    private func appSupportURL() -> URL {
        let fileManager = FileManager.default
        // Application Support always exists on macOS; a missing result is a programmer error.
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found")
        }
        let dir = appSupport.appendingPathComponent("Squeegee")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
