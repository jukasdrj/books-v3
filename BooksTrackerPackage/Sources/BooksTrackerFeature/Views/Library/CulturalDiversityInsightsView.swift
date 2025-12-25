import SwiftUI
import SwiftData

// MARK: - Cultural Diversity Insights Sheet

@available(iOS 26.0, *)
struct CulturalDiversityInsightsView: View {
    let works: [Work]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 20) {
                    diversityMetricsSection
                    culturalRegionsSection
                    genderDistributionSection
                    readingGoalsSection
                }
                .padding()
                .scrollTargetLayout()
            }
            #if os(iOS)
            .scrollEdgeEffectStyle(.soft, for: .top)
            #endif
            .navigationTitle("Cultural Insights")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var diversityMetricsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Diversity Overview")
                    .font(.headline.bold())

                let metrics = calculateDiversityMetrics()

                HStack(spacing: 20) {
                    MetricView(
                        title: "Diverse Voices",
                        value: "\(Int(metrics.diversePercentage * 100))%",
                        color: metrics.diversePercentage > 0.3 ? .green : .orange
                    )

                    MetricView(
                        title: "Cultural Regions",
                        value: "\(metrics.regionCount)",
                        color: .blue
                    )

                    MetricView(
                        title: "Languages",
                        value: "\(metrics.languageCount)",
                        color: .purple
                    )
                }
            }
            .padding()
        }
        #if os(iOS)
        .glassEffect(.regular, tint: .blue.opacity(0.2))
        #endif
    }

    private var culturalRegionsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cultural Regions")
                    .font(.headline.bold())

                let regionStats = calculateRegionStatistics()

                ForEach(regionStats.sorted(by: { $0.value > $1.value }), id: \.key) { region, count in
                    HStack {
                        Text(region.emoji)
                            .font(.title2)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(region.displayName)
                                .font(.body.bold())

                            Text("\(count) books")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text("\(Int(Double(count) / Double(max(works.count, 1)) * 100))%")
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        #if os(iOS)
        .glassEffect(.regular, tint: .green.opacity(0.2))
        #endif
    }

    private var genderDistributionSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Author Gender Distribution")
                    .font(.headline.bold())

                let genderStats = calculateGenderStatistics()

                ForEach(genderStats.sorted(by: { $0.value > $1.value }), id: \.key) { gender, count in
                    HStack {
                        Image(systemName: gender.icon)
                            .font(.title3)
                            .foregroundStyle(.primary)
                            .frame(width: 24)

                        Text(gender.displayName)
                            .font(.body)

                        Spacer()

                        Text("\(count)")
                            .font(.callout.bold())
                            .foregroundStyle(.primary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding()
        }
        #if os(iOS)
        .glassEffect(.regular, tint: .purple.opacity(0.2))
        #endif
    }

    private var readingGoalsSection: some View {
        GlassEffectContainer {
            VStack(alignment: .leading, spacing: 12) {
                Text("Reading Goals Progress")
                    .font(.headline.bold())

                VStack(spacing: 8) {
                    ProgressView(value: 0.65) {
                        Text("Diverse Authors Goal")
                            .font(.subheadline)
                    }
                    .tint(.green)

                    ProgressView(value: 0.8) {
                        Text("Annual Reading Goal")
                            .font(.subheadline)
                    }
                    .tint(.blue)
                }
            }
            .padding()
        }
        #if os(iOS)
        .glassEffect(.regular, tint: .orange.opacity(0.2))
        #endif
    }

    // MARK: - Calculations

    private func calculateDiversityMetrics() -> (diversePercentage: Double, regionCount: Int, languageCount: Int) {
        let allAuthors = works.compactMap(\.authors).flatMap { $0 }

        var validCount = 0
        var diverseCount = 0
        var regions = Set<CulturalRegion>()

        for author in allAuthors {
            guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                continue
            }
            validCount += 1
            if author.representsMarginalizedVoices() {
                diverseCount += 1
            }
            if let region = author.culturalRegion {
                regions.insert(region)
            }
        }

        let diversePercentage = validCount > 0 ? Double(diverseCount) / Double(validCount) : 0.0
        let languages = Set(works.compactMap(\.originalLanguage))

        return (diversePercentage, regions.count, languages.count)
    }

    private func calculateRegionStatistics() -> [CulturalRegion: Int] {
        let allAuthors = works.compactMap(\.authors).flatMap { $0 }
        var regionCounts: [CulturalRegion: Int] = [:]

        for author in allAuthors {
            guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                continue
            }
            if let region = author.culturalRegion {
                regionCounts[region, default: 0] += 1
            }
        }

        return regionCounts
    }

    private func calculateGenderStatistics() -> [AuthorGender: Int] {
        let allAuthors = works.compactMap(\.authors).flatMap { $0 }
        var genderCounts: [AuthorGender: Int] = [:]

        for author in allAuthors {
            guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                continue
            }
            genderCounts[author.gender, default: 0] += 1
        }

        return genderCounts
    }
}
