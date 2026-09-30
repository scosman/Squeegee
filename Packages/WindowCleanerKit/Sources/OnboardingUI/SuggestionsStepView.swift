import SharedUI
import SwiftUI

/// Onboarding step 3: Pick apps to tidy. Shows the shared SuggestionListView
/// with all matched catalog apps checked by default.
struct SuggestionsStepView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            step: 3,
            kicker: "SUGGESTIONS",
            buttonTitle: "Continue",
            canContinue: true,
            showSkip: false,
            onContinue: { Task { await viewModel.advance() } },
            content: {
                VStack(spacing: 16) {
                    Text("Pick Apps to Tidy")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text("These apps are safe to clean up. You can change any rule later in Settings.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    if viewModel.isLoadingSuggestions {
                        ProgressView()
                            .frame(maxHeight: 200)
                    } else {
                        SuggestionListView(
                            suggestions: viewModel.suggestions,
                            selectedIDs: Binding(
                                get: { viewModel.selectedIDs },
                                set: { viewModel.selectedIDs = $0 }
                            )
                        )
                    }
                }
            }
        )
    }
}
