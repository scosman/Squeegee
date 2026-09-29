import AppKit
import CoreGraphics
import Engine
import os

/// Lists all windows via the Core Graphics window server.
///
/// The heavy lift (`CGWindowListCopyWindowInfo`) runs on a detached task.
/// Parsing is a pure static function, unit-tested with fixture dictionaries.
public struct CGWindowLister: WindowListing, Sendable {
    private static let logger = Logger(
        subsystem: "net.scosman.windowcleaner",
        category: "CGWindowLister"
    )

    /// Bundle IDs that are always excluded from window listing.
    public static let excludedBundleIDs: Set<String> = [
        "com.apple.dock",
        "com.apple.WindowManager",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.systemuiserver",
        "com.apple.loginwindow",
        "com.apple.Spotlight",
        "com.apple.screencaptureui",
        "com.apple.ScreenContinuity"
    ]

    private let ownPID: Int32

    public init(ownPID: Int32 = ProcessInfo.processInfo.processIdentifier) {
        self.ownPID = ownPID
    }

    public func listWindows() async -> [ObservedWindow] {
        let pid = ownPID
        return await Task.detached {
            guard let infos = CGWindowListCopyWindowInfo(
                [.optionAll, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]] else {
                Self.logger.warning("CGWindowListCopyWindowInfo returned nil")
                return [ObservedWindow]()
            }
            return Self.parse(infos, ownPID: pid) { queryPID in
                Self.lookupApp(pid: queryPID)
            }
        }.value
    }

    // MARK: - Pure parsing

    /// Parses raw CG window info dictionaries into `ObservedWindow` values.
    ///
    /// Keeps a window only when all filter criteria pass:
    /// 1. Layer == 0
    /// 2. Alpha > 0
    /// 3. Not our own pid
    /// 4. Width >= 40 and height >= 40
    /// 5. `appLookup` returns an app with a bundle ID
    /// 6. Bundle ID not in `excludedBundleIDs` and not a WindowCleaner bundle
    public static func parse(
        _ infos: [[String: Any]],
        ownPID: Int32,
        appLookup: (Int32) -> ObservedApp?
    ) -> [ObservedWindow] {
        var appCache: [Int32: ObservedApp?] = [:]
        var result: [ObservedWindow] = []

        for info in infos {
            guard let parsed = parseOneWindow(info, ownPID: ownPID, appCache: &appCache, appLookup: appLookup) else {
                continue
            }
            result.append(parsed)
        }

        return result
    }

    private static func parseOneWindow(
        _ info: [String: Any],
        ownPID: Int32,
        appCache: inout [Int32: ObservedApp?],
        appLookup: (Int32) -> ObservedApp?
    ) -> ObservedWindow? {
        // Filter: layer must be 0
        guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { return nil }
        // Filter: alpha must be > 0
        guard let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0 else { return nil }
        // Filter: not our own pid
        guard let pid = info[kCGWindowOwnerPID as String] as? Int32, pid != ownPID else { return nil }
        // Filter: minimum size (40x40)
        guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
              bounds.width >= 40, bounds.height >= 40
        else { return nil }

        // Filter: must have an app with a bundle ID, and not excluded
        guard let app = resolveApp(pid: pid, appCache: &appCache, appLookup: appLookup) else { return nil }

        guard let windowID = info[kCGWindowNumber as String] as? UInt32 else { return nil }

        // kCGWindowName is never read (requires Screen Recording)
        let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false

        let key = WindowKey(pid: pid, windowID: windowID)
        return ObservedWindow(key: key, app: app, bounds: bounds, isOnScreen: isOnScreen)
    }

    /// Resolves an app from the cache or lookup, filtering out excluded bundle IDs.
    private static func resolveApp(
        pid: Int32,
        appCache: inout [Int32: ObservedApp?],
        appLookup: (Int32) -> ObservedApp?
    ) -> ObservedApp? {
        let app: ObservedApp
        if let cached = appCache[pid] {
            guard let cachedApp = cached else { return nil }
            app = cachedApp
        } else {
            let looked = appLookup(pid)
            appCache[pid] = looked
            guard let looked else { return nil }
            app = looked
        }

        if excludedBundleIDs.contains(app.bundleID) { return nil }
        if app.bundleID.hasPrefix("net.scosman.windowcleaner") { return nil }
        return app
    }

    // MARK: - App lookup

    /// Builds an `ObservedApp` from a running process, or nil if the process has
    /// no bundle ID or its activation policy is `.prohibited`.
    static func lookupApp(pid: Int32) -> ObservedApp? {
        guard let nsApp = NSRunningApplication(processIdentifier: pid) else { return nil }
        guard let bundleID = nsApp.bundleIdentifier else { return nil }
        guard nsApp.activationPolicy != .prohibited else { return nil }

        let name = nsApp.localizedName ?? bundleID
        return ObservedApp(
            pid: pid,
            bundleID: bundleID,
            name: name,
            launchDate: nsApp.launchDate
        )
    }
}
