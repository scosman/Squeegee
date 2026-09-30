import SwiftUI

/// Onboarding step 4: Done. Shows a completion message and a Get Started
/// button that closes the window and starts the app from the menu bar.
struct DoneStepView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            step: 4,
            kicker: "FINISH",
            buttonTitle: "Get Started",
            canContinue: true,
            showSkip: false,
            onContinue: { Task { await viewModel.advance() } },
            content: {
                VStack(spacing: 16) {
                    Text("You\u{2019}re All Set")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    (Text("WindowCleaner runs in the menu bar. Click ")
                        + Text(Image(systemName: "macwindow.on.rectangle"))
                        + Text(" to see what closes next, or to change settings."))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
            }
        )
    }
}
