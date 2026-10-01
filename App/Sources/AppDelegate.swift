import AppCore
import AppKit
import AppShellUI
import MenuBarUI
import OSLog
import Persistence
import SwiftUI
import SystemBridge

private let logger = Logger(subsystem: "net.scosman.windowcleaner", category: "AppDelegate")

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
        let storeURL = appSupportURL()
        let store: Store
        do {
            store = try Store(configuration: .onDisk(storeURL))
        } catch {
            logger.error("Failed to open store: \(error.localizedDescription, privacy: .public)")
            // Architecture section 7: show Quit and Reset Data.
            let alert = NSAlert()
            alert.messageText = "WindowCleaner couldn\u{2019}t open its data."
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Reset Data")
            let response = alert.runModal()
            if response == .alertSecondButtonReturn {
                resetStoreAndRelaunch(at: storeURL)
            }
            NSApp.terminate(nil)
            return
        }

        let ports = LivePorts.make()
        let appCore = AppCore(store: store, ports: ports)
        core = appCore

        // Wire the show-main-window callback
        appCore.showMainWindow = { [weak self] in
            self?.showMainWindow()
        }

        // Create the status item controller (menu bar icon)
        statusItemController = StatusItemController(core: appCore)

        // Observe window close to manage activation policy
        windowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Defer the check to the next run loop turn so the window list
            // is up to date after the close completes.
            DispatchQueue.main.async {
                self?.checkActivationPolicy()
            }
        }

        #if DEBUG
            registerSelfCheckObservers()
        #endif

        // Start the engine
        Task { @MainActor in
            await appCore.start()
            logger.info("AppCore started, onboardingComplete=\(store.settings.onboardingComplete)")

            // If onboarding is not complete, show the main window
            if !store.settings.onboardingComplete {
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

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "WindowCleaner"
        window.contentView = hostingView
        window.center()
        window.contentMinSize = NSSize(width: 640, height: 440)
        // Prevent the system from releasing the window on close; we manage
        // the lifetime ourselves via the mainWindow property.
        window.isReleasedWhenClosed = false

        mainWindow = window
        window.makeKeyAndOrderFront(nil)
        logger.info("Created main window via NSWindow + NSHostingView")
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
        let storeFile = directory.appendingPathComponent("WindowCleaner.store")
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

    // MARK: - Paths

    private func appSupportURL() -> URL {
        let fileManager = FileManager.default
        // Application Support always exists on macOS; a missing result is a programmer error.
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            fatalError("Application Support directory not found")
        }
        let dir = appSupport.appendingPathComponent("WindowCleaner")
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
