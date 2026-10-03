import AppKit
import CoreServices
import Engine
import Foundation
import os

/// Resolves the folder path shown in a Finder window by querying Finder
/// through Apple Events (NSAppleScript). Requires Automation TCC for Finder
/// — macOS shows a one-time "Squeegee wants to control Finder" dialog.
///
/// Only called at window-close time to minimise overhead.
///
/// ## Threading
///
/// NSAppleScript is not documented as thread-safe. All script execution
/// runs on a dedicated serial DispatchQueue (`appleScriptQueue`) so that:
/// 1. NSAppleScript is never used from the cooperative thread pool.
/// 2. A slow or hung Finder does not block the main thread or starve
///    the cooperative pool — only the dedicated queue waits.
/// Each AppleScript embeds a `with timeout of 5 seconds` block so a
/// hung Finder releases the queue within a bounded time.
public struct LiveFinderFolderResolver: FinderFolderResolving, Sendable {
    private static let logger = Logger(
        subsystem: "net.scosman.squeegee",
        category: "FinderFolderResolver"
    )

    /// Dedicated serial queue for NSAppleScript execution.
    private static let appleScriptQueue = DispatchQueue(
        label: "net.scosman.squeegee.applescript",
        qos: .userInitiated
    )

    /// Timeout in seconds embedded in each AppleScript block.
    private static let scriptTimeoutSeconds = 5

    public init() {}

    public func folderURL(windowTitle: String) async -> URL? {
        let escaped = escapeForAppleScript(windowTitle)

        let source = """
        with timeout of \(Self.scriptTimeoutSeconds) seconds
            tell application "Finder"
                set targetWindows to (every Finder window whose name is "\(escaped)")
                if (count of targetWindows) is 1 then
                    try
                        return POSIX path of (target of item 1 of targetWindows as alias)
                    on error
                        return ""
                    end try
                end if
            end tell
        end timeout
        return ""
        """

        let path = await executeAppleScript(source)
        guard let path, !path.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        Self.logger.info(
            "Resolved Finder folder for window \"\(windowTitle, privacy: .private)\" → \(url.path, privacy: .private)"
        )
        return url
    }

    public func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    public func probePermission() async -> Bool? {
        // Uses AEDeterminePermissionToAutomateTarget — the Apple-sanctioned
        // API for checking and requesting Automation TCC permission. With
        // askUserIfNeeded=true it triggers the system prompt on first use.
        // Must run on the main thread for the prompt to appear.
        await MainActor.run {
            let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.finder")
            guard let aeDesc = target.aeDesc else {
                Self.logger.warning("Failed to create AE target descriptor for Finder")
                return nil
            }
            let status = AEDeterminePermissionToAutomateTarget(
                aeDesc, typeWildCard, typeWildCard, true
            )
            if status == noErr {
                Self.logger.info("Automation permission probe: granted")
                return true
            } else if status == procNotFound {
                Self.logger.info("Automation permission probe: Finder not running (procNotFound)")
                return nil
            } else {
                Self.logger.info(
                    "Automation permission probe: denied (status=\(status, privacy: .public))"
                )
                return false
            }
        }
    }

    // MARK: - Helpers

    /// Escapes a string for embedding in an AppleScript double-quoted string.
    private func escapeForAppleScript(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Runs an AppleScript source string on a dedicated serial queue and
    /// returns the result, or nil on error.
    private func executeAppleScript(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            Self.appleScriptQueue.async {
                guard let script = NSAppleScript(source: source) else {
                    Self.logger.warning("Failed to create NSAppleScript")
                    continuation.resume(returning: nil)
                    return
                }

                var errorInfo: NSDictionary?
                let result = script.executeAndReturnError(&errorInfo)

                if let errorInfo {
                    Self.logger.warning("Finder AppleScript error: \(errorInfo, privacy: .public)")
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: result.stringValue)
            }
        }
    }
}
