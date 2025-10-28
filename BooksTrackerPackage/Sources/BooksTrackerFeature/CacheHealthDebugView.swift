import SwiftUI

/// Debug view for monitoring cache health metrics from backend
/// Displays real-time cache performance data collected from HTTP headers
@available(iOS 26.0, *)
@MainActor
public struct CacheHealthDebugView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @State private var metrics = CacheHealthMetrics.shared

    public init() {}

    public var body: some View {
        List {
            // MARK: - Cache Performance

            Section {
                MetricRow(
                    icon: "checkmark.circle.fill",
                    label: "Cache Hit Rate",
                    value: "\(Int(metrics.cacheHitRate * 100))%",
                    color: colorForHitRate(metrics.cacheHitRate)
                )

                MetricRow(
                    icon: "clock.fill",
                    label: "Avg Response Time",
                    value: "\(Int(metrics.averageResponseTime))ms",
                    color: colorForResponseTime(metrics.averageResponseTime)
                )

                MetricRow(
                    icon: "hourglass",
                    label: "Last Cache Age",
                    value: formatCacheAge(metrics.lastCacheAge),
                    color: .secondary
                )

            } header: {
                Text("Cache Performance")
            } footer: {
                Text("Metrics collected from backend X-Cache-* headers. Hit rate shows percentage of cached requests. Response time is rolling average of last 20 requests.")
            }

            // MARK: - Data Quality

            Section {
                MetricRow(
                    icon: "photo.fill",
                    label: "Image Availability",
                    value: "\(Int(metrics.imageAvailability * 100))%",
                    color: colorForQuality(metrics.imageAvailability)
                )

                MetricRow(
                    icon: "checkmark.seal.fill",
                    label: "Data Completeness",
                    value: "\(Int(metrics.dataCompleteness * 100))%",
                    color: colorForQuality(metrics.dataCompleteness)
                )

            } header: {
                Text("Data Quality")
            } footer: {
                Text("Image availability reflects cover image quality from backend. Data completeness shows percentage of books with both ISBN and cover image.")
            }

            // MARK: - Actions

            Section {
                Button {
                    metrics.reset()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                            .foregroundStyle(themeStore.primaryColor)

                        Text("Reset Metrics")
                    }
                }

                Button {
                    print(metrics.debugDescription)
                } label: {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(themeStore.primaryColor)

                        Text("Print Debug Info")
                    }
                }

            } footer: {
                Text("Reset clears all tracked metrics. Debug info prints detailed metrics to console.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Cache Health")
        .navigationBarTitleDisplayMode(.inline)
        .background(themeStore.backgroundGradient.ignoresSafeArea())
    }

    // MARK: - Helper Methods

    private func colorForHitRate(_ rate: Double) -> Color {
        if rate >= 0.7 { return .green }
        if rate >= 0.4 { return .orange }
        return .red
    }

    private func colorForResponseTime(_ time: TimeInterval) -> Color {
        if time <= 200 { return .green }
        if time <= 500 { return .orange }
        return .red
    }

    private func colorForQuality(_ quality: Double) -> Color {
        if quality >= 0.7 { return .green }
        if quality >= 0.4 { return .orange }
        return .red
    }

    private func formatCacheAge(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }
}

/// Reusable metric row component
@available(iOS 26.0, *)
private struct MetricRow: View {
    @Environment(\.iOS26ThemeStore) private var themeStore

    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(themeStore.primaryColor)
                .frame(width: 28)

            Text(label)
                .foregroundStyle(.primary)

            Spacer()

            Text(value)
                .font(.body.monospacedDigit())
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview {
    NavigationStack {
        CacheHealthDebugView()
    }
    .iOS26ThemeStore(iOS26ThemeStore())
}
