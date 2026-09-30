import AppCore
import OnboardingUI
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

    private func contentView(core: AppCore) -> some View {
        Group {
            switch core.route {
            case .onboarding:
                OnboardingRootView(core: core)

            case let .settings(selection):
                SettingsRootView(core: core, initialSelection: selection)
            }
        }
        .modifier(WindowChromeModifier(route: core.route))
    }
}
