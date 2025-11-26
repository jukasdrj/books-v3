import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("Progressive Profiling Gamification Integration Tests")
struct ProgressiveProfilingGamificationTests {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var readingSessionService: ReadingSessionService!
    var diversityStatsService: DiversityStatsService!
    var curatorPointsService: CuratorPointsService!
    
    /// Initializes the test suite with all required services
    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            ReadingSession.self, EnhancedDiversityStats.self, CuratorPoints.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext
        readingSessionService = ReadingSessionService(modelContext: modelContext)
        diversityStatsService = DiversityStatsService(modelContext: modelContext)
        curatorPointsService = CuratorPointsService(modelContext: modelContext)
    }
    
    // MARK: - Test Helpers
    
    /// Creates a complete work with author and library entry
    private func createTestWork(
        title: String,
        authorName: String,
        culturalRegion: CulturalRegion? = nil,
        gender: AuthorGender = .unknown
    ) throws -> (work: Work, entry: UserLibraryEntry, edition: Edition) {
        let author = Author(name: authorName, culturalRegion: culturalRegion, gender: gender)
        modelContext.insert(author)
        
        let work = Work(title: title)
        modelContext.insert(work)
        work.authors = [author]
        
        let edition = Edition()
        edition.pageCount = 300
        modelContext.insert(edition)
        edition.work = work
        
        let entry = UserLibraryEntry(readingStatus: .reading)
        modelContext.insert(entry)
        entry.work = work
        entry.edition = edition
        
        try modelContext.save()
        return (work, entry, edition)
    }
    
    /// Simulates a reading session by manipulating start time
    private func simulateSession(for entry: UserLibraryEntry, durationMinutes: Int, endPage: Int) throws -> ReadingSession {
        try readingSessionService.startSession(for: entry)
        
        guard let session = readingSessionService.getCurrentSession() else {
            throw SessionError.noActiveSession
        }
        
        // Adjust start time to simulate elapsed time
        session.date = Date().addingTimeInterval(TimeInterval(-durationMinutes * 60))
        
        let completedSession = try readingSessionService.endSession(endPage: endPage)
        return completedSession
    }
    
    // MARK: - Gamification Flow Tests
    
    @Test("Complete gamification flow: session → enrichment → points → completion update")
    func test_complete_gamification_flow() async throws {
        // 1. Create work with missing diversity data
        let (work, entry, _) = try createTestWork(
            title: "Test Book",
            authorName: "Unknown Author"
        )
        
        // Verify initial state - no points
        let initialPoints = try await curatorPointsService.getTotalPoints()
        #expect(initialPoints == 0)
        
        // 2. Complete a reading session (>= 5 minutes to trigger enrichment)
        let session = try simulateSession(for: entry, durationMinutes: 10, endPage: 100)
        
        // 3. Verify enrichment prompt should be shown
        let shouldPrompt = try await readingSessionService.shouldShowEnrichmentPrompt(for: session)
        #expect(shouldPrompt == true)
        
        // 4. Record enrichment shown
        try await readingSessionService.recordEnrichmentShown(for: session)
        
        // 5. Simulate user contributing cultural region data
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "culturalOrigins",
            value: "African"
        )
        
        // 6. Award curator points for the contribution
        let pointsAwarded = try await curatorPointsService.awardPoints(for: .culturalRegion)
        #expect(pointsAwarded == 15) // Cultural region = 15 points
        
        // 7. Verify total points updated
        let totalPoints = try await curatorPointsService.getTotalPoints()
        #expect(totalPoints == 15)
        
        // 8. Verify completion percentage increased
        let completionPercentage = try await diversityStatsService.fetchCompletionPercentage()
        #expect(completionPercentage > 0)
        
        // 9. Verify enrichment completed flag can be set
        try await readingSessionService.recordEnrichmentCompleted(for: session)
        #expect(session.enrichmentCompleted == true)
    }
    
    @Test("Cascade bonus: author-level contribution awards bonus points")
    func test_cascade_bonus_multiple_books() async throws {
        // 1. Create 3 books by the same author
        let author = Author(name: "Prolific Author", culturalRegion: nil, gender: .unknown)
        modelContext.insert(author)
        
        var works: [Work] = []
        for i in 1...3 {
            let work = Work(title: "Book \(i)")
            modelContext.insert(work)
            work.authors = [author]
            works.append(work)
            
            let edition = Edition()
            modelContext.insert(edition)
            edition.work = work
            
            let entry = UserLibraryEntry(readingStatus: .reading)
            modelContext.insert(entry)
            entry.work = work
            entry.edition = edition
        }
        
        try modelContext.save()
        
        // 2. Complete session for first book
        let firstEntry = works[0].userEntry!
        let session = try simulateSession(for: firstEntry, durationMinutes: 10, endPage: 50)
        try await readingSessionService.recordEnrichmentShown(for: session)
        
        // 3. Award points with cascade bonus (3 works affected)
        let pointsAwarded = try await curatorPointsService.awardPoints(for: .culturalRegion, cascadeCount: 3)
        
        // Base 15 + (2 extra works × 5) = 25 points
        #expect(pointsAwarded == 25)
        
        let totalPoints = try await curatorPointsService.getTotalPoints()
        #expect(totalPoints == 25)
    }
    
    @Test("Multiple contributions across different dimensions accumulate")
    func test_multiple_dimension_contributions() async throws {
        let (work, entry, _) = try createTestWork(
            title: "Multi-dimension Book",
            authorName: "Multi Author"
        )
        
        let session = try simulateSession(for: entry, durationMinutes: 10, endPage: 50)
        try await readingSessionService.recordEnrichmentShown(for: session)
        
        // Contribute to multiple dimensions
        
        // 1. Cultural region (15 points)
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "culturalOrigins",
            value: "Asian"
        )
        _ = try await curatorPointsService.awardPoints(for: .culturalRegion)
        
        // 2. Gender (10 points)
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "genderDistribution",
            value: "Female"
        )
        _ = try await curatorPointsService.awardPoints(for: .authorGender)
        
        // 3. Language (10 points)
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "translationStatus",
            value: "Japanese"
        )
        _ = try await curatorPointsService.awardPoints(for: .originalLanguage)
        
        // Verify total: 15 + 10 + 10 = 35
        let totalPoints = try await curatorPointsService.getTotalPoints()
        #expect(totalPoints == 35)
        
        // Verify breakdown
        let breakdown = try await curatorPointsService.getPointsBreakdown()
        #expect(breakdown[.culturalRegion] == 15)
        #expect(breakdown[.authorGender] == 10)
        #expect(breakdown[.originalLanguage] == 10)
    }
    
    @Test("Completion percentage increases after enrichment")
    func test_completion_percentage_increases() async throws {
        // 1. Create work with all data missing
        let (work, entry, _) = try createTestWork(
            title: "Incomplete Book",
            authorName: "Incomplete Author"
        )
        
        // Get baseline completion
        let initialCompletion = try await diversityStatsService.fetchCompletionPercentage()
        
        // 2. Complete session
        let session = try simulateSession(for: entry, durationMinutes: 10, endPage: 50)
        try await readingSessionService.recordEnrichmentShown(for: session)
        
        // 3. Add cultural data
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "culturalOrigins",
            value: "African"
        )
        
        // 4. Check completion increased
        let afterCulturalCompletion = try await diversityStatsService.fetchCompletionPercentage()
        #expect(afterCulturalCompletion > initialCompletion)
        
        // 5. Add gender data
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "genderDistribution",
            value: "Male"
        )
        
        // 6. Check completion increased further
        let afterGenderCompletion = try await diversityStatsService.fetchCompletionPercentage()
        #expect(afterGenderCompletion > afterCulturalCompletion)
    }
    
    @Test("Points persist across service instances")
    func test_points_persistence() async throws {
        // Award points with original service
        _ = try await curatorPointsService.awardPoints(for: .authorGender)
        let firstTotal = try await curatorPointsService.getTotalPoints()
        #expect(firstTotal == 10)
        
        // Create new service instance (simulates app restart)
        let newService = CuratorPointsService(modelContext: modelContext)
        
        // Verify points persisted
        let secondTotal = try await newService.getTotalPoints()
        #expect(secondTotal == 10)
        
        // Award more points
        _ = try await newService.awardPoints(for: .culturalRegion, cascadeCount: 2)
        
        // Verify accumulation: 10 + 15 + 5 (cascade bonus) = 30
        let finalTotal = try await newService.getTotalPoints()
        #expect(finalTotal == 30)
    }
    
    @Test("Session below 5 minutes does not trigger enrichment but points can still be awarded manually")
    func test_short_session_manual_enrichment() async throws {
        let (work, entry, _) = try createTestWork(
            title: "Short Read",
            authorName: "Quick Author"
        )
        
        // Short session (< 5 minutes)
        let session = try simulateSession(for: entry, durationMinutes: 3, endPage: 20)
        
        // Should not trigger automatic enrichment
        let shouldPrompt = try await readingSessionService.shouldShowEnrichmentPrompt(for: session)
        #expect(shouldPrompt == false)
        
        // But user can still manually enrich data and earn points
        try await diversityStatsService.updateDiversityData(
            workId: work.persistentModelID,
            dimension: "genderDistribution",
            value: "Female"
        )
        
        let pointsAwarded = try await curatorPointsService.awardPoints(for: .authorGender)
        #expect(pointsAwarded == 10)
    }
}
