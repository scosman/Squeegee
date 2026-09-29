import Foundation

// MARK: - Observation values

/// A running application as seen by the system bridge.
public struct ObservedApp: Sendable, Equatable {
    public let pid: Int32
    public let bundleID: String
    public let name: String
    public let launchDate: Date?

    public init(pid: Int32, bundleID: String, name: String, launchDate: Date?) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
        self.launchDate = launchDate
    }
}

/// A window as reported by the Core Graphics window list.
public struct ObservedWindow: Sendable, Equatable {
    public let key: WindowKey
    public let app: ObservedApp
    public let bounds: CGRect
    public let isOnScreen: Bool

    public init(key: WindowKey, app: ObservedApp, bounds: CGRect, isOnScreen: Bool) {
        self.key = key
        self.app = app
        self.bounds = bounds
        self.isOnScreen = isOnScreen
    }

    /// CGRect does not synthesize Equatable conformance in Swift, so we
    /// implement it manually using component-wise comparison.
    public static func == (lhs: ObservedWindow, rhs: ObservedWindow) -> Bool {
        lhs.key == rhs.key &&
            lhs.app == rhs.app &&
            lhs.bounds.origin.x == rhs.bounds.origin.x &&
            lhs.bounds.origin.y == rhs.bounds.origin.y &&
            lhs.bounds.size.width == rhs.bounds.size.width &&
            lhs.bounds.size.height == rhs.bounds.size.height &&
            lhs.isOnScreen == rhs.isOnScreen
    }
}

/// Metadata about a window obtained through the Accessibility framework.
public struct WindowMetadata: Sendable, Equatable {
    /// True when `subrole == AXStandardWindow` and the window has a close button.
    public var isStandard: Bool
    public var title: String?
    public var documentURL: URL?
    public var isMinimized: Bool

    public init(isStandard: Bool, title: String? = nil, documentURL: URL? = nil, isMinimized: Bool = false) {
        self.isStandard = isStandard
        self.title = title
        self.documentURL = documentURL
        self.isMinimized = isMinimized
    }
}

/// The result of inspecting an app's windows through AX.
public enum InspectionResult: Sendable, Equatable {
    /// Windows AX can see now (current Space + minimized), keyed by CGWindowID.
    case inspected([UInt32: WindowMetadata])
    /// AX timeout, cannot complete, or the app is gone.
    case appUnavailable
    /// kAXErrorAPIDisabled: no Accessibility permission.
    case notTrusted
}

/// The result of attempting to close a window through AX.
public enum CloseAttemptResult: Sendable, Equatable {
    /// AXPress delivered. `wasListed` = the window appeared in the AX window list at that moment.
    case pressed(latest: WindowMetadata?, wasListed: Bool)
    /// No AX element for this window (other Space, never seen).
    case unreachable
    /// The window has no close button.
    case noCloseButton
    /// An AX error other than the above.
    case failed(code: Int32)
    /// kAXErrorAPIDisabled: no Accessibility permission.
    case notTrusted
}

// MARK: - Event values

/// An event from NSWorkspace or NSApplication observation.
public enum WorkspaceEvent: Sendable, Equatable {
    case appActivated(ObservedApp)
    case appDeactivated(pid: Int32)
    case appLaunched(ObservedApp)
    case appTerminated(pid: Int32)
    case activeSpaceChanged
    case displaysSlept, displaysWoke
    case sessionResigned, sessionBecameActive
    case ownAppBecameActive
}

/// A focus signal from the AX observer on the frontmost app.
public struct FocusSignal: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case focusMayHaveChanged
        case windowCreated
    }

    public let pid: Int32
    public let kind: Kind
    // swiftlint:disable:next identifier_name
    public let at: Date

    public init(pid: Int32, kind: Kind, at: Date) { // swiftlint:disable:this identifier_name
        self.pid = pid
        self.kind = kind
        self.at = at
    }
}

/// An installed application found by scanning the file system.
public struct InstalledApp: Sendable, Equatable {
    public let bundleID: String
    public let name: String
    public let url: URL

    public init(bundleID: String, name: String, url: URL) {
        self.bundleID = bundleID
        self.name = name
        self.url = url
    }
}
