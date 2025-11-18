import SwiftUI

/// Statistics display for bookshelf scanning progress and results
/// Shows real-time progress during scanning and final statistics when complete
@available(iOS 26.0, *)
struct ScanStatisticsView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    let scanState: BookshelfScanModel.ScanState
    let currentProgress: Double
    let currentStage: String
    let detectedCount: Int
    let confirmedCount: Int
    let uncertainCount: Int

    var body: some View {
        VStack(spacing: 12) {
            Text("Scan Progress")
                .font(.headline)
                .foregroundStyle(.primary)

            // Real-time WebSocket progress (when processing)
            if scanState == .processing {
                VStack(spacing: 12) {
                    // Progress bar
                    ProgressView(value: currentProgress, total: 1.0)
                        .tint(themeStore.primaryColor)

                    // Stage label
                    Text(currentStage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    // Percentage
                    Text("\(Int(currentProgress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }

            // Statistics (when completed)
            if scanState == .completed {
                HStack(spacing: 20) {
                    statisticBadge(
                        icon: "books.vertical.fill",
                        value: "\(detectedCount)",
                        label: "Detected"
                    )

                    statisticBadge(
                        icon: "checkmark.circle.fill",
                        value: "\(confirmedCount)",
                        label: "Ready"
                    )

                    statisticBadge(
                        icon: "questionmark.circle.fill",
                        value: "\(uncertainCount)",
                        label: "Review"
                    )
                }
            }
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        }
    }

    private func statisticBadge(icon: String, value: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(themeStore.primaryColor)

            Text(value)
                .font(.title3.bold())
                .foregroundStyle(.primary)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
