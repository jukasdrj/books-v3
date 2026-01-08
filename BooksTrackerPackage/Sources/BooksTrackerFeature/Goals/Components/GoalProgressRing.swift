import SwiftUI

/// A circular progress ring showing goal completion percentage
/// Used to display visual progress for reading goals
@available(iOS 26.0, *)
public struct GoalProgressRing: View {
    let progress: Double
    let size: CGFloat
    let lineWidth: CGFloat
    let showPercentage: Bool

    public init(
        progress: Double,
        size: CGFloat = 120,
        lineWidth: CGFloat = 12,
        showPercentage: Bool = true
    ) {
        self.progress = min(max(progress, 0), 1.0)
        self.size = size
        self.lineWidth = lineWidth
        self.showPercentage = showPercentage
    }

    private var ringColor: Color {
        switch progress {
        case 0..<0.25:
            return .red.opacity(0.8)
        case 0.25..<0.50:
            return .orange.opacity(0.8)
        case 0.50..<0.75:
            return .yellow.opacity(0.9)
        case 0.75..<1.0:
            return .green.opacity(0.8)
        default: // 1.0 (100%)
            return Color(red: 1.0, green: 0.84, blue: 0.0) // Gold
        }
    }

    private var percentageText: String {
        let percent = Int(progress * 100)
        return "\(percent)%"
    }

    public var body: some View {
        ZStack {
            // Background circle (track)
            Circle()
                .stroke(
                    Color.gray.opacity(0.2),
                    lineWidth: lineWidth
                )

            // Progress circle (fill)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    ringColor,
                    style: StrokeStyle(
                        lineWidth: lineWidth,
                        lineCap: .round,
                        lineJoin: .round
                    )
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.6, dampingFraction: 0.7), value: progress)

            // Center content
            if showPercentage {
                VStack(spacing: 4) {
                    Text(percentageText)
                        .font(.system(size: size * 0.25, weight: .bold, design: .rounded))
                        .foregroundColor(ringColor)

                    Text("Complete")
                        .font(.system(size: size * 0.12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Goal progress")
        .accessibilityValue("\(percentageText) complete")
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Progress Ring States") {
    ScrollView {
        VStack(spacing: 40) {
            HStack(spacing: 30) {
                VStack(spacing: 8) {
                    GoalProgressRing(progress: 0, size: 100)
                    Text("0% - Not Started")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    GoalProgressRing(progress: 0.25, size: 100)
                    Text("25% - Early Progress")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 30) {
                VStack(spacing: 8) {
                    GoalProgressRing(progress: 0.50, size: 100)
                    Text("50% - Halfway")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    GoalProgressRing(progress: 0.75, size: 100)
                    Text("75% - Almost There")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 30) {
                VStack(spacing: 8) {
                    GoalProgressRing(progress: 0.90, size: 100)
                    Text("90% - Nearly Done")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 8) {
                    GoalProgressRing(progress: 1.0, size: 100)
                    Text("100% - Complete!")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Divider()

            // Size variations
            HStack(spacing: 30) {
                VStack(spacing: 8) {
                    GoalProgressRing(progress: 0.65, size: 80, lineWidth: 8)
                    Text("Small")
                        .font(.caption2)
                }

                VStack(spacing: 8) {
                    GoalProgressRing(progress: 0.65, size: 120, lineWidth: 12)
                    Text("Medium")
                        .font(.caption2)
                }

                VStack(spacing: 8) {
                    GoalProgressRing(progress: 0.65, size: 160, lineWidth: 16)
                    Text("Large")
                        .font(.caption2)
                }
            }
        }
        .padding()
    }
}

@available(iOS 26.0, *)
#Preview("Compact Ring (No Percentage)") {
    HStack(spacing: 20) {
        GoalProgressRing(progress: 0.30, size: 60, lineWidth: 6, showPercentage: false)
        GoalProgressRing(progress: 0.65, size: 60, lineWidth: 6, showPercentage: false)
        GoalProgressRing(progress: 1.0, size: 60, lineWidth: 6, showPercentage: false)
    }
    .padding()
}
