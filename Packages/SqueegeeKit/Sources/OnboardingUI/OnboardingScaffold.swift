import SwiftUI

/// The shared layout for every onboarding step (ui_design section 5.1).
/// Provides: progress header, centered content, primary button, optional
/// skip button, and brand footer.
struct OnboardingScaffold<Content: View>: View {
    let step: Int
    let kicker: String
    let buttonTitle: String
    let canContinue: Bool
    let showSkip: Bool
    let onContinue: () -> Void
    var onSkip: (() -> Void)?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            ProgressHeader(
                step: step,
                totalSteps: OnboardingViewModel.totalSteps,
                kicker: kicker
            )
            .padding(.top, 28)

            Spacer()

            content()
                .frame(maxWidth: 520)

            Spacer()

            // Primary button
            Button(action: onContinue) {
                Text(buttonTitle)
                    .frame(maxWidth: 440)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canContinue)

            // Skip link (only on accessibility step)
            if showSkip, let onSkip {
                Button("Skip", action: onSkip)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                // Reserve space so layout stays stable
                Color.clear.frame(height: 26)
            }

            Spacer()
                .frame(height: 24)

            BrandFooter()

            Spacer()
                .frame(height: 20)
        }
        .frame(width: 640, height: 600)
    }
}
