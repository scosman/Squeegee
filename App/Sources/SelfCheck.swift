import AppKit
import OSLog

#if DEBUG

    /// DEBUG-only self-check diagnostics. Logs verifiable facts at `.info`
    /// with prefix `[selfcheck]` (subsystem `net.scosman.squeegee`).
    /// Compiled out of Release builds.
    @MainActor
    enum SelfCheck {
        private static let logger = Logger(subsystem: "net.scosman.squeegee", category: "SelfCheck")

        // MARK: - Window open diagnostics

        /// Call after a main-window open request. Logs activation state,
        /// policy, frontmost app, and window state. Schedules a follow-up
        /// at +0.5 s.
        static func logWindowOpen(window: NSWindow?, requestTime: CFAbsoluteTime) {
            logWindowState(window: window, label: "immediate", requestTime: requestTime)

            // Follow-up at +0.5 s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                logWindowState(window: window, label: "after-0.5s", requestTime: requestTime)
            }
        }

        private static func logWindowState(window: NSWindow?, label: String, requestTime: CFAbsoluteTime) {
            let elapsed = CFAbsoluteTimeGetCurrent() - requestTime
            let isActive = NSApp.isActive
            let policy = NSApp.activationPolicy()
            let policyStr = switch policy {
            case .regular: "regular"
            case .accessory: "accessory"
            case .prohibited: "prohibited"
            @unknown default: "unknown"
            }
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
            let isKey = window?.isKeyWindow ?? false
            let isMain = window?.isMainWindow ?? false
            let isVisible = window?.isVisible ?? false

            logger.info("""
            [selfcheck] window-open (\(label, privacy: .public)): \
            isActive=\(isActive), \
            policy=\(policyStr, privacy: .public), \
            frontmost=\(frontmost, privacy: .public), \
            isKey=\(isKey), isMain=\(isMain), isVisible=\(isVisible), \
            elapsed=\(String(format: "%.3f", elapsed), privacy: .public)s
            """)
        }

        // MARK: - Remove confirmation diagnostics

        /// Logs whether any NSAlert or panel with an icon is on screen.
        static func logRemoveConfirmation() {
            let alertPanels = NSApp.windows.filter { window in
                // NSAlert panels have a specific class
                let className = String(describing: type(of: window))
                return className.contains("Alert") || (window.isSheet && window.isVisible)
            }

            let sheetWindows = NSApp.windows.filter { $0.isSheet && $0.isVisible }

            logger.info("""
            [selfcheck] remove-confirm: \
            presentation=custom-sheet, \
            alertPanels=\(alertPanels.count), \
            visibleSheets=\(sheetWindows.count), \
            totalWindows=\(NSApp.windows.count)
            """)
        }

        // MARK: - Activation diagnostics

        /// Logs timestamps of each handler during didBecomeActive.
        static func logBecomeActive() {
            let timestamp = CFAbsoluteTimeGetCurrent()
            let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "nil"
            logger.info("""
            [selfcheck] didBecomeActive: \
            timestamp=\(String(format: "%.3f", timestamp), privacy: .public), \
            frontmost=\(frontmost, privacy: .public), \
            isActive=\(NSApp.isActive)
            """)
        }

        // MARK: - Distributed notification triggers

        /// Registers DEBUG-only distributed notification observers that
        /// exercise the same code paths as the menu actions.
        static func registerTriggers(showMainWindow: @escaping @MainActor () -> Void) {
            let center = DistributedNotificationCenter.default()

            // Trigger: "Settings..." action
            center.addObserver(
                forName: .init("net.scosman.squeegee.debug.openSettings"),
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    logger.info("[selfcheck] trigger: openSettings via distributed notification")
                    showMainWindow()
                }
            }

            // Trigger: Remove action (logs only; does not actually remove)
            center.addObserver(
                forName: .init("net.scosman.squeegee.debug.logRemoveConfirm"),
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    logger.info("[selfcheck] trigger: logRemoveConfirm via distributed notification")
                    logRemoveConfirmation()
                }
            }

            logger.info("[selfcheck] DEBUG triggers registered")
        }
    }

#endif
