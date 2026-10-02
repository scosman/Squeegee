import Engine
import OSLog

/// Points-of-Interest signposts for profiling. Near-zero cost when not recorded.
/// Metadata must never include window titles or document paths.
enum Signposts {
    static let signposter = OSSignposter(
        logHandle: OSLog(subsystem: "net.scosman.squeegee", category: .pointsOfInterest)
    )
}

// MARK: - TrackerEvent label

extension TrackerEvent {
    var signpostLabel: String {
        switch self {
        case .windowList: "windowList"
        case .inspected: "inspected"
        case .focusChanged: "focusChanged"
        case .displaysSlept: "displaysSlept"
        case .appTerminated: "appTerminated"
        case .closeSent: "closeSent"
        case .closeUnreachable: "closeUnreachable"
        case .closeFailed: "closeFailed"
        case .closeHasNoButton: "closeHasNoButton"
        case .closeVerification: "closeVerification"
        case .quitSent: "quitSent"
        case .quitVerification: "quitVerification"
        case .restore: "restore"
        }
    }
}

// MARK: - WorkspaceEvent label

extension WorkspaceEvent {
    var signpostLabel: String {
        switch self {
        case .appActivated: "appActivated"
        case .appDeactivated: "appDeactivated"
        case .appLaunched: "appLaunched"
        case .appTerminated: "appTerminated"
        case .activeSpaceChanged: "activeSpaceChanged"
        case .displaysSlept: "displaysSlept"
        case .sessionResigned: "sessionResigned"
        case .displaysWoke: "displaysWoke"
        case .sessionBecameActive: "sessionBecameActive"
        case .ownAppBecameActive: "ownAppBecameActive"
        }
    }
}

// MARK: - FocusSignal.Kind label

extension FocusSignal.Kind {
    var signpostLabel: String {
        switch self {
        case .focusMayHaveChanged: "focusMayHaveChanged"
        case .windowCreated: "windowCreated"
        }
    }
}
