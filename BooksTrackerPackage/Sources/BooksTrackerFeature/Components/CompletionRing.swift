import SwiftUI

/// A circular progress ring overlay showing metadata completion percentage
/// Positioned in the top-right corner of book covers with color-coded completion levels
@available(iOS 26.0, *)
public struct CompletionRing: View {
    let completion: Double

    private var ringColor: Color {
        switch completion {
        case 0..<0.25:
            return .red
        case 0.25..<0.50:
            return .orange
        case 0.50..<0.75:
            return .yellow
        case 0.75..<1.0:
            return .green
        default: // 1.0 (100%)
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        }
    }

    private var percentageText: String {
        let percent = Int(completion * 100)
        return "\(percent)%"
    }

    public init(completion: Double) {
        self.completion = Double(min(max(completion, 0), 1))
    }

    public var body: some View {
        ZStack {
            // Background circle
            Circle()
                .fill(.white.opacity(0.1))
                .blur(radius: 1)

            // Progress ring
            Circle()
                .trim(from: 0, to: completion)
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: completion)

            // Percentage text
            Text(percentageText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(ringColor)
                .lineLimit(1)
        }
        .frame(width: 44, height: 44)
        .accessibilityLabel("Metadata completion")
        .accessibilityValue("\(percentageText) complete")
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Completion Ring States") {
    VStack(spacing: 20) {
        HStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("0%")
                    .font(.caption2)
                CompletionRing(completion: 0)
            }

            VStack(spacing: 8) {
                Text("25%")
                    .font(.caption2)
                CompletionRing(completion: 0.25)
            }

            VStack(spacing: 8) {
                Text("50%")
                    .font(.caption2)
                CompletionRing(completion: 0.50)
            }

            VStack(spacing: 8) {
                Text("75%")
                    .font(.caption2)
                CompletionRing(completion: 0.75)
            }
        }

        HStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("90%")
                    .font(.caption2)
                CompletionRing(completion: 0.90)
            }

            VStack(spacing: 8) {
                Text("100%")
                    .font(.caption2)
                CompletionRing(completion: 1.0)
            }

            Spacer()
        }
    }
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
}

@available(iOS 26.0, *)
#Preview("Completion Ring on Cover") {
    ZStack(alignment: .topTrailing) {
        // Simulated book cover
        Rectangle()
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [.blue, .purple]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 120, height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 8))

        CompletionRing(completion: 0.65)
            .padding(8)
    }
    .frame(width: 150, height: 220)
}
