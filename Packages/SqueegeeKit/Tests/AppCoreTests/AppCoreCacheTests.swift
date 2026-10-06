import AppCore
import Engine
import Foundation
import Persistence
import Presentation
import Testing
import TestSupport

/// Tests for the values AppCore caches so the UI never waits on slow system calls.
@Suite("AppCore caches")
struct AppCoreCacheTests {
    @MainActor
    private func makeCore(
        configure: (FakePortsBundle, Store) -> Void = { _, _ in }
    ) async throws -> (AppCore, FakePortsBundle) {
        let epoch = Date(timeIntervalSinceReferenceDate: 0)
        let store = try Store(configuration: .inMemory)
        store.settings.onboardingComplete = true
        let bundle = FakePortsBundle(now: epoch)
        bundle.windowLister.windows = []
        bundle.workspace.frontmost = nil
        configure(bundle, store)
        let core = AppCore(store: store, ports: bundle.ports, catalog: .builtIn)
        await core.start()
        return (core, bundle)
    }

    private static let docURL = URL(fileURLWithPath: "/Users/test/report.pdf")

    private static func closure(url: URL) -> ClosureValue {
        ClosureValue(
            bundleID: "com.apple.Preview", appName: "Preview",
            windowTitle: "report.pdf", documentURL: url,
            kind: .windowClosed, closedAt: Date(timeIntervalSinceReferenceDate: 0)
        )
    }

    private static func reopenItem(in menu: MenuContent) -> MenuItem? {
        menu.sections.flatMap(\.items).first { $0.title == "report.pdf" }
    }

    // MARK: - Launch at login

    @Test("launchAtLogin reads the system state at start")
    @MainActor
    func launchAtLoginLoadedAtStart() async throws {
        let (core, _) = try await makeCore { bundle, _ in bundle.loginItem.enabled = true }
        await settle()
        #expect(core.launchAtLogin)
    }

    @Test("setLaunchAtLogin updates the cached state")
    @MainActor
    func setLaunchAtLoginUpdatesCache() async throws {
        let (core, bundle) = try await makeCore()
        await settle()
        #expect(!core.launchAtLogin)

        try await core.setLaunchAtLogin(true)
        #expect(core.launchAtLogin)
        #expect(bundle.loginItem.setEnabledCalls == [true])
    }

    @Test("setLaunchAtLogin restores the system state on error")
    @MainActor
    func setLaunchAtLoginRevertsOnError() async throws {
        let (core, bundle) = try await makeCore()
        await settle()
        bundle.loginItem.shouldThrow = true

        await #expect(throws: FakeLoginItem.FakeLoginItemError.self) {
            try await core.setLaunchAtLogin(true)
        }
        #expect(!core.launchAtLogin)
    }

    // MARK: - File existence

    @Test("Menu marks a missing file after the start-up check")
    @MainActor
    func missingFileCheckedAtStart() async throws {
        let (core, _) = try await makeCore { _, store in
            store.appendClosure(Self.closure(url: Self.docURL))
            store.save()
        }
        await settle()

        let item = try #require(Self.reopenItem(in: core.menuContent()))
        #expect(item.subtitle?.contains("File not found") == true)
        #expect(!item.isEnabled)
    }

    @Test("Menu treats an unchecked file as present, then uses the check on the next open")
    @MainActor
    func uncheckedFileThenRefreshed() async throws {
        let (core, bundle) = try await makeCore()
        bundle.opener.existingFiles = []
        core.store.appendClosure(Self.closure(url: Self.docURL))
        core.store.save()

        // Not checked yet: shown as present, without a blocking file check.
        let first = try #require(Self.reopenItem(in: core.menuContent()))
        #expect(first.isEnabled)

        await settle()
        let second = try #require(Self.reopenItem(in: core.menuContent()))
        #expect(!second.isEnabled)
    }

    @Test("Menu shows a present file as reopenable")
    @MainActor
    func presentFileReopenable() async throws {
        let (core, _) = try await makeCore { bundle, store in
            bundle.opener.existingFiles = [Self.docURL]
            store.appendClosure(Self.closure(url: Self.docURL))
            store.save()
        }
        await settle()

        let item = try #require(Self.reopenItem(in: core.menuContent()))
        #expect(item.isEnabled)
        #expect(item.action == .reopen(Self.closure(url: Self.docURL)))
    }
}
