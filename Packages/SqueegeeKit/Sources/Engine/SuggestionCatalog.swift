import Foundation

/// The built-in catalog of app suggestions, matched against installed apps
/// during onboarding and from the Settings suggestion sheet.
public struct SuggestionCatalog: Sendable {
    public let entries: [CatalogEntry]

    public init(entries: [CatalogEntry]) {
        self.entries = entries
    }

    /// The default catalog with all known apps (functional spec section 11).
    public static let builtIn = SuggestionCatalog(entries: [
        // Files
        CatalogEntry(bundleID: "com.apple.finder", category: .files, rule: Rule(
            isEnabled: true, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        CatalogEntry(bundleID: "com.apple.Preview", category: .files, rule: Rule(
            isEnabled: true, closeAfter: 12 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),

        // Media
        CatalogEntry(bundleID: "com.apple.Photos", category: .media, rule: Rule(
            isEnabled: true, closeAfter: 2 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        CatalogEntry(bundleID: "com.apple.QuickTimePlayerX", category: .media, rule: Rule(
            isEnabled: true, closeAfter: 2 * 3600, measureFrom: .lastActive, quitPolicy: .always
        )),
        CatalogEntry(bundleID: "org.videolan.vlc", category: .media, rule: Rule(
            isEnabled: true, closeAfter: 2 * 3600, measureFrom: .lastActive, quitPolicy: .always
        )),
        CatalogEntry(bundleID: "com.colliderli.iina", category: .media, rule: Rule(
            isEnabled: true, closeAfter: 2 * 3600, measureFrom: .lastActive, quitPolicy: .always
        )),
        CatalogEntry(bundleID: "com.apple.Music", category: .media, rule: Rule(
            isEnabled: true, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        CatalogEntry(bundleID: "com.spotify.client", category: .media, rule: Rule(
            isEnabled: true, closeAfter: 6 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),

        // Messaging
        CatalogEntry(bundleID: "com.apple.MobileSMS", category: .messaging, rule: Rule(
            isEnabled: true, closeAfter: 4 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        CatalogEntry(bundleID: "com.tinyspeck.slackmacgap", category: .messaging, rule: Rule(
            isEnabled: true, closeAfter: 4 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        CatalogEntry(bundleID: "com.hnc.Discord", category: .messaging, rule: Rule(
            isEnabled: true, closeAfter: 4 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        CatalogEntry(bundleID: "net.whatsapp.WhatsApp", category: .messaging, rule: Rule(
            isEnabled: true, closeAfter: 4 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        CatalogEntry(bundleID: "org.whispersystems.signal-desktop", category: .messaging, rule: Rule(
            isEnabled: true, closeAfter: 4 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        CatalogEntry(bundleID: "ru.keepcoder.Telegram", category: .messaging, rule: Rule(
            isEnabled: true, closeAfter: 4 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),

        // Background apps
        CatalogEntry(bundleID: "com.1password.1password", category: .backgroundApps, rule: Rule(
            isEnabled: true, closeAfter: 1 * 3600, measureFrom: .lastActive, quitPolicy: .never
        )),
        // Granola bundle ID not confirmed; omitted per spec instruction

        // System
        CatalogEntry(bundleID: "com.apple.systempreferences", category: .system, rule: Rule(
            isEnabled: true, closeAfter: 1 * 3600, measureFrom: .lastActive, quitPolicy: .ifClosedBySqueegee
        )),
        CatalogEntry(bundleID: "com.apple.AppStore", category: .system, rule: Rule(
            isEnabled: true, closeAfter: 1 * 3600, measureFrom: .lastActive, quitPolicy: .ifClosedBySqueegee
        )),
        CatalogEntry(bundleID: "com.apple.ActivityMonitor", category: .system, rule: Rule(
            isEnabled: true, closeAfter: 2 * 3600, measureFrom: .lastActive, quitPolicy: .ifClosedBySqueegee
        ))
    ])

    /// Matches catalog entries against installed apps. Returns suggestions in
    /// catalog order within each category, categories in display order.
    ///
    /// - Parameters:
    ///   - installedApps: Apps found on the system.
    ///   - excludingBundleIDs: Bundle IDs to exclude (apps that already have rules).
    public func suggestions(
        installedApps: [InstalledApp],
        excludingBundleIDs: Set<String> = []
    ) -> [Suggestion] {
        let installedByBundleID = Dictionary(
            installedApps.map { ($0.bundleID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return entries.compactMap { entry in
            guard !excludingBundleIDs.contains(entry.bundleID),
                  let installed = installedByBundleID[entry.bundleID]
            else {
                return nil
            }
            return Suggestion(entry: entry, appName: installed.name, appURL: installed.url)
        }
    }
}
