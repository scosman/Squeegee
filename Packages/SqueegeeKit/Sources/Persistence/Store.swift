import Engine
import Foundation
import OSLog
import SwiftData

private let logger = Logger(subsystem: "net.scosman.squeegee", category: "Store")

// Type aliases for the V2 model types used throughout the module.
public typealias AppRuleRecord = SqueegeeSchemaV2.AppRuleRecord
public typealias AppSettingsRecord = SqueegeeSchemaV2.AppSettingsRecord
public typealias ClosureRecord = SqueegeeSchemaV2.ClosureRecord

/// How the store's backing container is configured.
public enum StoreConfiguration: Sendable {
    /// Persists to the given directory URL.
    case onDisk(URL)
    /// In-memory only; used for tests.
    case inMemory
}

/// The persistence layer for Squeegee. Wraps a SwiftData `ModelContext`
/// and maps between `@Model` records and Engine value types.
///
/// All access is on the main actor. SwiftData observation (via `@Model` and
/// `Observable`) allows `AppCore` to detect rule changes through
/// `withObservationTracking` on `ruleSet()`.
@MainActor
public final class Store {
    public let context: ModelContext
    private let container: ModelContainer

    /// The singleton settings row. Created on first access if it does not exist.
    public var settings: AppSettingsRecord {
        if let cached = _settings {
            return cached
        }
        let record = fetchOrCreateSettings()
        _settings = record
        return record
    }

    private var _settings: AppSettingsRecord?

    /// The maximum number of closure records to keep.
    static let maxClosureRecords = 1000

    // MARK: - Init

    public init(configuration: StoreConfiguration) throws {
        let schema = Schema(versionedSchema: SqueegeeSchemaV2.self)
        let modelConfig = switch configuration {
        case let .onDisk(url):
            ModelConfiguration(
                "Squeegee",
                schema: schema,
                url: url.appendingPathComponent("Squeegee.store"),
                allowsSave: true
            )
        case .inMemory:
            ModelConfiguration(
                "Squeegee",
                schema: schema,
                isStoredInMemoryOnly: true,
                allowsSave: true
            )
        }

        container = try ModelContainer(
            for: schema,
            migrationPlan: SqueegeeMigrationPlan.self,
            configurations: [modelConfig]
        )
        context = container.mainContext
        context.autosaveEnabled = true
    }

    // MARK: - App rules

