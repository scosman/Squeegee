import Foundation
import SwiftData

/// Third versioned schema for Squeegee persistence.
/// Adds `finderRestoreEnabled` to AppSettingsRecord for the Finder window
/// restore opt-in feature.
public enum SqueegeeSchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)

    public static var models: [any PersistentModel.Type] {
        [
            AppRuleRecord.self,
            AppSettingsRecord.self,
            ClosureRecord.self
        ]
    }

    // MARK: - App rule (unchanged from V2)

    @Model
    public final class AppRuleRecord {
        @Attribute(.unique)
        public var bundleID: String
        public var appName: String
        public var isEnabled: Bool
        public var closeAfterSeconds: Int
        public var measureFromRaw: String
        public var quitPolicyRaw: String
        public var createdAt: Date

        public init(
            bundleID: String,
            appName: String,
            isEnabled: Bool,
            closeAfterSeconds: Int,
            measureFromRaw: String,
            quitPolicyRaw: String,
            createdAt: Date = Date()
        ) {
            self.bundleID = bundleID
            self.appName = appName
            self.isEnabled = isEnabled
            self.closeAfterSeconds = closeAfterSeconds
            self.measureFromRaw = measureFromRaw
            self.quitPolicyRaw = quitPolicyRaw
            self.createdAt = createdAt
        }
    }

    // MARK: - App settings (singleton row)

    @Model
    public final class AppSettingsRecord {
        public var globalIsEnabled: Bool
        public var globalCloseAfterSeconds: Int
        public var globalMeasureFromRaw: String
        public var onboardingComplete: Bool
        public var showMenuBarIcon: Bool
        /// When true, Squeegee resolves the Finder folder path at close time
        /// and reopens the window to the same folder. Requires Automation TCC.
        /// Optional so lightweight migration from V2 can add the column.
        public var finderRestoreEnabled: Bool?
        public var pauseModeRaw: String?
        public var pausedUntil: Date?
        public var lastSettingsSelection: String?
        /// Incremented on rule insert/delete so `withObservationTracking` on
        /// `ruleSet()` fires. SwiftData context fetches are not observation-tracked,
        /// but reading this `@Model` property is.
        public var ruleVersion: Int

        public init() {
            globalIsEnabled = false
            globalCloseAfterSeconds = 21600
            globalMeasureFromRaw = "lastActive"
            onboardingComplete = false
            showMenuBarIcon = true
            finderRestoreEnabled = false
            pauseModeRaw = nil
            pausedUntil = nil
            lastSettingsSelection = nil
            ruleVersion = 0
        }
    }

    // MARK: - Closure record (unchanged from V2)

    @Model
    public final class ClosureRecord {
        #Index<ClosureRecord>([\.closedAt])

        public var id: UUID
        public var bundleID: String
        public var appName: String
        public var windowTitle: String?
        public var documentURL: URL?
        public var kindRaw: String
        public var closedAt: Date

        public init(
            id: UUID = UUID(),
            bundleID: String,
            appName: String,
            windowTitle: String?,
            documentURL: URL?,
            kindRaw: String,
            closedAt: Date
        ) {
            self.id = id
            self.bundleID = bundleID
            self.appName = appName
            self.windowTitle = windowTitle
            self.documentURL = documentURL
            self.kindRaw = kindRaw
            self.closedAt = closedAt
        }
    }
}
