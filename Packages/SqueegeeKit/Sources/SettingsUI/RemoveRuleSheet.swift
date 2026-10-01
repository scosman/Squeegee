import SwiftUI

/// A custom confirmation sheet for rule removal. Uses `.sheet` instead
/// of `.confirmationDialog` or `.alert` because both macOS system
/// presentations render as an NSAlert panel that shows the app icon.
struct RemoveRuleSheet: View {
    let appName: String
    let onRemove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Remove the rule for \(appName)?")
                .font(.headline)

            Text("The app will use the global rule.")
                .font(.body)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Remove", role: .destructive) {
                    onRemove()
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 340)
    }
}
