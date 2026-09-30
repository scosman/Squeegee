import SwiftUI

/// The progress bar and uppercase kicker at the top of each onboarding step.
/// The bar fills proportionally: `step / totalSteps`.
struct ProgressHeader: View {
    let step: Int
    let totalSteps: Int
    let kicker: String

    var body: some View {
        VStack(spacing: 16) {
            progressBar
            kickerLabel
        }
    }

    // MARK: - Progress bar

    private var progressBar: some View {
        let fraction = CGFloat(step) / CGFloat(totalSteps)
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 240, height: 3)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 240 * fraction, height: 3)
            }
            .frame(width: proxy.size.width)
        }
        .frame(height: 3)
        .accessibilityLabel("Step \(step) of \(totalSteps)")
    }

    // MARK: - Kicker

    private var kickerLabel: some View {
        Text(kicker)
            .font(.caption)
            .fontWeight(.semibold)
            .textCase(.uppercase)
            .tracking(1.5)
            .foregroundStyle(.secondary)
    }
}
