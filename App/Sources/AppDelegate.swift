import AppCore
import AppKit
import AppShellUI
import MenuBarUI
import OSLog
import Persistence
import SystemBridge

private let logger = Logger(subsystem: "net.scosman.windowcleaner", category: "AppDelegate")

/// The composition root. Creates the Store, ports, and AppCore, then starts
/// the engine. Manages the main window's visibility and the app's activation
/// policy (architecture section 6).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let launchState = LaunchState()

    private var core: AppCore?
    private var statusItemController: StatusItemController?
    private var windowObserver: NSObjectProtocol?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_: Notification) {
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

        // Give AppShellUI access to the core
        launchState.core = appCore

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

        // Start the engine
        Task { @MainActor in
            await appCore.start()

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
        NSApp.setActivationPolicy(.regular)
        launchState.openWindow()
        NSApp.activate()

        // Make the window key on the next main-queue turn
        DispatchQueue.main.async {
            NSApp.windows
                .first { $0.level == .normal && $0.canBecomeKey }?
                .makeKeyAndOrderFront(nil)
        }
    }

    private func checkActivationPolicy() {
        let hasVisibleMainWindow = NSApp.windows.contains { window in
            window.isVisible && window.level == .normal && window.canBecomeKey
        }
        if !hasVisibleMainWindow {
            NSApp.setActivationPolicy(.accessory)
        }
    }

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
