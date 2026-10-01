import AppKit
import ApplicationServices
import Engine
import os

/// Implements `AccessibilityPermissionPort` using the AX trust APIs and
/// the undocumented `com.apple.accessibility.api` distributed notification.
public final class LiveAccessibilityPermission: AccessibilityPermissionPort, @unchecked Sendable {
    private static let logger = Logger(
        subsystem: "net.scosman.squeegee",
        category: "Permission"
    )

    private let continuation: AsyncStream<Void>.Continuation
    private let stream: AsyncStream<Void>
    private var token: NSObjectProtocol?

    public init() {
        let (newStream, newContinuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(4))
        stream = newStream
        continuation = newContinuation

        // Observe the undocumented distributed notification for AX trust changes.
        token = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Yield after 0.25 s delay; the trust state can lag the notification.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.continuation.yield(())
            }
        }
    }

    deinit {
        if let token {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        continuation.finish()
    }

    public func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    public func requestPrompt() {
        // The C global `kAXTrustedCheckOptionPrompt` triggers a Swift 6 strict
        // concurrency diagnostic (shared mutable state). The string value is the
        // well-known constant "AXTrustedCheckOptionPrompt".
        let options = ["AXTrustedCheckOptionPrompt" as CFString: true as CFBoolean] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        openSystemSettings()
    }

    public func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    public func changes() -> AsyncStream<Void> {
        stream
    }
}