    /// All app rules, sorted by app name (case-insensitive).
    public func appRules() -> [AppRuleRecord] {
        let descriptor = FetchDescriptor<AppRuleRecord>(
            sortBy: [SortDescriptor(\AppRuleRecord.appName, comparator: .localizedStandard)]
        )
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch app rules: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    /// Fetches a single app rule by bundle ID.
    public func appRule(bundleID: String) -> AppRuleRecord? {
        var descriptor = FetchDescriptor<AppRuleRecord>(
            predicate: #Predicate { $0.bundleID == bundleID }
        )
        descriptor.fetchLimit = 1
        do {
            return try context.fetch(descriptor).first
        } catch {
            logger.error("Failed to fetch app rule for \(bundleID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Adds an app rule. If a rule for this bundle ID already exists, returns
    /// the existing one without modification.
    @discardableResult
    public func addAppRule(bundleID: String, appName: String, rule: Rule) -> AppRuleRecord {
        if let existing = appRule(bundleID: bundleID) {
            return existing
        }
        let record = AppRuleRecord(
            bundleID: bundleID,
            appName: appName,
            isEnabled: rule.isEnabled,
            closeAfterSeconds: Int(rule.closeAfter),
            measureFromRaw: rule.measureFrom.rawValue,
            quitPolicyRaw: rule.quitPolicy.rawValue
        )
        context.insert(record)
        settings.ruleVersion += 1
        return record
    }

    /// Removes the app rule for the given bundle ID.
    public func removeAppRule(bundleID: String) {
        if let record = appRule(bundleID: bundleID) {
            context.delete(record)
            settings.ruleVersion += 1
        }
    }

    /// Builds an Engine `RuleSet` from the current records. Reading this
    /// through `withObservationTracking` fires `onChange` when any rule
    /// property changes, or when rules are inserted or deleted (via
    /// `ruleVersion` on the settings singleton).
    public func ruleSet() -> RuleSet {
        let current = settings
        // Touch ruleVersion so observation tracking detects rule inserts/deletes
        _ = current.ruleVersion
        let globalRule = Rule(
            isEnabled: current.globalIsEnabled,
            closeAfter: TimeInterval(current.globalCloseAfterSeconds),
            measureFrom: MeasureFrom(rawValue: current.globalMeasureFromRaw) ?? .lastActive,
            quitPolicy: .never
        )

        var appRuleMap: [String: Rule] = [:]
        for record in appRules() {
            appRuleMap[record.bundleID] = Rule(
                isEnabled: record.isEnabled,
                closeAfter: TimeInterval(record.closeAfterSeconds),
                measureFrom: MeasureFrom(rawValue: record.measureFromRaw) ?? .lastActive,
                quitPolicy: QuitPolicy(rawValue: record.quitPolicyRaw) ?? .never
            )
        }

        return RuleSet(global: globalRule, appRules: appRuleMap)
    }

    // MARK: - Closure history

    /// Records a closure and trims the store to the newest records.
    public func appendClosure(_ value: ClosureValue) {
        let record = ClosureRecord(
            bundleID: value.bundleID,
            appName: value.appName,
            windowTitle: value.windowTitle,
            documentURL: value.documentURL,
            kindRaw: value.kind.rawValue,
            closedAt: value.closedAt
        )
        context.insert(record)
        trimClosures()
    }

    /// Returns the most recent closures, newest first.
    public func recentClosures(limit: Int) -> [ClosureValue] {
        var descriptor = FetchDescriptor<ClosureRecord>(
            sortBy: [SortDescriptor(\ClosureRecord.closedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        let records: [ClosureRecord]
        do {
            records = try context.fetch(descriptor)
        } catch {
            logger.error("Failed to fetch closures: \(error.localizedDescription, privacy: .public)")
            records = []
        }
        return records.map { record in
            ClosureValue(
                bundleID: record.bundleID,
                appName: record.appName,
                windowTitle: record.windowTitle,
                documentURL: record.documentURL,
                kind: ClosureValue.Kind(rawValue: record.kindRaw) ?? .windowClosed,
                closedAt: record.closedAt
            )
        }
    }

    /// Explicit save for writes that must persist immediately.
    public func save() {
        do {
            try context.save()
        } catch {
            logger.error("Failed to save context: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Private

    private func fetchOrCreateSettings() -> AppSettingsRecord {
        let descriptor = FetchDescriptor<AppSettingsRecord>()
        do {
            if let existing = try context.fetch(descriptor).first {
                return existing
            }
        } catch {
            logger.error("Failed to fetch settings: \(error.localizedDescription, privacy: .public)")
        }
        let record = AppSettingsRecord()
        context.insert(record)
        do {
            try context.save()
        } catch {
            logger.error("Failed to save new settings record: \(error.localizedDescription, privacy: .public)")
        }
        return record
    }

    private func trimClosures() {
        var countDescriptor = FetchDescriptor<ClosureRecord>()
        countDescriptor.propertiesToFetch = []
        let count: Int
        do {
            count = try context.fetchCount(countDescriptor)
        } catch {
            logger.error("Failed to count closures for trim: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard count > Self.maxClosureRecords else { return }

        let excess = count - Self.maxClosureRecords
        var oldestDescriptor = FetchDescriptor<ClosureRecord>(
            sortBy: [SortDescriptor(\ClosureRecord.closedAt, order: .forward)]
        )
        oldestDescriptor.fetchLimit = excess
        do {
            let toDelete = try context.fetch(oldestDescriptor)
            for record in toDelete {
                context.delete(record)
            }
        } catch {
            logger.error("Failed to fetch oldest closures for trim: \(error.localizedDescription, privacy: .public)")
        }
    }
}
