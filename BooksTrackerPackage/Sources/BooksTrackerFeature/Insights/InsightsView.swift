import SwiftUI
import SwiftData

/// Main Insights landing page - 4th tab in app
/// Displays diversity statistics and reading stats
@MainActor
public struct InsightsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.iOS26ThemeStore) private var themeStore

    @State private var diversityStats: DiversityStats?
    @State private var readingStats: ReadingStats?
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
                // CRITICAL: Clear cached stats and reload when library is reset
                // Prevents crash from accessing deleted Author objects
                diversityStats = nil
                readingStats = nil
                // Don't reload stats immediately - library is empty after reset
                // Stats will reload automatically via .onAppear when user adds books
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
                        print("Tapped: \(stat.title)")
                    }
                }

                // Diversity section
                diversitySection

                // Reading stats section
                if let reading = readingStats {
                    ReadingStatsSection(stats: reading, selectedPeriod: $selectedPeriod)
                }
            }
            .padding()
        }
        .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        .scrollPosition($scrollPosition)
    }

    private var diversitySection: some View {
        VStack(spacing: 20) {
            if let diversity = diversityStats {
                // Cultural regions chart
                CulturalRegionsChart(stats: diversity.culturalRegionStats) { region in
                    // TODO: Filter library (Phase 4)
                    print("Tapped region: \(region.displayName)")
                }

                // Gender chart
                GenderDonutChart(
                    stats: diversity.genderStats,
                    totalAuthors: diversity.totalAuthors
                ) { gender in
                    // TODO: Filter library (Phase 4)
                    print("Tapped gender: \(gender.displayName)")
                }

                // Language tags
                LanguageTagCloud(stats: diversity.languageStats) { language in
                    // TODO: Filter library (Phase 4)
                    print("Tapped language: \(language)")
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

    private func loadStatistics() async {
        #if DEBUG
        let startTime = Date()
        #endif

        isLoading = true
        errorMessage = nil

        do {
            // Calculate diversity stats
            diversityStats = try DiversityStats.calculate(from: modelContext)

            // Calculate reading stats for selected period
            readingStats = try await ReadingStats.calculate(from: modelContext, period: selectedPeriod)

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
