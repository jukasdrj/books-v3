import Testing
import SwiftData
@testable import BooksTrackerFeature

@MainActor
@Suite("Diversity Radar Integration Tests")
struct DiversityRadarIntegrationTests {

    @Test("Complete flow: Add Own Voices and Accessibility data, verify stats update")
    func testCompleteOwnVoicesAccessibilityFlow() async throws {
        // Setup in-memory container with all required models
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, UserLibraryEntry.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        // Create a work with author
        let author = Author(name: "Octavia Butler", gender: .female, culturalRegion: .northAmerica)
        context.insert(author)

        let work = Work(title: "Kindred")
        context.insert(work)
        work.addAuthor(author)

        // Add to user's library
        let entry = UserLibraryEntry(work: work, readingStatus: .read)
        context.insert(entry)

        try context.save()

        // Step 1: Verify initial state has no Own Voices or Accessibility data
        let service = DiversityStatsService(modelContext: context)
        let initialMissing = try await service.getMissingDataDimensions(for: work.persistentModelID)
        
        #expect(initialMissing.contains("ownVoicesTheme"))
        #expect(initialMissing.contains("nicheAccessibility"))

        // Step 2: Add Own Voices data
        try await service.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "ownVoicesTheme",
            value: "true"
        )

        #expect(work.isOwnVoices == true)

        // Step 3: Add Accessibility data
        try await service.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "nicheAccessibility",
            value: "Large Print, Dyslexia Friendly"
        )

        #expect(work.accessibilityTags.count == 2)
        #expect(work.accessibilityTags.contains("Large Print"))
        #expect(work.accessibilityTags.contains("Dyslexia Friendly"))

        // Step 4: Verify missing dimensions updated
        let updatedMissing = try await service.getMissingDataDimensions(for: work.persistentModelID)
        
        #expect(!updatedMissing.contains("ownVoicesTheme"))
        #expect(!updatedMissing.contains("nicheAccessibility"))

        // Step 5: Verify stats calculation includes new data
        let stats = try await service.calculateStats(period: .allTime)

        #expect(stats.totalBooks == 1)
        #expect(stats.booksWithOwnVoicesData == 1)
        #expect(stats.booksWithAccessibilityData == 1)
        #expect(stats.ownVoicesTheme["Own Voices"] == 1)
        #expect(stats.nicheAccessibility["Has Accessibility Features"] == 1)
        
        // Step 6: Verify completion percentages
        #expect(stats.ownVoicesCompletionPercentage == 100.0)
        #expect(stats.accessibilityCompletionPercentage == 100.0)
    }

    @Test("Radar chart data model reflects all 5 dimensions")
    func testRadarChartDimensionsComplete() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, UserLibraryEntry.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        // Create fully populated work
        let author = Author(
            name: "Chimamanda Ngozi Adichie",
            gender: .female,
            culturalRegion: .africa
        )
        context.insert(author)

        let work = Work(title: "Americanah")
        work.originalLanguage = "English"
        work.isOwnVoices = true
        work.accessibilityTags = ["Large Print"]
        context.insert(work)
        work.addAuthor(author)

        let entry = UserLibraryEntry(work: work, readingStatus: .read)
        context.insert(entry)

        try context.save()

        // Calculate stats
        let service = DiversityStatsService(modelContext: context)
        let stats = try await service.calculateStats(period: .allTime)

        // Verify all 5 dimensions have data
        #expect(stats.culturalCompletionPercentage == 100.0)
        #expect(stats.genderCompletionPercentage == 100.0)
        #expect(stats.translationCompletionPercentage == 100.0)
        #expect(stats.ownVoicesCompletionPercentage == 100.0)
        #expect(stats.accessibilityCompletionPercentage == 100.0)

        // Create RadarChartData as InsightsView would
        let radarData = RadarChartData(dimensions: [
            RadarDimension(
                name: "Cultural",
                completionPercentage: stats.culturalCompletionPercentage,
                isComplete: stats.culturalCompletionPercentage >= 80
            ),
            RadarDimension(
                name: "Gender",
                completionPercentage: stats.genderCompletionPercentage,
                isComplete: stats.genderCompletionPercentage >= 80
            ),
            RadarDimension(
                name: "Translation",
                completionPercentage: stats.translationCompletionPercentage,
                isComplete: stats.translationCompletionPercentage >= 80
            ),
            RadarDimension(
                name: "Own Voices",
                completionPercentage: stats.ownVoicesCompletionPercentage,
                isComplete: stats.ownVoicesCompletionPercentage >= 80
            ),
            RadarDimension(
                name: "Accessibility",
                completionPercentage: stats.accessibilityCompletionPercentage,
                isComplete: stats.accessibilityCompletionPercentage >= 80
            )
        ])

        // Verify radar chart has all 5 dimensions at 100%
        #expect(radarData.dimensions.count == 5)
        #expect(radarData.dimensions.allSatisfy { $0.isComplete })
        #expect(radarData.overallCompletionPercentage == 100.0)
    }

    @Test("Progressive profiling detects missing Own Voices and Accessibility")
    func testProgressiveProfilingDetectsMissingData() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self,
            configurations: config
        )
        let context = container.mainContext

        let author = Author(name: "Test Author")
        context.insert(author)

        // Work with no diversity data
        let work = Work(title: "Incomplete Book")
        context.insert(work)
        work.addAuthor(author)

        try context.save()

        let service = DiversityStatsService(modelContext: context)
        let missing = try await service.getMissingDataDimensions(for: work.persistentModelID)

        // Should detect both Own Voices and Accessibility as missing
        #expect(missing.contains("ownVoicesTheme"))
        #expect(missing.contains("nicheAccessibility"))
    }

    @Test("Mixed library calculates correct completion percentages")
    func testMixedLibraryCompletionPercentages() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, UserLibraryEntry.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        let author = Author(name: "Test Author")
        context.insert(author)

        // Create 10 books with varying levels of Own Voices and Accessibility data
        for i in 1...10 {
            let work = Work(title: "Book \(i)")
            
            // Only books 1-6 have Own Voices data
            if i <= 6 {
                work.isOwnVoices = (i % 2 == 0)
            }
            
            // Only books 1-3 have Accessibility data
            if i <= 3 {
                work.accessibilityTags = ["Large Print"]
            }
            
            context.insert(work)
            work.addAuthor(author)

            let entry = UserLibraryEntry(work: work, readingStatus: .read)
            context.insert(entry)
        }

        try context.save()

        let service = DiversityStatsService(modelContext: context)
        let stats = try await service.calculateStats(period: .allTime)

        // Verify completion percentages
        // Own Voices: 6/10 = 60%
        #expect(stats.ownVoicesCompletionPercentage == 60.0)
        
        // Accessibility: 3/10 = 30%
        #expect(stats.accessibilityCompletionPercentage == 30.0)

        // Verify radar chart reflects incomplete data
        let radarData = RadarChartData(dimensions: [
            RadarDimension(
                name: "Own Voices",
                completionPercentage: stats.ownVoicesCompletionPercentage,
                isComplete: stats.ownVoicesCompletionPercentage >= 80
            ),
            RadarDimension(
                name: "Accessibility",
                completionPercentage: stats.accessibilityCompletionPercentage,
                isComplete: stats.accessibilityCompletionPercentage >= 80
            )
        ])

        // Both dimensions should be marked as incomplete (< 80%)
        #expect(!radarData.dimensions[0].isComplete)
        #expect(!radarData.dimensions[1].isComplete)
    }
}
