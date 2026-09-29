import AppKit
import Engine
import os

/// Scans `/Applications`, `/System/Applications`, `~/Applications`, and
/// running apps to build a list of installed applications.
public struct LiveInstalledAppScanner: InstalledAppScanning, Sendable {
    private static let logger = Logger(
        subsystem: "net.scosman.windowcleaner",
        category: "InstalledAppScanner"
    )

    public init() {}

    public func installedApps() async -> [InstalledApp] {
        await Task.detached {
            Self.scan()
        }.value
    }

    private static func scan() -> [InstalledApp] {
        var seen: [String: InstalledApp] = [:]
        let fileManager = FileManager.default

        // Search directories in priority order (first found wins per bundle ID).
        let searchDirs: [String] = [
            "/Applications",
            "/System/Applications",
            NSHomeDirectory() + "/Applications"
        ]

        for dir in searchDirs {
            let url = URL(fileURLWithPath: dir, isDirectory: true)
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let fileURL as URL in enumerator {
                // Limit depth to 2 (covers Utilities/ and vendor folders).
                let relPath = fileURL.path.dropFirst(url.path.count)
                let depth = relPath.components(separatedBy: "/").count(where: { !$0.isEmpty })
                if depth > 2 {
                    enumerator.skipDescendants()
                    continue
                }

                guard fileURL.pathExtension == "app" else { continue }

                // Do not descend into .app bundles.
                enumerator.skipDescendants()

                guard let bundle = Bundle(url: fileURL),
                      let bundleID = bundle.bundleIdentifier
                else { continue }

                if seen[bundleID] != nil { continue }

                let displayName = fileManager.displayName(atPath: fileURL.path)
                let name = displayName.hasSuffix(".app")
                    ? String(displayName.dropLast(4))
                    : displayName

                seen[bundleID] = InstalledApp(bundleID: bundleID, name: name, url: fileURL)
            }
        }

        // Add running apps that are not already found.
        for nsApp in NSWorkspace.shared.runningApplications {
            guard let bundleID = nsApp.bundleIdentifier,
                  let bundleURL = nsApp.bundleURL,
                  seen[bundleID] == nil
            else { continue }

            let name = nsApp.localizedName ?? bundleID
            seen[bundleID] = InstalledApp(bundleID: bundleID, name: name, url: bundleURL)
        }

        return Array(seen.values).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
