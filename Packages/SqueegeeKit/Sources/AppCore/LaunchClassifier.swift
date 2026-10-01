/// Classifies a launch as user-initiated or login-item, and decides
/// whether the main window should open.
///
/// The detection relies on the `keyAELaunchedAsLogInItem` ('lgit')
/// descriptor in the `kAEOpenApplication` Apple event. Whether macOS
/// attaches this descriptor for apps registered via `SMAppService.mainApp`
/// is unverified on all macOS versions — multiple open-source projects
/// report the same gap. The classifier therefore **fails open**: when the
/// descriptor is absent, it treats the launch as user-initiated and shows
/// the window.
///
/// Failure modes:
/// - **False negative** (login launch not detected → window opens):
///   Visible but harmless — the user can close the window.
/// - **False positive** (user launch treated as login → window hidden):
///   The user sees nothing happen — confusing and bad. This direction is
///   avoided by the fail-open default.
public enum LaunchClassifier: Sendable {
    /// The kind of launch that started the process.
    public enum LaunchKind: Sendable, Equatable {
        /// A user opened the app (Dock, Finder, Spotlight, Launchpad,
        /// `open`, Xcode Run).
        case user
        /// The system started the app at login via SMAppService.mainApp.
        case loginItem
    }

    /// Classify a launch from the Apple event's login-item descriptor.
    ///
    /// - Parameter loginItemDescriptorValue: The `booleanValue` of the
    ///   `keyAELaunchedAsLogInItem` descriptor in the `kAEOpenApplication`
    ///   event, or `nil` if the descriptor was absent.
    /// - Returns: `.loginItem` when the descriptor is present and `true`;
    ///   `.user` otherwise (fail-open).
    public static func classify(
        loginItemDescriptorValue: Bool?
    ) -> LaunchKind {
        if loginItemDescriptorValue == true {
            return .loginItem
        }
        return .user
    }

    /// Whether the main window should open for a given launch kind.
    ///
    /// User launches show the window at the current route (Onboarding or
    /// Settings). Login-item launches start silently — menu bar only.
    public static func shouldShowWindow(for kind: LaunchKind) -> Bool {
        kind == .user
    }
}
