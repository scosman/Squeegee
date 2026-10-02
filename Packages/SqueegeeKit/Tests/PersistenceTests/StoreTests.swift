import Engine
import Foundation
import Observation
import Persistence
import SwiftData
import Synchronization
import Testing

/// Thread-safe flag for observation change tracking in Swift 6.
private final class ObservationFlag: Sendable {
    private let storage = Mutex(false)

    var value: Bool {
        storage.withLock { $0 }
    }

    func set() {
        storage.withLock { $0 = true }
    }
}

@MainActor
@Suite("Store")
struct StoreTests {
    private func makeStore() throws -> Store {
        try Store(configuration: .inMemory)
    }

    // MARK: - Settings singleton

    @Test func settingsSingletonCreated() throws {
        let store = try makeStore()
        let settings = store.settings
        #expect(settings.globalIsEnabled == false)
        #expect(settings.globalCloseAfterSeconds == 21600)
        #expect(settings.globalMeasureFromRaw == "lastActive")
        #expect(settings.onboardingComplete == false)
        #expect(settings.showMenuBarIcon == true)
        #expect(settings.pauseModeRaw == nil)
        #expect(settings.pausedUntil == nil)
        #expect(settings.lastSettingsSelection == nil)
    }

    @Test func settingsSingletonReturnsSameInstance() throws {
        let store = try makeStore()
        let first = store.settings
        first.globalIsEnabled = true
        let second = store.settings
        #expect(second.globalIsEnabled == true)
    }

    // MARK: - App rules

    @Test func addAndFetchAppRules() throws {
        let store = try makeStore()
        let rule = Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never)
        store.addAppRule(bundleID: "com.test.beta", appName: "Beta", rule: rule)
        store.addAppRule(bundleID: "com.test.alpha", appName: "Alpha", rule: rule)

        let rules = store.appRules()
        #expect(rules.count == 2)
        #expect(rules[0].appName == "Alpha")
        #expect(rules[1].appName == "Beta")
    }

    @Test func addDuplicateReturnsExisting() throws {
        let store = try makeStore()
        let rule = Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never)
        let first = store.addAppRule(bundleID: "com.test.app", appName: "App", rule: rule)
        first.isEnabled = false

        let second = store.addAppRule(bundleID: "com.test.app", appName: "App", rule: rule)
        #expect(second.isEnabled == false)
        #expect(store.appRules().count == 1)
    }

    @Test func fetchAppRuleByBundleID() throws {
        let store = try makeStore()
        let rule = Rule(isEnabled: true, closeAfter: 7200, measureFrom: .opened, quitPolicy: .always)
        store.addAppRule(bundleID: "com.test.app", appName: "App", rule: rule)

        let fetched = store.appRule(bundleID: "com.test.app")
        #expect(fetched != nil)
        #expect(fetched?.closeAfterSeconds == 7200)
        #expect(fetched?.measureFromRaw == "opened")

        #expect(store.appRule(bundleID: "com.nonexistent") == nil)
    }

    @Test func removeAppRule() throws {
        let store = try makeStore()
        let rule = Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never)
        store.addAppRule(bundleID: "com.test.app", appName: "App", rule: rule)
        #expect(store.appRules().count == 1)

        store.removeAppRule(bundleID: "com.test.app")
        #expect(store.appRules().isEmpty)
        #expect(store.appRule(bundleID: "com.test.app") == nil)
    }

    // MARK: - RuleSet mapping

    @Test func ruleSetMapping() throws {
        let store = try makeStore()
        store.settings.globalIsEnabled = true
        store.settings.globalCloseAfterSeconds = 7200
        store.settings.globalMeasureFromRaw = "opened"

        let finderRule = Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .always)
        store.addAppRule(bundleID: "com.apple.finder", appName: "Finder", rule: finderRule)

        let ruleSet = store.ruleSet()
        #expect(ruleSet.global.isEnabled == true)
        #expect(ruleSet.global.closeAfter == 7200)
        #expect(ruleSet.global.measureFrom == .opened)
        #expect(ruleSet.global.quitPolicy == .never)

        let appRule = ruleSet.appRules["com.apple.finder"]
        #expect(appRule != nil)
        #expect(appRule?.isEnabled == true)
        #expect(appRule?.closeAfter == 3600)
        #expect(appRule?.quitPolicy == .always)
    }

    // MARK: - Closure history

    @Test func appendAndFetchClosures() throws {
        let store = try makeStore()
        let now = Date()
        let older = ClosureValue(
            bundleID: "com.test.a", appName: "A", windowTitle: "W1",
            documentURL: nil, kind: .windowClosed, closedAt: now.addingTimeInterval(-60)
        )
        let newer = ClosureValue(
            bundleID: "com.test.b", appName: "B", windowTitle: "W2",
            documentURL: URL(string: "file:///test.pdf"), kind: .windowClosed, closedAt: now
        )
        store.appendClosure(older)
        store.appendClosure(newer)

        let recent = store.recentClosures(limit: 10)
        #expect(recent.count == 2)
        #expect(recent[0].appName == "B")
        #expect(recent[1].appName == "A")
    }

    @Test func recentClosuresRespectsLimit() throws {
        let store = try makeStore()
        let now = Date()
        for idx in 0 ..< 5 {
            store.appendClosure(ClosureValue(
                bundleID: "com.test.\(idx)", appName: "App\(idx)", windowTitle: nil,
                documentURL: nil, kind: .windowClosed, closedAt: now.addingTimeInterval(TimeInterval(idx))
            ))
        }

        let recent = store.recentClosures(limit: 3)
        #expect(recent.count == 3)
    }

    @Test func appendClosureFIFOTrim() throws {
        let store = try makeStore()
        let base = Date()
        for idx in 0 ..< 1005 {
            store.appendClosure(ClosureValue(
                bundleID: "com.test.\(idx)", appName: "App\(idx)", windowTitle: nil,
                documentURL: nil, kind: .windowClosed, closedAt: base.addingTimeInterval(TimeInterval(idx))
            ))
        }

        // After 1005 inserts with FIFO trim, only 1000 remain
        let all = store.recentClosures(limit: 2000)
        #expect(all.count == 1000)

        // The oldest should be gone (indices 0-4 trimmed)
        let oldest = all.last
        #expect(oldest?.bundleID == "com.test.5")
    }

    @Test func closureKindRoundTrips() throws {
        let store = try makeStore()
        let now = Date()
        store.appendClosure(ClosureValue(
            bundleID: "com.test.app", appName: "App", windowTitle: nil,
            documentURL: nil, kind: .appQuit, closedAt: now
        ))

        let recent = store.recentClosures(limit: 1)
        #expect(recent.first?.kind == .appQuit)
    }

    // MARK: - Save

    @Test func explicitSaveDoesNotThrow() throws {
        let store = try makeStore()
        store.settings.globalIsEnabled = true
        store.save()
    }
}

