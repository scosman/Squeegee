import AppCore
import SettingsUI
import SwiftUI

/// The main window root: switches on `core.route` to show either the
/// onboarding flow or the settings view.
struct MainWindowRootView: View {
    let launchState: LaunchState

    var body: some View {
        if let core = launchState.core {
            contentView(core: core)
        } else {
            ProgressView("Loading\u{2026}")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func contentView(core: AppCore) -> some View {
        switch core.route {
        case .onboarding:
            // Onboarding views are built in Phase 8. Show a placeholder.
            onboardingPlaceholder(core: core)

        case let .settings(selection):
            SettingsRootView(core: core, initialSelection: selection)
        }
    }

    private func onboardingPlaceholder(core: AppCore) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("WindowCleaner")
                .font(.largeTitle)
                .fontWeight(.semibold)
            Text("Onboarding screens are coming in a future update.")
                .foregroundStyle(.secondary)
            Button("Skip to Settings") {
                core.completeOnboarding()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minWidth: 640, minHeight: 600)
    }
}
