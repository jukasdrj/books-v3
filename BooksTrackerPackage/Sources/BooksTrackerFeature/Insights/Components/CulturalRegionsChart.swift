import SwiftUI
import Charts

/// Horizontal bar chart showing cultural region distribution
/// Highlights marginalized regions in theme color
@MainActor
public struct CulturalRegionsChart: View {
    let stats: [DiversityStats.RegionStat]
    let onRegionTap: (CulturalRegion) -> Void

    @Environment(iOS26ThemeStore.self) private var themeStore

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cultural Regions")
                .font(.title3.bold())
                .foregroundStyle(.primary)

            if stats.isEmpty {
                emptyState
            } else {
                chart
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chart: some View {
        Chart {
            ForEach(stats) { stat in
                BarMark(
                    x: .value("Books", stat.count),
                    y: .value("Region", stat.region.shortName)
                )
                .foregroundStyle(stat.isMarginalized ? themeStore.primaryColor : Color.secondary.opacity(0.6))
                .cornerRadius(4)
                .annotation(position: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("\(stat.count)")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        if stat.isMarginalized {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundStyle(themeStore.primaryColor)
                                .accessibilityLabel("Marginalized voice")
                        }
                    }
                }
                .accessibilityLabel("\(stat.region.displayName): \(stat.count) books")
                .accessibilityValue(stat.isMarginalized ? "Marginalized region" : "")
            }
        }
        .chartXAxis(.hidden) // Cleaner on mobile
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let regionName = value.as(String.self) {
                        Text(regionName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartLegend(.hidden)
        .frame(height: CGFloat(stats.count) * 30 + 40) // Dynamic height
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Cultural regions chart")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "globe")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No regional data yet")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Add books with author info to see diversity breakdown")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}

// MARK: - Preview

#Preview("Cultural Regions Chart") {
    @Previewable @State var themeStore = iOS26ThemeStore()

    let sampleStats: [DiversityStats.RegionStat] = [
        .init(region: .northAmerica, count: 45, total: 100),
        .init(region: .europe, count: 30, total: 100),
        .init(region: .africa, count: 12, total: 100),
        .init(region: .asia, count: 8, total: 100),
        .init(region: .indigenous, count: 3, total: 100),
        .init(region: .southAmerica, count: 2, total: 100)
    ]

    return ScrollView {
        CulturalRegionsChart(stats: sampleStats) { region in
            print("Tapped region: \(region.displayName)")
        }
        .padding()
    }
    .environment(themeStore)
}
