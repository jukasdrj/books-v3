import SwiftUI

/// Reading statistics section with time period picker and stat cards
@MainActor
public struct ReadingStatsSection: View {
    let stats: ReadingStats
    @Binding var selectedPeriod: TimePeriod

    @Environment(\.iOS26ThemeStore) private var themeStore

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section header
            Text("Reading Statistics")
                .font(.title2.bold())
                .foregroundStyle(.primary)

            // Time period picker
            timePeriodPicker

            // Stat cards grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                ForEach(stats.statCards) { card in
                    StatCardView(card: card)
                }
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var timePeriodPicker: some View {
        HStack(spacing: 0) {
            ForEach(TimePeriod.allCases.filter { $0 != .custom }, id: \.self) { period in
                Button {
                    selectedPeriod = period
                } label: {
                    Text(period.rawValue)
                        .font(.caption.bold())
                        .foregroundStyle(selectedPeriod == period ? .white : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedPeriod == period ?
                                AnyView(themeStore.primaryColor) :
                                AnyView(Color.clear)
                        )
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor
private struct StatCardView: View {
    let card: ReadingStats.StatCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: card.systemImage)
                .font(.title2)
                .foregroundStyle(card.color)

            Text(card.title)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(card.value)
                .font(.body.bold())
                .foregroundStyle(.primary)

            if !card.subtitle.isEmpty {
                Text(card.subtitle)
                    .font(.caption2)
                    .foregroundStyle(card.color)
            }

            if !card.detail.isEmpty {
                Text(card.detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(card.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(card.color.opacity(0.3), lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.title): \(card.value). \(card.subtitle). \(card.detail)")
    }
}

// MARK: - Preview

#Preview("Reading Stats Section") {
    PreviewContainer()
        .iOS26ThemeStore(iOS26ThemeStore())
}

@MainActor
private struct PreviewContainer: View {
    @State private var selectedPeriod: TimePeriod = .thisYear

    var body: some View {
        let mockStats = ReadingStats(
            pagesRead: 12456,
            booksCompleted: 42,
            booksInProgress: 3,
            averageReadingPace: 47.0,
            fastestReadingPace: 120.0,
            diversityScore: 7.8,
            regionsRepresented: 8,
            marginalizedVoicesPercentage: 45.0,
            period: .thisYear,
            comparisonToPreviousPeriod: 23.0
        )

        ScrollView {
            ReadingStatsSection(stats: mockStats, selectedPeriod: $selectedPeriod)
                .padding()
        }
    }
}
