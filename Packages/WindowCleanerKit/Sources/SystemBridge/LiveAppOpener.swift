import AppKit
import Engine
import os

/// Opens documents in their apps and launches apps through NSWorkspace.
public struct LiveAppOpener: AppOpening, Sendable {
    private static let logger = Logger(
        subsystem: "net.scosman.windowcleaner",
        category: "AppOpener"
    )

    public init() {}

    public func open(documentURL: URL, withBundleID bundleID: String) async throws {
        guard let appURL = appURL(for: bundleID) else {
            throw OpenError.appNotFound(bundleID)
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        try await NSWorkspace.shared.open(
            [documentURL],
            withApplicationAt: appURL,
            configuration: config
        )
    }

    public func launch(bundleID: String) async throws {
        guard let appURL = appURL(for: bundleID) else {
            throw OpenError.appNotFound(bundleID)
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        try await NSWorkspace.shared.openApplication(
            at: appURL,
            configuration: config
        )
    }

    public func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private func appURL(for bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }
}

/// Errors from `LiveAppOpener`.
public enum OpenError: Error, LocalizedError {
    case appNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .appNotFound(id):
            "Application with bundle ID \(id) not found"
        }
    }
}