// MARK: - Observation suite

@MainActor
@Suite("Store Observation")
struct StoreObservationTests {
    private func makeStore() throws -> Store {
        try Store(configuration: .inMemory)
    }

    @Test func observationFiresOnRulePropertyEdit() throws {
        let store = try makeStore()
        let rule = Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never)
        let record = store.addAppRule(bundleID: "com.test.app", appName: "App", rule: rule)
        store.save()

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.ruleSet()
        } onChange: {
            flag.set()
        }

        record.closeAfterSeconds = 7200
        #expect(flag.value)
    }

    @Test func observationFiresOnRuleInsert() throws {
        let store = try makeStore()
        store.save()

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.ruleSet()
        } onChange: {
            flag.set()
        }

        let rule = Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never)
        store.addAppRule(bundleID: "com.test.new", appName: "NewApp", rule: rule)
        #expect(flag.value)
    }

    @Test func observationFiresOnRuleDelete() throws {
        let store = try makeStore()
        let rule = Rule(isEnabled: true, closeAfter: 3600, measureFrom: .lastActive, quitPolicy: .never)
        store.addAppRule(bundleID: "com.test.app", appName: "App", rule: rule)
        store.save()

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.ruleSet()
        } onChange: {
            flag.set()
        }

        store.removeAppRule(bundleID: "com.test.app")
        #expect(flag.value)
    }

    @Test func observationFiresOnGlobalSettingsEdit() throws {
        let store = try makeStore()
        store.save()

        let flag = ObservationFlag()
        withObservationTracking {
            _ = store.ruleSet()
        } onChange: {
            flag.set()
        }

        store.settings.globalIsEnabled = true
        #expect(flag.value)
    }
}

// MARK: - Migration suite

@MainActor
@Suite("Store Migration")
struct StoreMigrationTests {
    /// Creates a V1 store on disk with a rule, settings, closure, and tracked window.
    /// Returns the temp directory (caller must clean up).
    private func populateV1Store() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("squeegee-migration-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storeURL = tempDir.appendingPathComponent("Squeegee.store")
        let v1Schema = Schema(versionedSchema: SqueegeeSchemaV1.self)
        let v1Config = ModelConfiguration("Squeegee", schema: v1Schema, url: storeURL, allowsSave: true)
        let v1Container = try ModelContainer(for: v1Schema, configurations: [v1Config])
        let ctx = v1Container.mainContext

        ctx.insert(SqueegeeSchemaV1.AppRuleRecord(
            bundleID: "com.test.migrated", appName: "MigratedApp",
            isEnabled: true, closeAfterSeconds: 7200,
            measureFromRaw: "opened", quitPolicyRaw: "always"
        ))
        let settings = SqueegeeSchemaV1.AppSettingsRecord()
        settings.onboardingComplete = true
        settings.globalCloseAfterSeconds = 9000
        ctx.insert(settings)
        ctx.insert(SqueegeeSchemaV1.ClosureRecord(
            bundleID: "com.test.closed", appName: "ClosedApp",
            windowTitle: "Doc.pdf", documentURL: nil,
            kindRaw: "windowClosed", closedAt: Date()
        ))
        ctx.insert(SqueegeeSchemaV1.TrackedWindowRecord(
            pid: 42, windowID: 99, bundleID: "com.test.tracked",
            processLaunchDate: nil, firstSeen: Date(), lastActive: nil, closeSentAt: nil
        ))
        try ctx.save()
        return tempDir
    }

    @Test func migratesV1StoreToV2KeepingRulesSettingsAndHistory() throws {
        let tempDir = try populateV1Store()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try Store(configuration: .onDisk(tempDir))

        let rules = store.appRules()
        #expect(rules.count == 1)
        #expect(rules.first?.bundleID == "com.test.migrated")
        #expect(rules.first?.appName == "MigratedApp")
        #expect(rules.first?.closeAfterSeconds == 7200)
        #expect(rules.first?.measureFromRaw == "opened")

        #expect(store.settings.onboardingComplete == true)
        #expect(store.settings.globalCloseAfterSeconds == 9000)

        let closures = store.recentClosures(limit: 10)
        #expect(closures.count == 1)
        #expect(closures.first?.bundleID == "com.test.closed")
        #expect(closures.first?.windowTitle == "Doc.pdf")
    }
}
