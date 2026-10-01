import AppCore
import Engine
import Foundation

/// Drives the onboarding flow: step progression, permission gating,
/// suggestions loading, and completion. All access is on the main actor.
@MainActor
@Observable
public final class OnboardingViewModel {
    // MARK: - Published state

    public private(set) var step: Int = 1
    public private(set) var suggestions: [Suggestion] = []
    public var selectedIDs: Set<String> = []
    public private(set) var isLoadingSuggestions = false

    // MARK: - Dependencies

    private let core: AppCore

    // MARK: - Constants

    static let totalSteps = 4

    // MARK: - Init

    public init(core: AppCore) {
        self.core = core
    }

    // MARK: - Computed state

    /// Whether the Continue / Get Started button is enabled on the current step.
    public var canContinue: Bool {
        switch step {
        case 2:
            core.permission == .granted
        default:
            true
        }
    }

    /// Whether the accessibility permission has been granted.
    public var isPermissionGranted: Bool {
        core.permission == .granted
    }

    // MARK: - Actions

    /// Advances to the next step. On step 2, requires permission unless
    /// `skip()` was used. On step 3, loads suggestions. On step 4 (Get
    /// Started), applies selected suggestions and completes onboarding.
    public func advance() async {
        guard step <= Self.totalSteps else { return }

        if step == Self.totalSteps {
            applyAndComplete()
            return
        }

        step += 1

        if step == 3 {
            await loadSuggestions()
        }
    }

    /// Skips the accessibility step (step 2) without requiring permission.
    public func skip() async {
        guard step == 2 else { return }
        step = 3
        await loadSuggestions()
    }

    /// Triggers the system accessibility permission prompt.
    public func grant() {
        core.requestAccessibility()
    }

    // MARK: - Private

    private func loadSuggestions() async {
        isLoadingSuggestions = true
        suggestions = await core.suggestions(excludingExistingRules: false)
        selectedIDs = Set(suggestions.map(\.id))
        isLoadingSuggestions = false
    }

    private func applyAndComplete() {
        let selected = suggestions.filter { selectedIDs.contains($0.id) }
        core.applySuggestions(selected)
        core.completeOnboarding()
    }
}
