import AppCore
import SwiftUI

/// The public entry point for the onboarding flow. Creates the view model and
/// switches between step views. The window is fixed at 640x600 with a hidden
/// title bar.
public struct OnboardingRootView: View {
    @State private var viewModel: OnboardingViewModel

    public init(core: AppCore) {
        _viewModel = State(initialValue: OnboardingViewModel(core: core))
    }

    public var body: some View {
        Group {
            switch viewModel.step {
            case 1:
                WelcomeStepView(viewModel: viewModel)
            case 2:
                AccessibilityStepView(viewModel: viewModel)
            case 3:
                SuggestionsStepView(viewModel: viewModel)
            case 4:
                DoneStepView(viewModel: viewModel)
            default:
                EmptyView()
            }
        }
    }
}
