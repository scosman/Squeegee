import Engine
import Foundation

/// An action associated with a menu item, dispatched by the renderer.
public enum MenuAction: Sendable, Equatable {
    /// Open System Settings at Accessibility.
    case openAccessibilitySettings
    /// Resume from pause.
    case resume
    /// Open the Settings window at the given app's rule.
    case openRule(bundleID: String, source: ResolvedRule.Source)
    /// Reopen a closure (document URL or launch app).
    case reopen(ClosureValue)
    /// Pause for one hour.
    case pauseOneHour
    /// Pause until tomorrow.
    case pauseUntilTomorrow
    /// Pause until manually resumed.
    case pauseUntilResumed
    /// Open the Settings window.
    case openSettings
    /// Quit the app.
    case quit
}

/// A single item in the menu.
public struct MenuItem: Sendable, Equatable {
    public let title: String
    public let subtitle: String?
    public let bundleID: String?
    public let action: MenuAction?
    /// Tooltip text shown on hover.
    public let tooltip: String?
    public let isEnabled: Bool
    /// Whether this item shows a checkmark.
    public let isChecked: Bool
    /// When non-nil, the renderer creates a submenu with these items.
    public let submenu: [MenuItem]?
    /// Keyboard shortcut character (e.g. "," for Cmd+,).
    public let keyEquivalent: String?

    public init(
        title: String,
        subtitle: String? = nil,
        bundleID: String? = nil,
        action: MenuAction? = nil,
        tooltip: String? = nil,
        isEnabled: Bool = true,
        isChecked: Bool = false,
        submenu: [MenuItem]? = nil,
        keyEquivalent: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.bundleID = bundleID
        self.action = action
        self.tooltip = tooltip
        self.isEnabled = isEnabled
        self.isChecked = isChecked
        self.submenu = submenu
        self.keyEquivalent = keyEquivalent
    }
}

/// A section of the menu with an optional header.
public struct MenuSection: Sendable, Equatable {
    public let header: String?
    public let items: [MenuItem]

    public init(header: String? = nil, items: [MenuItem]) {
        self.header = header
        self.items = items
    }
}

/// The complete content of the menu bar menu, built as a value tree.
/// `MenuRenderer` (in `MenuBarUI`) converts this to an `NSMenu`.
public struct MenuContent: Sendable, Equatable {
    public let sections: [MenuSection]

    public init(sections: [MenuSection]) {
        self.sections = sections
    }
}
