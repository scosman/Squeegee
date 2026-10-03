import Engine

/// Factory for all live system-bridge port implementations.
public enum LivePorts {
    /// Creates an `AppCorePorts` bag with all live implementations.
    @MainActor
    public static func make() -> AppCorePorts {
        let axService = AXWindowService()
        return AppCorePorts(
            windowLister: CGWindowLister(),
            windowInspector: axService,
            windowCloser: axService,
            appTerminator: LiveAppTerminator(),
            workspace: LiveWorkspaceEvents(),
            focus: FrontmostFocusObserver(),
            permission: LiveAccessibilityPermission(),
            loginItem: LiveLoginItem(),
            installedApps: LiveInstalledAppScanner(),
            opener: LiveAppOpener(),
            finderFolderResolver: LiveFinderFolderResolver(),
            scheduler: LiveAppScheduler()
        )
    }
}
