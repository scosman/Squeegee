import AppCore
import SwiftUI

/// A banner shown at the top of every settings detail page when Accessibility
/// permission is missing (ui_design section 4.4).
struct PermissionBanner: View {
    let core: AppCore

    var body: some View {
        if core.permission == .denied {
            GroupBox {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.yellow)
                    Text("Squeegee needs Accessibility access to close windows.")
                        .font(.callout)
                    Spacer()
                    Button("Open System Settings") {
                        core.openAccessibilitySettings()
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
