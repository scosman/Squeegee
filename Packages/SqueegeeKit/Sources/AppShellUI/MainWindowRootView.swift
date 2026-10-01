import AppCore
import OnboardingUI
import SettingsUI
import SwiftUI

/// The main window root: switches on `core.route` to show either the
/// onboarding flow or the settings view.
public struct MainWindowRootView: View {
    let core: AppCore

    public init(core: AppCore) {
        self.core = core
    }

    public var body: some View {
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
