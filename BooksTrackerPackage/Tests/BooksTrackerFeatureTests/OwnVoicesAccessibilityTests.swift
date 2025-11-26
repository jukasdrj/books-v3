import Testing
import SwiftData
@testable import BooksTrackerFeature

@MainActor
@Suite("Own Voices and Accessibility Tests")
struct OwnVoicesAccessibilityTests {

    // MARK: - Work Model Tests

    @Test("Work can store isOwnVoices flag")
    func testWorkOwnVoicesFlag() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, configurations: config)
        let context = container.mainContext

        let work = Work(title: "The Color Purple")
        work.isOwnVoices = true
        
        context.insert(work)
        try context.save()

        #expect(work.isOwnVoices == true)
    }

    @Test("Work can store accessibility tags")
    func testWorkAccessibilityTags() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, configurations: config)
        let context = container.mainContext

        let work = Work(title: "Accessible Book")
        work.accessibilityTags = ["Large Print", "Dyslexia Friendly", "Audio Description"]
        
        context.insert(work)
        try context.save()

        #expect(work.accessibilityTags.count == 3)
        #expect(work.accessibilityTags.contains("Large Print"))
        #expect(work.accessibilityTags.contains("Dyslexia Friendly"))
        #expect(work.accessibilityTags.contains("Audio Description"))
    }

    @Test("Work isOwnVoices defaults to nil")
    func testWorkOwnVoicesDefaultsToNil() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, configurations: config)
        let context = container.mainContext

        let work = Work(title: "New Book")
        
        context.insert(work)
        try context.save()

        #expect(work.isOwnVoices == nil)
    }

    @Test("Work accessibility tags defaults to empty array")
    func testWorkAccessibilityTagsDefaultsToEmpty() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, configurations: config)
        let context = container.mainContext

        let work = Work(title: "New Book")
        
        context.insert(work)
        try context.save()

        #expect(work.accessibilityTags.isEmpty)
    }

    // MARK: - DiversityStatsService Tests

    @Test("DiversityStatsService calculates Own Voices metrics")
    func testDiversityStatsServiceOwnVoices() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, UserLibraryEntry.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        // Create test data
        let author = Author(name: "Alice Walker")
        context.insert(author)

        let work1 = Work(title: "The Color Purple")
        work1.isOwnVoices = true
        context.insert(work1)
        work1.addAuthor(author)

        let work2 = Work(title: "Another Book")
        work2.isOwnVoices = false
        context.insert(work2)
        work2.addAuthor(author)

        // Create library entries to make works count
        let entry1 = UserLibraryEntry(work: work1, readingStatus: .read)
        let entry2 = UserLibraryEntry(work: work2, readingStatus: .read)
        context.insert(entry1)
        context.insert(entry2)

        try context.save()

        // Calculate stats
        let service = DiversityStatsService(modelContext: context)
        let stats = try await service.calculateStats(period: .allTime)

        // Verify Own Voices tracking
        #expect(stats.totalBooks == 2)
        #expect(stats.booksWithOwnVoicesData == 2)
        #expect(stats.ownVoicesTheme["Own Voices"] == 1)
        #expect(stats.ownVoicesTheme["Not Own Voices"] == 1)
    }

    @Test("DiversityStatsService calculates Accessibility metrics")
    func testDiversityStatsServiceAccessibility() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, UserLibraryEntry.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        // Create test data
        let author = Author(name: "Test Author")
        context.insert(author)

        let work1 = Work(title: "Accessible Book")
        work1.accessibilityTags = ["Large Print", "Dyslexia Friendly"]
        context.insert(work1)
        work1.addAuthor(author)

        let work2 = Work(title: "Regular Book")
        context.insert(work2)
        work2.addAuthor(author)

        // Create library entries
        let entry1 = UserLibraryEntry(work: work1, readingStatus: .read)
        let entry2 = UserLibraryEntry(work: work2, readingStatus: .read)
        context.insert(entry1)
        context.insert(entry2)

        try context.save()

        // Calculate stats
        let service = DiversityStatsService(modelContext: context)
        let stats = try await service.calculateStats(period: .allTime)

        // Verify Accessibility tracking
        #expect(stats.totalBooks == 2)
        #expect(stats.booksWithAccessibilityData == 1)
        #expect(stats.nicheAccessibility["Has Accessibility Features"] == 1)
    }

    @Test("DiversityStatsService getMissingDataDimensions detects missing Own Voices")
    func testGetMissingDataDimensionsOwnVoices() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Author.self, configurations: config)
        let context = container.mainContext

        let work = Work(title: "Test Book")
        context.insert(work)
        try context.save()

        let service = DiversityStatsService(modelContext: context)
        let missing = try await service.getMissingDataDimensions(for: work.persistentModelID)

        #expect(missing.contains("ownVoicesTheme"))
    }

    @Test("DiversityStatsService getMissingDataDimensions detects missing Accessibility")
    func testGetMissingDataDimensionsAccessibility() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Author.self, configurations: config)
        let context = container.mainContext

        let work = Work(title: "Test Book")
        context.insert(work)
        try context.save()

        let service = DiversityStatsService(modelContext: context)
        let missing = try await service.getMissingDataDimensions(for: work.persistentModelID)

        #expect(missing.contains("nicheAccessibility"))
    }

    @Test("DiversityStatsService updateDiversityData sets Own Voices")
    func testUpdateDiversityDataOwnVoices() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        let work = Work(title: "Test Book")
        context.insert(work)
        try context.save()

        let service = DiversityStatsService(modelContext: context)
        try await service.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "ownVoicesTheme",
            value: "true"
        )

        #expect(work.isOwnVoices == true)
    }

    @Test("DiversityStatsService updateDiversityData sets Accessibility tags")
    func testUpdateDiversityDataAccessibility() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        let work = Work(title: "Test Book")
        context.insert(work)
        try context.save()

        let service = DiversityStatsService(modelContext: context)
        try await service.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "nicheAccessibility",
            value: "Large Print, Dyslexia Friendly, Audio Description"
        )

        #expect(work.accessibilityTags.count == 3)
        #expect(work.accessibilityTags.contains("Large Print"))
        #expect(work.accessibilityTags.contains("Dyslexia Friendly"))
        #expect(work.accessibilityTags.contains("Audio Description"))
    }

    @Test("EnhancedDiversityStats calculates Own Voices completion percentage")
    func testOwnVoicesCompletionPercentage() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, UserLibraryEntry.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        let author = Author(name: "Test Author")
        context.insert(author)

        // Create 4 works, 3 with Own Voices data
        for i in 1...4 {
            let work = Work(title: "Book \(i)")
            if i <= 3 {
                work.isOwnVoices = (i % 2 == 0)
            }
            context.insert(work)
            work.addAuthor(author)

            let entry = UserLibraryEntry(work: work, readingStatus: .read)
            context.insert(entry)
        }

        try context.save()

        let service = DiversityStatsService(modelContext: context)
        let stats = try await service.calculateStats(period: .allTime)

        // 3 out of 4 books have Own Voices data = 75%
        #expect(stats.ownVoicesCompletionPercentage == 75.0)
    }

    @Test("EnhancedDiversityStats calculates Accessibility completion percentage")
    func testAccessibilityCompletionPercentage() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, UserLibraryEntry.self, EnhancedDiversityStats.self,
            configurations: config
        )
        let context = container.mainContext

        let author = Author(name: "Test Author")
        context.insert(author)

        // Create 5 works, 2 with accessibility tags
        for i in 1...5 {
            let work = Work(title: "Book \(i)")
            if i <= 2 {
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

        // 2 out of 5 books have accessibility data = 40%
        #expect(stats.accessibilityCompletionPercentage == 40.0)
    }
}
