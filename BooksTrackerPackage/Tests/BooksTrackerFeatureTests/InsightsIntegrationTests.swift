import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("Insights Integration Tests")
struct InsightsIntegrationTests {

    @Test("Full pipeline: add books → calculate stats → verify UI data")
    func testFullInsightsPipeline() async throws {
        // Setup in-memory container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        // Create diverse library
        let africanAuthor = Author(name: "Ngũgĩ wa Thiong'o", gender: .male, culturalRegion: .africa)
        let asianAuthor = Author(name: "Arundhati Roy", gender: .female, culturalRegion: .asia)
        let indigenousAuthor = Author(name: "Louise Erdrich", gender: .female, culturalRegion: .indigenous)

        context.insert(africanAuthor)
        context.insert(asianAuthor)
        context.insert(indigenousAuthor)

        let work1 = Work(title: "Wizard of the Crow", originalLanguage: "Gikuyu")
        work1.addAuthor(africanAuthor)

        let work2 = Work(title: "The God of Small Things", originalLanguage: "English")
        work2.addAuthor(asianAuthor)

        let work3 = Work(title: "The Round House", originalLanguage: "English")
        work3.addAuthor(indigenousAuthor)

        context.insert(work1)
        context.insert(work2)
        context.insert(work3)

        let edition1 = Edition(pageCount: 768, work: work1)
        let edition2 = Edition(pageCount: 340, work: work2)
        let edition3 = Edition(pageCount: 321, work: work3)

        let entry1 = UserLibraryEntry.createOwnedEntry(for: work1, edition: edition1, status: .read)
        entry1.dateCompleted = Date()

        let entry2 = UserLibraryEntry.createOwnedEntry(for: work2, edition: edition2, status: .read)
        entry2.dateCompleted = Date()

        let entry3 = UserLibraryEntry.createOwnedEntry(for: work3, edition: edition3, status: .reading)
        entry3.dateStarted = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        entry3.currentPage = 160

        context.insert(edition1)
        context.insert(edition2)
        context.insert(edition3)
        context.insert(entry1)
        context.insert(entry2)
        context.insert(entry3)

        try context.save()

        // Calculate diversity stats
        let diversityStats = try DiversityStats.calculate(from: context)

        // Verify cultural regions
        #expect(diversityStats.totalRegionsRepresented == 3)
        #expect(diversityStats.culturalRegionStats.contains { $0.region == .africa })
        #expect(diversityStats.culturalRegionStats.contains { $0.region == .asia })
        #expect(diversityStats.culturalRegionStats.contains { $0.region == .indigenous })

        // Verify gender
        #expect(diversityStats.genderStats.contains { $0.gender == .female && $0.count == 2 })
        #expect(diversityStats.genderStats.contains { $0.gender == .male && $0.count == 1 })

        // Verify marginalized voices (all 3 are marginalized)
        #expect(diversityStats.marginalizedVoicesCount == 3)
        #expect(diversityStats.marginalizedVoicesPercentage == 100.0)

        // Verify languages
        #expect(diversityStats.totalLanguages == 2) // Gikuyu and English

        // Calculate reading stats
        let readingStats = try ReadingStats.calculate(from: context, period: .allTime)

        // Verify reading stats
        #expect(readingStats.booksCompleted == 2)
        #expect(readingStats.booksInProgress == 1)
        #expect(readingStats.pagesRead == 768 + 340) // Only completed books
        #expect(readingStats.diversityScore > 8.0) // High diversity
    }

    @Test("Hero stats contain all 4 metrics")
    func testHeroStatsCompleteness() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Author.self, configurations: config)
        let context = container.mainContext

        let author = Author(name: "Test Author", gender: .female, culturalRegion: .africa)
        context.insert(author)

        let work = Work(title: "Test Book", originalLanguage: "Swahili")
        work.addAuthor(author)
        context.insert(work)

        try context.save()

        let stats = try DiversityStats.calculate(from: context)

        #expect(stats.heroStats.count == 4)
        #expect(stats.heroStats.contains { $0.title == "Cultural Regions" })
        #expect(stats.heroStats.contains { $0.title == "Gender Representation" })
        #expect(stats.heroStats.contains { $0.title == "Marginalized Voices" })
        #expect(stats.heroStats.contains { $0.title == "Languages Read" })
    }
}
