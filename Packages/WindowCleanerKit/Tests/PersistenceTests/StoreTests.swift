import Engine
import Foundation
import Observation
import Persistence
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

    // MARK: - Tracked windows

    @Test func saveAndLoadTrackedWindows() throws {
        let store = try makeStore()
        let now = Date()
        let snapshots = [
            TrackedWindowSnapshot(
                key: WindowKey(pid: 100, windowID: 1),
                bundleID: "com.test.a", processLaunchDate: now,
                firstSeen: now, lastActive: now, closeSentAt: nil
            ),
            TrackedWindowSnapshot(
                key: WindowKey(pid: 100, windowID: 2),
                bundleID: "com.test.a", processLaunchDate: now,
                firstSeen: now, lastActive: nil, closeSentAt: now
            )
        ]

        store.saveTrackedWindows(snapshots)
        let loaded = store.loadTrackedWindows()
        #expect(loaded.count == 2)

        let byKey = Dictionary(loaded.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        let first = byKey[WindowKey(pid: 100, windowID: 1)]
        #expect(first != nil)
        #expect(first?.bundleID == "com.test.a")
        #expect(first?.lastActive != nil)
        #expect(first?.closeSentAt == nil)

        let second = byKey[WindowKey(pid: 100, windowID: 2)]
        #expect(second?.closeSentAt != nil)
    }

    @Test func saveTrackedWindowsUpsertAndDeleteStale() throws {
        let store = try makeStore()
        let now = Date()
        let initial = [
            TrackedWindowSnapshot(
                key: WindowKey(pid: 100, windowID: 1),
                bundleID: "com.test.a", processLaunchDate: now,
                firstSeen: now, lastActive: nil, closeSentAt: nil
            ),
            TrackedWindowSnapshot(
                key: WindowKey(pid: 100, windowID: 2),
                bundleID: "com.test.a", processLaunchDate: now,
                firstSeen: now, lastActive: nil, closeSentAt: nil
            )
        ]
        store.saveTrackedWindows(initial)
        #expect(store.loadTrackedWindows().count == 2)

        // Save with only window 1 updated, window 2 removed, window 3 added
        let later = now.addingTimeInterval(60)
        let updated = [
            TrackedWindowSnapshot(
                key: WindowKey(pid: 100, windowID: 1),
                bundleID: "com.test.a", processLaunchDate: now,
                firstSeen: now, lastActive: later, closeSentAt: nil
            ),
            TrackedWindowSnapshot(
                key: WindowKey(pid: 100, windowID: 3),
                bundleID: "com.test.a", processLaunchDate: now,
                firstSeen: later, lastActive: nil, closeSentAt: nil
            )
        ]
        store.saveTrackedWindows(updated)

        let loaded = store.loadTrackedWindows()
        #expect(loaded.count == 2)
        let keys = Set(loaded.map(\.key))
        #expect(keys.contains(WindowKey(pid: 100, windowID: 1)))
        #expect(keys.contains(WindowKey(pid: 100, windowID: 3)))
        #expect(!keys.contains(WindowKey(pid: 100, windowID: 2)))

        let window1 = loaded.first(where: { $0.key.windowID == 1 })
        #expect(window1?.lastActive == later)
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
