import SwiftUI

/// The brand footer shown at the bottom of every onboarding step:
/// app icon, app name, and tagline.
struct BrandFooter: View {
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 16, height: 16)

                Text("Squeegee")
                    .font(.headline)
            }

            Text("Clean your windows.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }
}
