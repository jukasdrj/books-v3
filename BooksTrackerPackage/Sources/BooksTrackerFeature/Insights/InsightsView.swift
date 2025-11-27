import SwiftUI
import SwiftData

/// Main Insights landing page - 4th tab in app
/// Displays diversity statistics and reading stats
@MainActor
public struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var diversityStats: DiversityStats?
    @State private var enhancedDiversityStats: EnhancedDiversityStats?
    @State private var readingStats: ReadingStats?
    @State private var streakData: StreakData?
    @State private var selectedPeriod: TimePeriod = .thisYear
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var scrollPosition = ScrollPosition()

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                // Add themed background gradient for visual consistency
                themeStore.backgroundGradient
                    .ignoresSafeArea()

                Group {
                    if isLoading {
                        loadingView
                    } else if let error = errorMessage {
                        errorView(error)
                    } else {
                        contentView
                    }
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadStatistics()
            }
            .onChange(of: selectedPeriod) { _, newPeriod in
                Task {
                    await loadStatistics()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .libraryWasReset)) { _ in
                // CRITICAL: Immediately clear stats and reload.
                // The `reset: true` flag handles nil-ing out the data, preventing
                // the view from trying to render with stale, deleted objects.
                // The load might "fail" if the library is empty, but it will
                // correctly reflect the new empty state.
                Task {
                    await loadStatistics(reset: true)
                }
            }
        }
    }

    private var contentView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero stats card
                if let diversity = diversityStats {
                    HeroStatsCard(stats: diversity.heroStats) { stat in
                        // TODO: Jump to section (Phase 4)
                        #if DEBUG
                        print("Tapped: \(stat.title)")
                        #endif
                    }
                }

                // Diversity Completion Widget (Sprint 2)
                if #available(iOS 26.0, *) {
                    DiversityCompletionWidget(
                        onDimensionTapped: { dimension in
                            #if DEBUG
                            print("📊 Tapped dimension: \(dimension)")
                            #endif
                            // TODO: Navigate to dimension detail (Phase 4)
                        },
                        onFillMissingData: {
                            #if DEBUG
                            print("📊 Fill missing data tapped")
                            #endif
                            // TODO: Navigate to progressive profiling flow (Phase 4)
                        }
                    )
                }

                // Representation Radar Chart (Sprint 2)
                representationRadarSection

                // Diversity section (existing charts)
                diversitySection

                // Reading stats section
                if let reading = readingStats {
                    ReadingStatsSection(stats: reading, selectedPeriod: $selectedPeriod)
                }

                // Session analytics section
                if let streak = streakData {
                    sessionAnalyticsSection(streak: streak)
                }
            }
            .padding()
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .scrollPosition($scrollPosition)
    }

    private func transformStatsToMetrics(stats: EnhancedDiversityStats) -> [DiversityMetric] {
        return [
            .init(axis: .cultural, score: stats.culturalCompletionPercentage / 100.0, isMissing: stats.booksWithCulturalData == 0),
            .init(axis: .gender, score: stats.genderCompletionPercentage / 100.0, isMissing: stats.booksWithGenderData == 0),
            .init(axis: .translation, score: stats.translationCompletionPercentage / 100.0, isMissing: stats.booksWithTranslationData == 0),
            .init(axis: .ownVoices, score: stats.ownVoicesCompletionPercentage / 100.0, isMissing: stats.booksWithOwnVoicesData == 0),
            .init(axis: .accessibility, score: stats.accessibilityCompletionPercentage / 100.0, isMissing: stats.booksWithAccessibilityData == 0)
        ]
    }

    private func sessionAnalyticsSection(streak: StreakData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "flame.fill")
                    .font(.title3)
                    .foregroundColor(streak.isOnStreak ? .orange : .secondary)

                Text("Reading Streak")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 8)

            // Streak visualization
            StreakVisualizationView(streakData: streak)
        }
    }

    private var representationRadarSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section header
            HStack {
                Image(systemName: "chart.pie.fill")
                    .font(.title3)
                    .foregroundStyle(.purple)

                Text("Representation Overview")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
            }
            .padding(.bottom, 8)

            // Radar chart with diversity dimensions (using EnhancedDiversityStats)
            if let enhanced = enhancedDiversityStats {
                RadarChartView(metrics: transformStatsToMetrics(stats: enhanced))
                    .frame(height: 300)
                    .padding(.horizontal)
            }
        }
    }

    private var diversitySection: some View {
        VStack(spacing: 20) {
            if let diversity = diversityStats {
                // Cultural regions chart
                CulturalRegionsChart(stats: diversity.culturalRegionStats) { region in
                    // TODO: Filter library (Phase 4)
                    #if DEBUG
                    print("Tapped region: \(region.displayName)")
                    #endif
                }

                // Gender chart
                GenderDonutChart(
                    stats: diversity.genderStats,
                    totalAuthors: diversity.totalAuthors
                ) { gender in
                    // TODO: Filter library (Phase 4)
                    #if DEBUG
                    print("Tapped gender: \(gender.displayName)")
                    #endif
                }

                // Language tags
                LanguageTagCloud(stats: diversity.languageStats) { language in
                    // TODO: Filter library (Phase 4)
                    #if DEBUG
                    print("Tapped language: \(language)")
                    #endif
                }
            }
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(themeStore.primaryColor)

            Text("Calculating diversity insights...")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Unable to Load Insights", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Try Again") {
                Task { await loadStatistics() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Data Loading

    private func loadStatistics(reset: Bool = false) async {
        #if DEBUG
        let startTime = Date()
        #endif

        // If resetting, clear existing data immediately
        if reset {
            diversityStats = nil
            enhancedDiversityStats = nil
            readingStats = nil
            streakData = nil
        }

        isLoading = true
        errorMessage = nil

        do {
            // Calculate diversity stats
            diversityStats = try DiversityStats.calculate(from: modelContext)

            // Calculate enhanced diversity stats for radar chart (Sprint 2)
            let diversityService = DiversityStatsService(modelContext: modelContext)
            enhancedDiversityStats = try await diversityService.calculateStats(period: .allTime)

            // Calculate reading stats for selected period
            readingStats = try await ReadingStats.calculate(from: modelContext, period: selectedPeriod)

            // Load streak data
            let sessionService = SessionAnalyticsService(modelContext: modelContext)
            streakData = try sessionService.fetchStreakData(userId: "default-user")

            isLoading = false

            #if DEBUG
            let duration = Date().timeIntervalSince(startTime)
            print("📊 Insights calculation took \(String(format: "%.2f", duration * 1000))ms")
            #endif
        } catch {
            errorMessage = "Failed to calculate statistics: \(error.localizedDescription)"
            isLoading = false
        }
    }
}

// MARK: - Preview

#Preview("Insights View") {
    InsightsView()
        .modelContainer(for: [Work.self, Author.self, Edition.self, UserLibraryEntry.self])
        .iOS26ThemeStore(BooksTrackerFeature.iOS26ThemeStore())
}
