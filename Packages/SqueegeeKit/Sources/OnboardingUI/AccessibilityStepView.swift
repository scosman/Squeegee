import SwiftUI

/// Onboarding step 2: Accessibility permission. Shows a card with the
/// permission row (Grant / Granted) and help text. Continue is gated on
/// permission; a Skip link bypasses the gate.
struct AccessibilityStepView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        OnboardingScaffold(
            step: 2,
            kicker: "PERMISSIONS",
            buttonTitle: "Continue",
            canContinue: viewModel.canContinue,
            showSkip: !viewModel.isPermissionGranted,
            onContinue: { Task { await viewModel.advance() } },
            onSkip: { Task { await viewModel.skip() } },
            content: {
                VStack(spacing: 20) {
                    Text("Allow Accessibility Access")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)

                    Text("Squeegee uses Accessibility to see and close windows of other apps. Nothing leaves your Mac.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)

                    permissionCard

                    Text("macOS opens System Settings. Turn on Squeegee, then come back here.")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 440)
                }
            }
        )
    }

    // MARK: - Permission card

    private var permissionCard: some View {
        HStack(spacing: 12) {
            // Accent-tinted rounded square with accessibility symbol
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: "accessibility")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility")
                    .font(.body)
                    .fontWeight(.medium)

                Text("Lets Squeegee close windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.isPermissionGranted {
                grantedTag
            } else {
                Button("Grant") {
                    viewModel.grant()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: 440)
    }

    // MARK: - Granted tag

    private var grantedTag: some View {
        HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.accentColor)
            Text("Granted")
                .foregroundStyle(Color.accentColor)
                .fontWeight(.medium)
        }
        .font(.callout)
    }
}
