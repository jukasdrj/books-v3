import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("CuratorPoints Service Tests")
struct CuratorPointsServiceTests {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var curatorService: CuratorPointsService!
    
    /// Initializes the test suite by setting up an in-memory ModelContainer and service instance
    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        modelContainer = try ModelContainer(
            for: CuratorPoints.self,
            configurations: config
        )
        modelContext = modelContainer.mainContext
        curatorService = CuratorPointsService(modelContext: modelContext)
    }
    
    // MARK: - Basic Point Awards
    
    @Test("Award points for author gender contribution")
    func test_award_points_author_gender() async throws {
        let awarded = try await curatorService.awardPoints(for: .authorGender)
        
        #expect(awarded == 10) // Base points for author gender
        
        let totalPoints = try await curatorService.getTotalPoints()
        #expect(totalPoints == 10)
    }
    
    @Test("Award points for cultural region contribution")
    func test_award_points_cultural_region() async throws {
        let awarded = try await curatorService.awardPoints(for: .culturalRegion)
        
        #expect(awarded == 15) // Base points for cultural region
        
        let totalPoints = try await curatorService.getTotalPoints()
        #expect(totalPoints == 15)
    }
    
    @Test("Award points for original language contribution")
    func test_award_points_original_language() async throws {
        let awarded = try await curatorService.awardPoints(for: .originalLanguage)
        
        #expect(awarded == 10)
        
        let totalPoints = try await curatorService.getTotalPoints()
        #expect(totalPoints == 10)
    }
    
    @Test("Award points for own voices contribution")
    func test_award_points_own_voices() async throws {
        let awarded = try await curatorService.awardPoints(for: .ownVoices)
        
        #expect(awarded == 20) // Higher value for own voices
        
        let totalPoints = try await curatorService.getTotalPoints()
        #expect(totalPoints == 20)
    }
    
    @Test("Award points for accessibility contribution")
    func test_award_points_accessibility() async throws {
        let awarded = try await curatorService.awardPoints(for: .accessibility)
        
        #expect(awarded == 10)
        
        let totalPoints = try await curatorService.getTotalPoints()
        #expect(totalPoints == 10)
    }
    
    @Test("Award bonus points for complete profile")
    func test_award_points_complete_profile() async throws {
        let awarded = try await curatorService.awardPoints(for: .completeAllFields)
        
        #expect(awarded == 50) // Bonus for completing all fields
        
        let totalPoints = try await curatorService.getTotalPoints()
        #expect(totalPoints == 50)
    }
    
    // MARK: - Cascade Bonuses
    
    @Test("Cascade bonus: single work has no bonus")
    func test_cascade_single_work_no_bonus() async throws {
        let awarded = try await curatorService.awardPoints(for: .authorGender, cascadeCount: 1)
        
        #expect(awarded == 10) // Just base points, no cascade bonus
    }
    
    @Test("Cascade bonus: multiple works adds +5 per extra work")
    func test_cascade_multiple_works_adds_bonus() async throws {
        // 3 works by same author
        let awarded = try await curatorService.awardPoints(for: .culturalRegion, cascadeCount: 3)
        
        // Base 15 + 2 extra works × 5 = 25 total
        #expect(awarded == 25)
        
        let totalPoints = try await curatorService.getTotalPoints()
        #expect(totalPoints == 25)
    }
    
    @Test("Cascade bonus: large cascade correctly calculates bonus")
    func test_cascade_large_bonus() async throws {
        // 10 works by same author
        let awarded = try await curatorService.awardPoints(for: .authorGender, cascadeCount: 10)
        
        // Base 10 + 9 extra works × 5 = 55 total
        #expect(awarded == 55)
    }
    
    // MARK: - Accumulation
    
    @Test("Multiple contributions accumulate correctly")
    func test_multiple_contributions_accumulate() async throws {
        // Award gender points
        _ = try await curatorService.awardPoints(for: .authorGender)
        var total = try await curatorService.getTotalPoints()
        #expect(total == 10)
        
        // Award cultural region points
        _ = try await curatorService.awardPoints(for: .culturalRegion)
        total = try await curatorService.getTotalPoints()
        #expect(total == 25) // 10 + 15
        
        // Award language points
        _ = try await curatorService.awardPoints(for: .originalLanguage)
        total = try await curatorService.getTotalPoints()
        #expect(total == 35) // 10 + 15 + 10
    }
    
    @Test("Points breakdown correctly tracks actions")
    func test_points_breakdown_by_action() async throws {
        // Award different types of points
        _ = try await curatorService.awardPoints(for: .authorGender)
        _ = try await curatorService.awardPoints(for: .culturalRegion, cascadeCount: 3)
        _ = try await curatorService.awardPoints(for: .authorGender) // Second gender award
        
        let breakdown = try await curatorService.getPointsBreakdown()
        
        // Gender: 10 + 10 = 20
        #expect(breakdown[.authorGender] == 20)
        
        // Cultural: 15 + (2 × 5) = 25
        #expect(breakdown[.culturalRegion] == 25)
        
        // Total: 45
        let total = try await curatorService.getTotalPoints()
        #expect(total == 45)
    }
    
    // MARK: - Persistence
    
    @Test("Points persist across service instances")
    func test_points_persist_across_instances() async throws {
        // Award points with first service instance
        _ = try await curatorService.awardPoints(for: .authorGender)
        let firstTotal = try await curatorService.getTotalPoints()
        #expect(firstTotal == 10)
        
        // Create new service instance
        let newService = CuratorPointsService(modelContext: modelContext)
        
        // Verify points are persisted
        let secondTotal = try await newService.getTotalPoints()
        #expect(secondTotal == 10)
        
        // Award more points with second instance
        _ = try await newService.awardPoints(for: .culturalRegion)
        let finalTotal = try await newService.getTotalPoints()
        #expect(finalTotal == 25)
    }
}
