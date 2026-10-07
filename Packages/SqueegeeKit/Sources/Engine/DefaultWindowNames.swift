import Foundation

/// Provides fallback window names for apps whose windows have no AX title.
///
/// Some macOS apps (System Settings, App Store, etc.) do not set the
/// `kAXTitleAttribute` on their windows. This map supplies a sensible
/// display name keyed by bundle ID. Use `title(for:)` only when the
/// AX-reported title is nil or blank.
public enum DefaultWindowNames {
    /// Bundle ID to default window name.
    private static let map: [String: String] = [
        "com.apple.systempreferences": "System Settings",
        "com.apple.AppStore": "App Store"
    ]

    /// Returns a default window name for the given bundle ID, or nil
    /// if no default is known.
    public static func title(for bundleID: String) -> String? {
        map[bundleID]
    }

    /// Returns the effective window title: the AX title if it is
    /// non-empty after trimming whitespace, otherwise the default
    /// for the bundle ID, otherwise nil.
    public static func effectiveTitle(
        axTitle: String?,
        bundleID: String
    ) -> String? {
        if let trimmed = axTitle?.trimmingCharacters(in: .whitespaces),
           !trimmed.isEmpty
        {
            return trimmed
        }
        return title(for: bundleID)
    }

    /// Returns a guaranteed non-empty display title for a window.
    ///
    /// Fallback chain: stored/AX title → per-bundle default → app name → "Open Window".
    /// Whitespace-only strings are treated as empty at each step.
    public static func displayTitle(
        windowTitle: String?,
        bundleID: String,
        appName: String
    ) -> String {
        if let trimmed = windowTitle?.trimmingCharacters(in: .whitespaces),
           !trimmed.isEmpty
        {
            return trimmed
        }
        if let bundleDefault = title(for: bundleID) {
            return bundleDefault
        }
        let trimmedApp = appName.trimmingCharacters(in: .whitespaces)
        if !trimmedApp.isEmpty {
            return trimmedApp
        }
        return "Open Window"
    }
}
