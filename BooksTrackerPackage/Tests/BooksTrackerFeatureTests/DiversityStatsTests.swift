import Testing
import SwiftData
@testable import BooksTrackerFeature

@MainActor
@Suite("DiversityStats Tests")
struct DiversityStatsTests {

    @Test("Calculate cultural region distribution")
    func testCulturalRegionDistribution() async throws {
        // Setup in-memory ModelContainer
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Author.self, configurations: config)
        let context = container.mainContext

        // Create test data
        let africanAuthor = Author(name: "Chinua Achebe", culturalRegion: .africa)
        let asianAuthor = Author(name: "Haruki Murakami", culturalRegion: .asia)
        let europeanAuthor = Author(name: "Jane Austen", culturalRegion: .europe)

        context.insert(africanAuthor)
        context.insert(asianAuthor)
        context.insert(europeanAuthor)

        let work1 = Work(title: "Things Fall Apart")
        work1.addAuthor(africanAuthor)

        let work2 = Work(title: "Norwegian Wood")
        work2.addAuthor(asianAuthor)

        let work3 = Work(title: "Pride and Prejudice")
        work3.addAuthor(europeanAuthor)

        context.insert(work1)
        context.insert(work2)
        context.insert(work3)

        try context.save()

        // Calculate stats
        let stats = try DiversityStats.calculate(from: context)

        // Verify
        #expect(stats.culturalRegionStats.count == 3)
        #expect(stats.culturalRegionStats.contains { $0.region == .africa && $0.count == 1 })
        #expect(stats.totalRegionsRepresented == 3)
    }

    @Test("Calculate gender distribution")
    func testGenderDistribution() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Author.self, configurations: config)
        let context = container.mainContext

        let femaleAuthor = Author(name: "Toni Morrison", gender: .female)
        let maleAuthor = Author(name: "James Baldwin", gender: .male)
        let nonBinaryAuthor = Author(name: "Sam Smith", gender: .nonBinary)

        context.insert(femaleAuthor)
        context.insert(maleAuthor)
        context.insert(nonBinaryAuthor)

        try context.save()

        let stats = try DiversityStats.calculate(from: context)

        #expect(stats.genderStats.count == 3)
        #expect(stats.genderStats.contains { $0.gender == .female && $0.count == 1 })
    }

    @Test("Calculate marginalized voices percentage")
    func testMarginalizedVoicesPercentage() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Author.self, configurations: config)
        let context = container.mainContext

        // Marginalized: female + African region
        let marginalizedAuthor = Author(name: "Chimamanda Adichie", gender: .female, culturalRegion: .africa)
        let nonMarginalizedAuthor = Author(name: "John Smith", gender: .male, culturalRegion: .northAmerica)

        context.insert(marginalizedAuthor)
        context.insert(nonMarginalizedAuthor)

        let work1 = Work(title: "Americanah")
        work1.addAuthor(marginalizedAuthor)

        let work2 = Work(title: "Generic Book")
        work2.addAuthor(nonMarginalizedAuthor)

        context.insert(work1)
        context.insert(work2)

        try context.save()

        let stats = try DiversityStats.calculate(from: context)

        #expect(stats.marginalizedVoicesPercentage == 50.0)
        #expect(stats.marginalizedVoicesCount == 1)
    }
}
