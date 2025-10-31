import SwiftUI
import Charts

/// Donut chart showing gender distribution
/// Center displays total author count
@MainActor
public struct GenderDonutChart: View {
    let stats: [DiversityStats.GenderStat]
    let totalAuthors: Int
    let onGenderTap: (AuthorGender) -> Void

    @Environment(\.iOS26ThemeStore) private var themeStore

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gender Representation")
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
        Chart(stats, id: \.gender) { stat in
            SectorMark(
                angle: .value("Count", stat.count),
                innerRadius: .ratio(0.618), // Golden ratio
                angularInset: 2.0
            )
            .foregroundStyle(by: .value("Gender", stat.gender.displayName))
            .cornerRadius(8)
            .opacity(stat.gender == .unknown ? 0.3 : 1.0)
            .accessibilityLabel("\(stat.gender.displayName): \(stat.count) authors, \(String(format: "%.0f", stat.percentage))%")
        }
        .chartForegroundStyleScale([
            "Female": Color.pink,
            "Male": Color.blue,
            "Non-binary": Color.purple,
            "Other": Color.orange,
            "Unknown": Color.gray.opacity(0.3)
        ])
        .chartLegend(position: .bottom, spacing: 12) {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(stats.filter { $0.count > 0 }, id: \.gender) { stat in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(colorForGender(stat.gender))
                            .frame(width: 8, height: 8)

                        Text(stat.gender.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("\(String(format: "%.0f", stat.percentage))%")
                            .font(.caption.bold())
                            .foregroundStyle(.primary)

                        Spacer()
                    }
                }
            }
        }
        .chartBackground { proxy in
            GeometryReader { geometry in
                VStack(spacing: 4) {
                    Text("\(totalAuthors)")
                        .font(.title.bold())
                        .foregroundStyle(.primary)

                    Text("Authors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .frame(height: 280)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Gender distribution chart")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text("No gender data yet")
                .font(.body)
                .foregroundStyle(.secondary)

            Text("Add authors with gender information")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func colorForGender(_ gender: AuthorGender) -> Color {
        switch gender {
        case .female: return .pink
        case .male: return .blue
        case .nonBinary: return .purple
        case .other: return .orange
        case .unknown: return .gray.opacity(0.3)
        }
    }
}

// MARK: - Preview

#Preview("Gender Donut Chart") {
    let sampleStats: [DiversityStats.GenderStat] = [
        .init(gender: .female, count: 62, total: 100),
        .init(gender: .male, count: 35, total: 100),
        .init(gender: .nonBinary, count: 3, total: 100)
    ]

    ScrollView {
        GenderDonutChart(stats: sampleStats, totalAuthors: 100) { gender in
            print("Tapped gender: \(gender.displayName)")
        }
        .padding()
    }
    .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
