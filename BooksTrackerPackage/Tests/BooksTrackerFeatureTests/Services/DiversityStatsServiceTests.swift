import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("DiversityStatsService Tests")
struct DiversityStatsServiceTests {

    let container: ModelContainer
    let context: ModelContext
    let service: DiversityStatsService

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, Author.self, EnhancedDiversityStats.self, UserSettings.self, ReadingSession.self, configurations: config)
        context = container.mainContext
        service = DiversityStatsService(modelContext: context)
    }

    @Test("calculateStats returns empty stats for empty library")
    func testCalculateStatsEmpty() async throws {
        let stats = try await service.calculateStats()

        #expect(stats.totalBooks == 0)
        #expect(stats.overallCompletionPercentage == 0.0)
    }

    @Test("calculateStats aggregates diversity data correctly")
    func testCalculateStatsFullData() async throws {
        // Setup UserSettings for English to test translation status
        let settings = UserSettings(userId: "default-user", primaryReadingLanguage: "english")
        context.insert(settings)

        // Create Author
        let author = Author(name: "Test Author", gender: .female, culturalRegion: .africa)
        context.insert(author)

        // Create Work
        let work = Work(title: "Test Book", originalLanguage: "Swahili", isOwnVoices: true)
        work.accessibilityTags = ["Dyslexia Friendly"]
        context.insert(work)
        work.authors = [author]

        // Create Edition
        let edition = Edition(originalLanguage: "Swahili") // Translated (vs English)
        context.insert(edition)
        edition.work = work

        // Create Entry
        _ = UserLibraryEntry.createOwnedEntry(for: work, edition: edition, status: .read, context: context)

        try context.save()

        let stats = try await service.calculateStats()

        #expect(stats.totalBooks == 1)

        // Cultural Origins
        #expect(stats.booksWithCulturalData == 1)
        #expect(stats.culturalOrigins["Africa"] == 1)

        // Gender
        #expect(stats.booksWithGenderData == 1)
        #expect(stats.genderDistribution["Female"] == 1)

        // Translation
        #expect(stats.booksWithTranslationData == 1)
        #expect(stats.translationStatus["Translated"] == 1)

        // Own Voices
        #expect(stats.booksWithOwnVoicesData == 1)
        #expect(stats.ownVoicesCount == 1)

        // Accessibility
        #expect(stats.booksWithAccessibilityData == 1)
        #expect(stats.accessibilityTags["Dyslexia Friendly"] == 1)

        #expect(stats.overallCompletionPercentage == 100.0)
    }

    @Test("fetchCompletionPercentage returns correct value")
    func testFetchCompletionPercentage() async throws {
        // Just rely on calculateStats populating the DB
        let settings = UserSettings(userId: "default-user", primaryReadingLanguage: "english")
        context.insert(settings)

        let work = Work(title: "Book")
        context.insert(work)
        _ = UserLibraryEntry.createWishlistEntry(for: work, context: context)
        try context.save()

        // Should be 0% as no data filled
        let percentage = try await service.fetchCompletionPercentage()
        #expect(percentage == 0.0)
    }

    @Test("getMissingDataDimensions identifies missing fields")
    func testGetMissingDataDimensions() async throws {
        let work = Work(title: "Incomplete Book")
        context.insert(work)
        let entry = UserLibraryEntry.createWishlistEntry(for: work, context: context)
        try context.save()

        let missing = try await service.getMissingDataDimensions(for: entry.persistentModelID)

        #expect(missing.contains("culturalOrigins"))
        #expect(missing.contains("genderDistribution"))
        #expect(missing.contains("translationStatus")) // Edition is nil
        #expect(missing.contains("ownVoicesCount"))
        #expect(missing.contains("accessibilityTags"))
    }

    @Test("updateDiversityData updates dimensions correctly")
    func testUpdateDiversityData() async throws {
        // Setup
        let settings = UserSettings(userId: "default-user", primaryReadingLanguage: "english")
        context.insert(settings)

        let author = Author(name: "Author")
        context.insert(author)

        let work = Work(title: "Book")
        context.insert(work)
        work.authors = [author]

        let edition = Edition()
        context.insert(edition)
        edition.work = work

        let entry = UserLibraryEntry.createOwnedEntry(for: work, edition: edition, context: context)
        try context.save()

        // Update Cultural Origin
        try await service.updateDiversityData(entryId: entry.persistentModelID, dimension: "culturalOrigins", value: "Africa")

        #expect(work.primaryAuthor?.culturalRegion == .africa)

        // Update Gender
        try await service.updateDiversityData(entryId: entry.persistentModelID, dimension: "genderDistribution", value: "Female")

        #expect(work.primaryAuthor?.gender == .female)

        // Update Translation (Language)
        try await service.updateDiversityData(entryId: entry.persistentModelID, dimension: "translationStatus", value: "French")

        #expect(edition.originalLanguage == "French")

        // Update Own Voices
        try await service.updateDiversityData(entryId: entry.persistentModelID, dimension: "ownVoicesCount", value: true)

        #expect(work.isOwnVoices == true)

        // Update Accessibility
        try await service.updateDiversityData(entryId: entry.persistentModelID, dimension: "accessibilityTags", value: "Large Print")

        #expect(work.accessibilityTags.contains("Large Print"))
    }
}
