import AppKit
import Engine
import Foundation
import ManualTestKit
import SystemBridge

/// Replaces placeholder closures in ManualTestKit scripts with real SystemBridge calls.
enum WiredScripts {
    /// Returns wired copies of all canonical scripts, ready for the runner.
    static func all() -> [TestScript] {
        allScripts.map { wire($0) }
    }

    private static func wire(_ script: TestScript) -> TestScript {
        TestScript(
            id: script.id,
            title: script.title,
            steps: script.steps.map { wireStep($0) }
        )
    }

    // MARK: - Step wiring dispatch

    private static func wireStep(_ step: TestStep) -> TestStep {
        switch step {
        case let .autoCheck(id, _, _) where id == "sb_bridge_available":
            wireSetupBridgeCheck(step)
        case let .action(id, _, _) where id == "sb_permission_prompt_action":
            wireSetupPermissionPrompt(step)
        case let .action(id, _, _) where id == "sb_close_standard_action":
            wireCloseStandard(step)
        case let .action(id, _, _) where id == "sb_reopen_action":
            wireReopen(step)
        case let .action(id, _, _) where id == "sb_quit_normal_action":
            wireQuitNormal(step)
        case let .action(id, _, _) where id == "sb_login_item_action":
            wireLoginItem(step)
        case let .autoCheck(id, _, _) where id == "sb_installed_apps_check":
            wireInstalledAppsCheck(step)
        default:
            step
        }
    }

    // MARK: - Setup wiring

    private static func wireSetupBridgeCheck(_ step: TestStep) -> TestStep {
        guard case let .autoCheck(id, label, _) = step else { return step }
        return .autoCheck(id: id, label: label) {
            let available = AXWindowService.isBridgeAvailable
            let version = ProcessInfo.processInfo.operatingSystemVersionString
            return CheckOutcome(
                passed: available,
                detail: "Bridge available: \(available), macOS \(version)"
            )
        }
    }

    private static func wireSetupPermissionPrompt(_ step: TestStep) -> TestStep {
        guard case let .action(id, label, _) = step else { return step }
        return .action(id: id, label: label) { status in
            let perm = LiveAccessibilityPermission()
            status("Requesting accessibility permission prompt...")
            perm.requestPrompt()
            status("Prompt requested. Check System Settings.")
        }
    }

    // MARK: - Close wiring

    private static func wireCloseStandard(_ step: TestStep) -> TestStep {
        guard case let .action(id, label, _) = step else { return step }
        return .action(id: id, label: label) { status in
            status("Finding a standard Finder window to close...")
            let axService = AXWindowService()
            let lister = CGWindowLister()
            let windows = await lister.listWindows()
            await axService.updateBounds(windows)

            guard let target = windows.first(where: {
                $0.app.bundleID == "com.apple.finder"
            }) else {
                status("No Finder window found. Open a Finder window and try again.")
                return
            }

            status("Closing Finder wid \(target.key.windowID) (pid \(target.key.pid))...")
            let result = await axService.close(target.key)
            status("Close result: \(result)")
        }
    }

    // MARK: - URL wiring

    private static func wireReopen(_ step: TestStep) -> TestStep {
        guard case let .action(id, label, _) = step else { return step }
        return .action(id: id, label: label) { status in
            let entries = await CapturedCloseStore.shared.drainAll()
            guard !entries.isEmpty else {
                status("No captured closes. Close windows from the Live Inspector first.")
                return
            }
            let opener = LiveAppOpener()
            status("Reopening \(entries.count) captured document(s)...")
            for entry in entries {
                do {
                    try await opener.open(
                        documentURL: entry.documentURL,
                        withBundleID: entry.bundleID
                    )
                    status("Reopened \(entry.documentURL.lastPathComponent) in \(entry.bundleID)")
                } catch {
                    status("Failed to reopen \(entry.documentURL.lastPathComponent): \(error)")
                }
            }
            status("Done. \(entries.count) document(s) reopened.")
        }
    }

    // MARK: - Quit wiring

    private static func wireQuitNormal(_ step: TestStep) -> TestStep {
        guard case let .action(id, label, _) = step else { return step }
        return .action(id: id, label: label) { status in
            let qtBundleID = "com.apple.QuickTimePlayerX"
            let terminator = LiveAppTerminator()

            // Look up by running applications so it works even with no windows.
            let runningApps = await MainActor.run {
                NSWorkspace.shared.runningApplications
            }
            guard let nsApp = runningApps.first(where: {
                $0.bundleIdentifier == qtBundleID
            }) else {
                status("QuickTime Player is not running. Launching it...")
                let opener = LiveAppOpener()
                do {
                    try await opener.launch(bundleID: qtBundleID)
                    status("Launched QuickTime Player. Wait a moment, then run again.")
                } catch {
                    status("Could not launch QuickTime Player: \(error)")
                }
                return
            }

            let pid = nsApp.processIdentifier
            let delivered = await terminator.terminate(pid: pid)
            status(
                "Terminate sent to QuickTime Player (pid \(pid)): "
                    + "\(delivered ? "delivered" : "failed")"
            )
        }
    }

    // MARK: - Login Item wiring

    private static func wireLoginItem(_ step: TestStep) -> TestStep {
        guard case let .action(id, label, _) = step else { return step }
        return .action(id: id, label: label) { status in
            let loginItem = LiveLoginItem()
            do {
                try await loginItem.setEnabled(true)
                let enabled = await loginItem.isEnabled()
                status("Login item enabled: \(enabled). Check System Settings > General > Login Items.")
            } catch {
                status("Failed to enable login item: \(error)")
            }
        }
    }

    // MARK: - Scan wiring

    private static func wireInstalledAppsCheck(_ step: TestStep) -> TestStep {
        guard case let .autoCheck(id, label, _) = step else { return step }
        return .autoCheck(id: id, label: label) {
            let scanner = LiveInstalledAppScanner()
            let apps = await scanner.installedApps()
            let hasFinder = apps.contains { $0.bundleID == "com.apple.finder" }
            let hasPreview = apps.contains { $0.bundleID == "com.apple.Preview" }
            let passed = hasFinder && hasPreview
            let summary = "Found \(apps.count) apps. "
                + "Finder: \(hasFinder ? "yes" : "NO"), "
                + "Preview: \(hasPreview ? "yes" : "NO")"

            let sorted = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let listing = sorted.map { "\($0.name) — \($0.bundleID)" }.joined(separator: "\n")
            let detail = summary + "\n\n" + listing
            return CheckOutcome(passed: passed, detail: detail)
        }
    }
}
