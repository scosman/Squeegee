import SwiftUI

/// Onboarding step 1: Welcome. Shows the app icon, a welcome title, and
/// a short description of what Squeegee does.
struct WelcomeStepView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            step: 1,
            kicker: "WELCOME",
            buttonTitle: "Continue",
            canContinue: true,
            showSkip: false,
            onContinue: { Task { await viewModel.advance() } },
            content: {
                VStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 96)

                    Text("Welcome to Squeegee")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text("Squeegee closes windows you\u{2019}ve stopped using, based on rules you set for each app. Nothing closes until you turn it on.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
            }
        )
    }
}
