import Foundation

// MARK: - Close state

/// Tracks the lifecycle of a close attempt on a single window.
public enum CloseState: Sendable, Equatable {
    /// Eligible for closing (no pending attempt).
    case none
    /// AXPress delivered; waiting for verification.
    /// `wasListed` records whether the window appeared in the AX window list at close time.
    case sent(at: Date, wasListed: Bool) // swiftlint:disable:this identifier_name
    /// App kept the window (save dialog, etc.); no retry until active again.
    case declined(at: Date) // swiftlint:disable:this identifier_name
    /// No AX element or press on another Space did nothing; retry when AX lists it.
    case unreachable(since: Date)
}

// MARK: - Tracked window

/// A window being tracked by the engine.
public struct TrackedWindow: Sendable, Equatable {
    public let key: WindowKey
    public var bundleID: String
    public var appName: String
    public var firstSeen: Date
    /// End time of the most recent qualifying focus session.
    public var lastActive: Date?
    /// Nil until an AX inspection lists this window.
    public var metadata: WindowMetadata?
    public var closeState: CloseState

    public init(
        key: WindowKey,
        bundleID: String,
        appName: String,
        firstSeen: Date,
        lastActive: Date? = nil,
        metadata: WindowMetadata? = nil,
        closeState: CloseState = .none
    ) {
        self.key = key
        self.bundleID = bundleID
        self.appName = appName
        self.firstSeen = firstSeen
        self.lastActive = lastActive
        self.metadata = metadata
        self.closeState = closeState
    }
}

// MARK: - Quit state

/// Tracks the lifecycle of a quit attempt on an app.
public enum QuitState: Sendable, Equatable {
    case none
    case sent(at: Date) // swiftlint:disable:this identifier_name
    case declined
}

// MARK: - Tracked app

/// An app being tracked by the engine.
public struct TrackedApp: Sendable, Equatable {
    public let pid: Int32
    public var bundleID: String
    public var appName: String
    public var launchDate: Date?
    /// True once any window with `metadata.isStandard == true` was seen.
    public var hadStandardWindow: Bool
    /// Set when the present-window count drops to 0 (only if hadStandardWindow).
    public var noStandardWindowsSince: Date?
    /// Set when a Squeegee close emptied the app.
    public var quitAfterSqueegeeClose: Bool
    public var quitState: QuitState

    public init(
        pid: Int32,
        bundleID: String,
        appName: String,
        launchDate: Date? = nil,
        hadStandardWindow: Bool = false,
        noStandardWindowsSince: Date? = nil,
        quitAfterSqueegeeClose: Bool = false,
        quitState: QuitState = .none
    ) {
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
        self.launchDate = launchDate
        self.hadStandardWindow = hadStandardWindow
        self.noStandardWindowsSince = noStandardWindowsSince
        self.quitAfterSqueegeeClose = quitAfterSqueegeeClose
        self.quitState = quitState
    }
}

// MARK: - Focus session

/// Measures the time one window is focused while displays are awake.
public struct FocusSession: Sendable, Equatable {
    public let key: WindowKey
    public let start: Date

    public init(key: WindowKey, start: Date) {
        self.key = key
        self.start = start
    }
}

// MARK: - Tracker state

/// The full mutable state of the window tracker.
public struct TrackerState: Sendable, Equatable {
    public var windows: [WindowKey: TrackedWindow] = [:]
    public var apps: [Int32: TrackedApp] = [:]
    public var frontmostPID: Int32?
    /// Focused window of the frontmost app (kept during display sleep).
    public var focusedKey: WindowKey?
    /// Activity measurement; nil while displays sleep.
    public var session: FocusSession?

    public init() {}
}

// MARK: - Tracker event

// swiftlint:disable identifier_name
/// An event that the tracker reducer processes to update state.
public enum TrackerEvent: Sendable, Equatable {
    case windowList([ObservedWindow], at: Date)
    case inspected(pid: Int32, InspectionResult, at: Date)
    case focusChanged(app: ObservedApp?, windowID: UInt32?, at: Date)
    case displaysSlept(at: Date)
    case appTerminated(pid: Int32, at: Date)
    case closeSent(WindowKey, wasListed: Bool, latest: WindowMetadata?, at: Date)
    case closeUnreachable(WindowKey, at: Date)
    case closeFailed(WindowKey, at: Date)
    case closeHasNoButton(WindowKey)
    case closeVerification(WindowKey, at: Date)
    case quitSent(pid: Int32, at: Date)
    case quitVerification(pid: Int32, at: Date)
}

// swiftlint:enable identifier_name

// MARK: - Tracker output

// swiftlint:disable identifier_name
/// Side effects the reducer asks the caller (AppCore) to perform.
public enum TrackerOutput: Sendable, Equatable {
    case windowClosedBySqueegee(TrackedWindow, at: Date)
    case appQuitBySqueegee(TrackedApp, at: Date)
    case needsInspection(pid: Int32)
    case permissionLost
}

// swiftlint:enable identifier_name

// MARK: - Closure value

/// A record of a window closure or app quit performed by Squeegee.
public struct ClosureValue: Sendable, Equatable {
    public let bundleID: String
    public let appName: String
    public let windowTitle: String?
    public let documentURL: URL?
    public let kind: Kind
    public let closedAt: Date

    public enum Kind: String, Sendable, Equatable, Codable {
        case windowClosed
        case appQuit
    }

    public init(
        bundleID: String,
        appName: String,
        windowTitle: String?,
        documentURL: URL?,
        kind: Kind,
        closedAt: Date
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.windowTitle = windowTitle
        self.documentURL = documentURL
        self.kind = kind
        self.closedAt = closedAt
    }
}

// MARK: - Constants

/// Engine-wide constants for timing thresholds.
public enum Tracker {
    /// A focus session must last this many seconds to qualify and update `lastActive`.
    public static let focusQualifyingDuration: TimeInterval = 5
    /// Seconds after the last standard window is gone before an "Always" quit fires.
    public static let alwaysQuitGrace: TimeInterval = 60
    /// Seconds after a closeSent before verification checks the result.
    public static let closeVerificationDelay: TimeInterval = 10
    /// Seconds after a quitSent before verification checks the result.
    public static let quitVerificationDelay: TimeInterval = 30
}
