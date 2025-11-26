import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("Diversity and Reading Session Integration Tests")
struct DiversitySessionIntegrationTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var readingSessionService: ReadingSessionService!
    var diversityStatsService: DiversityStatsService!

    /// Initializes the test suite by setting up an in-memory ModelContainer and service instances.
    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // Ensure all relevant models are included for the in-memory container
        modelContainer = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self, ReadingSession.self, EnhancedDiversityStats.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext
        readingSessionService = ReadingSessionService(modelContext: modelContext)
        diversityStatsService = DiversityStatsService(modelContext: modelContext)
    }

    // MARK: - Test Helpers

    /// Creates a Work, Author, and UserLibraryEntry with specified diversity data.
    /// Inserts them into the model context and saves.
    private func createWorkWithDiversityData(
        title: String,
        authorName: String,
        culturalRegion: CulturalRegion?,
        gender: AuthorGender,
        originalLanguage: String?
    ) throws -> UserLibraryEntry {
        let author = Author(name: authorName, culturalRegion: culturalRegion, gender: gender)
        modelContext.insert(author)

        let work = Work(title: title, originalLanguage: originalLanguage)
        modelContext.insert(work)
        work.addAuthor(author)

        let entry = UserLibraryEntry(work: work, currentPage: 0, totalPages: 200)
        modelContext.insert(entry)

        try modelContext.save()
        return entry
    }

    /// Simulates a reading session by creating a session with specified duration (in minutes)
    /// Directly sets the duration instead of actually waiting for time to pass (for test speed)
    private func simulateSession(for entry: UserLibraryEntry, durationMinutes: Int, endPage: Int) throws -> ReadingSession {
        try readingSessionService.startSession(for: entry)

        // Get the active session and manually set the start time to simulate elapsed time
        guard let session = readingSessionService.getCurrentSession() else {
            throw SessionError.noActiveSession
        }

        // Manually adjust the session start date to simulate the passage of time
        // This allows tests to run instantly without actual time delays
        let adjustedStartDate = Date().addingTimeInterval(TimeInterval(-durationMinutes * 60))
        session.date = adjustedStartDate

        let completedSession = try readingSessionService.endSession(endPage: endPage)
        return completedSession
    }

    // MARK: - Core Workflow Tests

    @Test("Complete workflow: start session, end session, diversity stats updated, enrichment prompted")
    func test_complete_session_workflow_updates_stats_and_prompts_enrichment() async throws {
        // 1. Setup: Create a work with some diversity data
        let entry = try createWorkWithDiversityData(
            title: "The Jungle Book",
            authorName: "Rudyard Kipling",
            culturalRegion: .europe,
            gender: .male,
            originalLanguage: "English"
        )

        // 2. Simulate a long reading session (>5 minutes)
        let session = try simulateSession(for: entry, durationMinutes: 6, endPage: 50)

        // 3. Verify session details
        #expect(session.durationMinutes == 6)
        #expect(session.startPage == 0)
        #expect(session.endPage == 50)
        #expect(entry.currentPage == 50)

        // 4. Verify enrichment prompt is triggered due to session duration
        let shouldPrompt = try await readingSessionService.shouldShowEnrichmentPrompt(for: session)
        #expect(shouldPrompt == true)

        // 5. Verify diversity stats are updated
        let stats = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(stats.totalBooks == 1)
        #expect(stats.culturalOrigins["European"] == 1)
        #expect(stats.genderDistribution["Male"] == 1)
        #expect(stats.translationStatus["Original Language"] == 1)
        #expect(stats.overallCompletionPercentage > 0)
    }

    @Test("Short session (<5 min) does not trigger enrichment prompt")
    func test_short_session_no_enrichment_prompt() async throws {
        let entry = try createWorkWithDiversityData(
            title: "Short Story",
            authorName: "Author S",
            culturalRegion: .asia,
            gender: .female,
            originalLanguage: "Japanese"
        )

        let session = try simulateSession(for: entry, durationMinutes: 1, endPage: 10)

        #expect(session.durationMinutes == 1)
        let shouldPrompt = try await readingSessionService.shouldShowEnrichmentPrompt(for: session)
        #expect(shouldPrompt == false)

        // Verify stats are still updated even for short sessions
        let stats = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(stats.totalBooks == 1)
        #expect(stats.culturalOrigins["Asian"] == 1)
    }

    @Test("Diversity data enrichment for missing dimensions recalculates stats")
    func test_diversity_data_enrichment_recalculates_stats() async throws {
        // 1. Setup: Create a work with missing diversity data
        let author = Author(name: "Unknown Author", culturalRegion: nil, gender: .unknown)
        modelContext.insert(author)
        let work = Work(title: "Mystery Novel", originalLanguage: nil, primaryAuthor: author)
        modelContext.insert(work)
        let entry = UserLibraryEntry(work: work, currentPage: 0, totalPages: 300)
        modelContext.insert(entry)
        try modelContext.save()

        // 2. Simulate a long session to trigger enrichment
        let session = try simulateSession(for: entry, durationMinutes: 7, endPage: 100)
        #expect(try await readingSessionService.shouldShowEnrichmentPrompt(for: session) == true)

        // 3. Check initial missing dimensions for the work
        var missingDimensions = try await diversityStatsService.getMissingDataDimensions(for: work.persistentModelID)
        #expect(missingDimensions.contains("culturalOrigins"))
        #expect(missingDimensions.contains("genderDistribution"))
        #expect(missingDimensions.contains("translationStatus"))

        // 4. Record enrichment shown for the session
        try await readingSessionService.recordEnrichmentShown(for: session)
        #expect(session.enrichmentPromptShown == true)
        #expect(try await readingSessionService.shouldShowEnrichmentPrompt(for: session) == false)

        // 5. Update diversity data for one dimension (culturalOrigins)
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "culturalOrigins",
            value: "African"
        )

        // 6. Verify stats are automatically recalculated and reflect the update
        let statsAfterCulturalUpdate = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(statsAfterCulturalUpdate.totalBooks == 1)
        #expect(statsAfterCulturalUpdate.culturalOrigins["African"] == 1)
        #expect(statsAfterCulturalUpdate.booksWithCulturalData == 1)
        #expect(statsAfterCulturalUpdate.booksWithGenderData == 0)
        #expect(statsAfterCulturalUpdate.booksWithTranslationData == 0)

        // 7. Check missing dimensions again - culturalOrigins should no longer be missing
        missingDimensions = try await diversityStatsService.getMissingDataDimensions(for: work.persistentModelID)
        #expect(!missingDimensions.contains("culturalOrigins"))
        #expect(missingDimensions.contains("genderDistribution"))
        #expect(missingDimensions.contains("translationStatus"))

        // 8. Update another dimension (genderDistribution)
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "genderDistribution",
            value: "Female"
        )
        let statsAfterGenderUpdate = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(statsAfterGenderUpdate.genderDistribution["Female"] == 1)
        #expect(statsAfterGenderUpdate.booksWithGenderData == 1)

        // 9. Record enrichment completed for the session
        try await readingSessionService.recordEnrichmentCompleted(for: session)
        #expect(session.enrichmentCompleted == true)
    }

    @Test("Multiple sessions for different works aggregate diversity stats correctly")
    func test_multiple_sessions_aggregate_stats() async throws {
        // 1. Session for Work 1 (European, Male, English)
        let entry1 = try createWorkWithDiversityData(
            title: "Work One", authorName: "Author A", culturalRegion: .europe, gender: .male, originalLanguage: "English"
        )
        _ = try simulateSession(for: entry1, durationMinutes: 10, endPage: 50)

        var stats = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(stats.totalBooks == 1)
        #expect(stats.culturalOrigins["European"] == 1)
        #expect(stats.genderDistribution["Male"] == 1)
        #expect(stats.translationStatus["Original Language"] == 1)

        // 2. Session for Work 2 (Asian, Female, Translated)
        let entry2 = try createWorkWithDiversityData(
            title: "Work Two", authorName: "Author B", culturalRegion: .asia, gender: .female, originalLanguage: "Japanese"
        )
        _ = try simulateSession(for: entry2, durationMinutes: 8, endPage: 75)

        stats = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(stats.totalBooks == 2)
        #expect(stats.culturalOrigins["European"] == 1)
        #expect(stats.culturalOrigins["Asian"] == 1)
        #expect(stats.genderDistribution["Male"] == 1)
        #expect(stats.genderDistribution["Female"] == 1)
        #expect(stats.translationStatus["Original Language"] == 1)
        #expect(stats.translationStatus["Translated"] == 1)

        // 3. Session for Work 3 (African, Unknown Gender, English)
        let entry3 = try createWorkWithDiversityData(
            title: "Work Three", authorName: "Author C", culturalRegion: .africa, gender: .unknown, originalLanguage: "English"
        )
        _ = try simulateSession(for: entry3, durationMinutes: 5, endPage: 30)

        stats = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(stats.totalBooks == 3)
        #expect(stats.culturalOrigins["European"] == 1)
        #expect(stats.culturalOrigins["Asian"] == 1)
        #expect(stats.culturalOrigins["African"] == 1)
        #expect(stats.genderDistribution["Male"] == 1)
        #expect(stats.genderDistribution["Female"] == 1)
        #expect(stats.genderDistribution.keys.count == 2)
        #expect(stats.translationStatus["Original Language"] == 2)
        #expect(stats.translationStatus["Translated"] == 1)
    }

    @Test("Fetch completion percentage calculates stats if none exist")
    func test_fetch_completion_percentage_calculates_if_needed() async throws {
        // Ensure no stats exist initially
        let initialStats = try modelContext.fetch(FetchDescriptor<EnhancedDiversityStats>())
        #expect(initialStats.isEmpty)

        // Create a work and entry
        _ = try createWorkWithDiversityData(
            title: "Test Book", authorName: "Test Author", culturalRegion: .europe, gender: .male, originalLanguage: "English"
        )

        // Call fetchCompletionPercentage - it should trigger calculateStats internally
        let percentage = try await diversityStatsService.fetchCompletionPercentage()

        // Verify stats are now created and percentage is > 0
        let newStats = try modelContext.fetch(FetchDescriptor<EnhancedDiversityStats>())
        #expect(!newStats.isEmpty)
        #expect(newStats.first?.totalBooks == 1)
        #expect(percentage > 0)
    }

    @Test("Session with work having complete diversity data")
    func test_session_with_complete_diversity_data() async throws {
        let entry = try createWorkWithDiversityData(
            title: "Fully Enriched", authorName: "Complete Author", culturalRegion: .northAmerica, gender: .nonBinary, originalLanguage: "Spanish"
        )

        let session = try simulateSession(for: entry, durationMinutes: 10, endPage: 100)
        #expect(session.durationMinutes == 10)

        // Enrichment prompt should still trigger based on duration
        #expect(try await readingSessionService.shouldShowEnrichmentPrompt(for: session) == true)

        // Missing dimensions should be empty
        let missingDimensions = try await diversityStatsService.getMissingDataDimensions(for: entry.work!.persistentModelID)
        #expect(missingDimensions.isEmpty)

        // Stats should reflect complete data
        let stats = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(stats.totalBooks == 1)
        #expect(stats.culturalOrigins["North American"] == 1)
        #expect(stats.genderDistribution["Non-binary"] == 1)
        #expect(stats.translationStatus["Translated"] == 1)
    }

    @Test("Record enrichment shown prevents subsequent prompts for the same session")
    func test_record_enrichment_shown_prevents_future_prompts() async throws {
        let entry = try createWorkWithDiversityData(
            title: "Prompt Test", authorName: "Prompt Author", culturalRegion: .asia, gender: .female, originalLanguage: "English"
        )
        let session = try simulateSession(for: entry, durationMinutes: 8, endPage: 50)

        // Initially, prompt should be true
        #expect(try await readingSessionService.shouldShowEnrichmentPrompt(for: session) == true)

        // Record that the prompt was shown
        try await readingSessionService.recordEnrichmentShown(for: session)

        // Now should return false
        #expect(try await readingSessionService.shouldShowEnrichmentPrompt(for: session) == false)
    }

    // MARK: - Edge Cases and Error Handling

    @Test("Attempting to start a session when one is already active throws an error")
    func test_start_session_already_active_error() async throws {
        let entry1 = try createWorkWithDiversityData(
            title: "Book One", authorName: "Author A", culturalRegion: .europe, gender: .male, originalLanguage: "English"
        )
        let entry2 = try createWorkWithDiversityData(
            title: "Book Two", authorName: "Author B", culturalRegion: .asia, gender: .female, originalLanguage: "Japanese"
        )

        try readingSessionService.startSession(for: entry1)
        #expect(readingSessionService.isSessionActive() == true)

        // Attempt to start another session while one is active
        await #expect(throws: SessionError.alreadyActive) {
            try readingSessionService.startSession(for: entry2)
        }

        // Clean up the active session
        _ = try readingSessionService.endSession(endPage: 10)
    }

    @Test("Attempting to end a session when none is active throws an error")
    func test_end_session_no_active_session_error() async throws {
        #expect(readingSessionService.isSessionActive() == false)

        await #expect(throws: SessionError.noActiveSession) {
            try readingSessionService.endSession(endPage: 10)
        }
    }

    @Test("Updating diversity data for non-existent work throws error")
    func test_update_diversity_data_work_not_found() async throws {
        let entry = try createWorkWithDiversityData(
            title: "Temp Book", authorName: "Temp Author", culturalRegion: .europe, gender: .male, originalLanguage: "English"
        )
        let workId = entry.work!.persistentModelID

        // Delete the work from the context
        modelContext.delete(entry.work!)
        try modelContext.save()

        // Try to update using the ID of the deleted work
        await #expect(throws: DiversityStatsError.workNotFound) {
            try await diversityStatsService.updateDiversityData(
                workId: workId,
                dimension: "culturalOrigins",
                value: "African"
            )
        }
    }

    @Test("Updating diversity data with invalid dimension throws error")
    func test_update_diversity_data_invalid_dimension() async throws {
        let entry = try createWorkWithDiversityData(
            title: "Valid Book", authorName: "Valid Author", culturalRegion: .europe, gender: .male, originalLanguage: "English"
        )
        let workId = entry.work!.persistentModelID

        await #expect(throws: DiversityStatsError.invalidDimension) {
            try await diversityStatsService.updateDiversityData(
                workId: workId,
                dimension: "nonExistentDimension",
                value: "someValue"
            )
        }
    }
    
    // MARK: - New Dimension Tests (Own Voices & Accessibility)
    
    @Test("Own Voices dimension aggregation works correctly")
    func test_own_voices_dimension_aggregation() async throws {
        // Create work with Own Voices set to true
        let author1 = Author(name: "Author 1", culturalRegion: .africa, gender: .female)
        modelContext.insert(author1)
        let work1 = Work(title: "Own Voices Book", originalLanguage: "English")
        work1.isOwnVoices = true
        modelContext.insert(work1)
        work1.addAuthor(author1)
        let entry1 = UserLibraryEntry(work: work1, currentPage: 0, totalPages: 200)
        modelContext.insert(entry1)
        
        // Create work with Own Voices set to false
        let author2 = Author(name: "Author 2", culturalRegion: .asia, gender: .male)
        modelContext.insert(author2)
        let work2 = Work(title: "Not Own Voices Book", originalLanguage: "Japanese")
        work2.isOwnVoices = false
        modelContext.insert(work2)
        work2.addAuthor(author2)
        let entry2 = UserLibraryEntry(work: work2, currentPage: 0, totalPages: 300)
        modelContext.insert(entry2)
        
        try modelContext.save()
        
        // Calculate stats
        let stats = try await diversityStatsService.calculateStats(period: .allTime)
        
        #expect(stats.totalBooks == 2)
        #expect(stats.ownVoicesTheme["Own Voices"] == 1)
        #expect(stats.ownVoicesTheme["Not Own Voices"] == 1)
        #expect(stats.booksWithOwnVoicesData == 2)
        #expect(stats.ownVoicesCompletionPercentage == 100.0)
    }
    
    @Test("Accessibility dimension aggregation works correctly")
    func test_accessibility_dimension_aggregation() async throws {
        // Create work with accessibility tags
        let author1 = Author(name: "Author 1", culturalRegion: .europe, gender: .female)
        modelContext.insert(author1)
        let work1 = Work(title: "Accessible Book", originalLanguage: "English")
        work1.accessibilityTags = ["Large Print", "Audio Available"]
        modelContext.insert(work1)
        work1.addAuthor(author1)
        let entry1 = UserLibraryEntry(work: work1, currentPage: 0, totalPages: 200)
        modelContext.insert(entry1)
        
        // Create work without accessibility tags
        let author2 = Author(name: "Author 2", culturalRegion: .asia, gender: .male)
        modelContext.insert(author2)
        let work2 = Work(title: "Standard Book", originalLanguage: "Chinese")
        modelContext.insert(work2)
        work2.addAuthor(author2)
        let entry2 = UserLibraryEntry(work: work2, currentPage: 0, totalPages: 300)
        modelContext.insert(entry2)
        
        try modelContext.save()
        
        // Calculate stats
        let stats = try await diversityStatsService.calculateStats(period: .allTime)
        
        #expect(stats.totalBooks == 2)
        #expect(stats.nicheAccessibility["Large Print"] == 1)
        #expect(stats.nicheAccessibility["Audio Available"] == 1)
        #expect(stats.booksWithAccessibilityData == 1)
        #expect(stats.accessibilityCompletionPercentage == 50.0)
    }
    
    @Test("Missing dimensions includes Own Voices and Accessibility")
    func test_missing_dimensions_includes_new_dimensions() async throws {
        let author = Author(name: "Test Author", culturalRegion: nil, gender: .unknown)
        modelContext.insert(author)
        let work = Work(title: "Test Book", originalLanguage: nil)
        // Leave isOwnVoices as nil and accessibilityTags empty
        modelContext.insert(work)
        work.addAuthor(author)
        try modelContext.save()
        
        let missingDimensions = try await diversityStatsService.getMissingDataDimensions(for: work.persistentModelID)
        
        #expect(missingDimensions.contains("culturalOrigins"))
        #expect(missingDimensions.contains("genderDistribution"))
        #expect(missingDimensions.contains("translationStatus"))
        #expect(missingDimensions.contains("ownVoicesTheme"))
        #expect(missingDimensions.contains("nicheAccessibility"))
    }
    
    @Test("Update Own Voices dimension updates stats")
    func test_update_own_voices_dimension() async throws {
        let author = Author(name: "Test Author", culturalRegion: .africa, gender: .female)
        modelContext.insert(author)
        let work = Work(title: "Test Book", originalLanguage: "English")
        modelContext.insert(work)
        work.addAuthor(author)
        let entry = UserLibraryEntry(work: work, currentPage: 0, totalPages: 200)
        modelContext.insert(entry)
        try modelContext.save()
        
        // Update Own Voices status
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "ownVoicesTheme",
            value: "Own Voices"
        )
        
        // Verify the field was updated
        #expect(work.isOwnVoices == true)
        
        // Verify stats reflect the update
        let stats = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(stats.ownVoicesTheme["Own Voices"] == 1)
        #expect(stats.booksWithOwnVoicesData == 1)
    }
    
    @Test("Update Accessibility dimension updates stats")
    func test_update_accessibility_dimension() async throws {
        let author = Author(name: "Test Author", culturalRegion: .asia, gender: .male)
        modelContext.insert(author)
        let work = Work(title: "Test Book", originalLanguage: "Japanese")
        modelContext.insert(work)
        work.addAuthor(author)
        let entry = UserLibraryEntry(work: work, currentPage: 0, totalPages: 300)
        modelContext.insert(entry)
        try modelContext.save()
        
        // Add accessibility tag
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "nicheAccessibility",
            value: "Dyslexia-Friendly"
        )
        
        // Verify the tag was added
        #expect(work.accessibilityTags.contains("Dyslexia-Friendly"))
        
        // Verify stats reflect the update
        let stats = try await diversityStatsService.calculateStats(period: .allTime)
        #expect(stats.nicheAccessibility["Dyslexia-Friendly"] == 1)
        #expect(stats.booksWithAccessibilityData == 1)
    }
    
    @Test("Overall completion percentage includes all 5 dimensions")
    func test_overall_completion_includes_all_dimensions() async throws {
        // Create work with only 3 of 5 dimensions filled
        let author = Author(name: "Test Author", culturalRegion: .europe, gender: .female)
        modelContext.insert(author)
        let work = Work(title: "Partial Book", originalLanguage: "English")
        // isOwnVoices = nil, accessibilityTags = []
        modelContext.insert(work)
        work.addAuthor(author)
        let entry = UserLibraryEntry(work: work, currentPage: 0, totalPages: 200)
        modelContext.insert(entry)
        try modelContext.save()
        
        let stats = try await diversityStatsService.calculateStats(period: .allTime)
        
        #expect(stats.totalBooks == 1)
        #expect(stats.booksWithCulturalData == 1)
        #expect(stats.booksWithGenderData == 1)
        #expect(stats.booksWithTranslationData == 1)
        #expect(stats.booksWithOwnVoicesData == 0)
        #expect(stats.booksWithAccessibilityData == 0)
        
        // 3 out of 5 dimensions filled = (3 / 5) * 100 = 60%
        #expect(stats.overallCompletionPercentage == 60.0)
    }
}
