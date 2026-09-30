import AppCore
import Engine
import Foundation
import OnboardingUI
import Persistence
import Testing
import TestSupport

/// Helper to create an in-memory Store for tests.
@MainActor
private func makeStore() throws -> Store {
    try Store(configuration: .inMemory)
}

/// Yields enough times for pending Tasks to process.
@MainActor
private func settle(rounds: Int = 10) async {
    for _ in 0 ..< rounds {
        await Task.yield()
    }
}

@Suite("OnboardingViewModel")
struct OnboardingViewModelTests {
    @Test("Initial step is welcome (step 1)")
    @MainActor
    func initialStepIsWelcome() throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        let core = AppCore(store: store, ports: bundle.ports)
        let viewModel = OnboardingViewModel(core: core)

        #expect(viewModel.step == 1)
    }

    @Test("Advance from welcome moves to accessibility (step 2)")
    @MainActor
    func advanceFromWelcome() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        let core = AppCore(store: store, ports: bundle.ports)
        let viewModel = OnboardingViewModel(core: core)

        await viewModel.advance()
        #expect(viewModel.step == 2)
    }

    @Test("Advance through all four steps")
    @MainActor
    func advanceThroughAllSteps() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = true
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        #expect(viewModel.step == 1)

        await viewModel.advance()
        #expect(viewModel.step == 2)

        await viewModel.advance() // Permission granted, moves to step 3
        #expect(viewModel.step == 3)

        await viewModel.advance()
        #expect(viewModel.step == 4)
    }

    @Test("Continue blocked on step 2 without permission")
    @MainActor
    func continueBlockedWithoutPermission() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = false
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        await viewModel.advance() // Move to step 2
        #expect(viewModel.step == 2)
        #expect(!viewModel.canContinue)
    }

    @Test("Continue enabled on step 2 with permission")
    @MainActor
    func continueEnabledWithPermission() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = true
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        await viewModel.advance() // Move to step 2
        #expect(viewModel.step == 2)
        #expect(viewModel.canContinue)
    }

    @Test("Skip accessibility advances to suggestions (step 3)")
    @MainActor
    func skipAccessibility() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = false
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        await viewModel.advance() // Move to step 2
        #expect(viewModel.step == 2)
        #expect(!viewModel.canContinue)

        await viewModel.skip()
        #expect(viewModel.step == 3)
    }

    @Test("Grant calls requestAccessibility on core")
    @MainActor
    func grantCallsRequestAccessibility() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = false
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        await viewModel.advance() // Move to step 2

        viewModel.grant()

        #expect(bundle.permission.promptRequested)
    }

    @Test("Suggestions load on step 3")
    @MainActor
    func suggestionsLoadOnStep3() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = true
        bundle.installedApps.apps = [
            InstalledApp(bundleID: "com.apple.finder", name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        ]
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        await viewModel.advance() // Step 2
        await viewModel.advance() // Step 3, triggers load

        #expect(viewModel.step == 3)
        #expect(!viewModel.suggestions.isEmpty)
        #expect(viewModel.suggestions.first?.entry.bundleID == "com.apple.finder")
        #expect(viewModel.selectedIDs.contains("com.apple.finder"))
    }

    @Test("Apply suggestions and complete onboarding")
    @MainActor
    func applySuggestionsAndComplete() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = true
        bundle.installedApps.apps = [
            InstalledApp(bundleID: "com.apple.finder", name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        ]
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        await viewModel.advance() // Step 2
        await viewModel.advance() // Step 3
        await viewModel.advance() // Step 4

        // All suggestions are selected by default
        #expect(viewModel.step == 4)

        // Get Started: applies suggestions and completes onboarding
        await viewModel.advance()

        // Verify onboarding completed
        #expect(store.settings.onboardingComplete)
        #expect(core.route == .settings(.general))

        // Verify rules were created for selected suggestions
        let rules = store.appRules()
        #expect(rules.contains { $0.bundleID == "com.apple.finder" })

        // Verify login item was enabled
        #expect(bundle.loginItem.enabled)
    }

    @Test("Permission state updates from core")
    @MainActor
    func permissionStateUpdates() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = false
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        await viewModel.advance() // Step 2
        #expect(!viewModel.isPermissionGranted)

        // Simulate permission grant
        bundle.permission.trusted = true
        bundle.permission.notifyChange()
        await settle()

        #expect(viewModel.isPermissionGranted)
        #expect(viewModel.canContinue)
    }

    @Test("Unchecked suggestions are not applied")
    @MainActor
    func uncheckedSuggestionsNotApplied() async throws {
        let store = try makeStore()
        let bundle = FakePortsBundle(now: Date())
        bundle.permission.trusted = true
        bundle.installedApps.apps = [
            InstalledApp(bundleID: "com.apple.finder", name: "Finder", url: URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")),
            InstalledApp(bundleID: "com.apple.Preview", name: "Preview", url: URL(fileURLWithPath: "/System/Applications/Preview.app"))
        ]
        let core = AppCore(store: store, ports: bundle.ports)
        await core.start()
        await settle()

        let viewModel = OnboardingViewModel(core: core)
        await viewModel.advance() // Step 2
        await viewModel.advance() // Step 3

        // Uncheck Finder
        viewModel.selectedIDs.remove("com.apple.finder")

        await viewModel.advance() // Step 4
        await viewModel.advance() // Get Started

        // Preview should have a rule, Finder should not
        let rules = store.appRules()
        #expect(rules.contains { $0.bundleID == "com.apple.Preview" })
        #expect(!rules.contains { $0.bundleID == "com.apple.finder" })
    }
}
