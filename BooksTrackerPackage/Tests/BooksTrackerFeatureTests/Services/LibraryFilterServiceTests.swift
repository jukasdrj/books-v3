import Testing
import Foundation
import SwiftData
@testable import BooksTrackerFeature

@Suite("LibraryFilterService")
@MainActor
struct LibraryFilterServiceTests {

    @Test("filterWorks returns only library works")
    func testFilterWorksReturnsLibraryOnly() throws {
        let service = LibraryFilterService()

        // Create test data
        let modelContext = createTestModelContext()
        let work1 = Work(title: "Test Book 1", authors: [])
        let work2 = Work(title: "Test Book 2", authors: [])

        // Add work1 to library, leave work2 out
        let entry = UserLibraryEntry(work: work1, readingStatus: .toRead)
        work1.userLibraryEntries = [entry]

        modelContext.insert(work1)
        modelContext.insert(work2)

        let allWorks = [work1, work2]
        let filtered = service.filterLibraryWorks(from: allWorks)

        #expect(filtered.count == 1, "Should only include works in library")
        #expect(filtered.first?.title == "Test Book 1")
    }

    @Test("searchWorks filters by title")
    func testSearchWorksFiltersByTitle() throws {
        let service = LibraryFilterService()

        let modelContext = createTestModelContext()
        let work1 = Work(title: "Swift Programming", authors: [])
        let work2 = Work(title: "Python for Beginners", authors: [])

        modelContext.insert(work1)
        modelContext.insert(work2)

        let allWorks = [work1, work2]
        let results = service.searchWorks(allWorks, searchText: "Swift")

        #expect(results.count == 1)
        #expect(results.first?.title == "Swift Programming")
    }

    @Test("calculateDiversityScore computes correctly")
    func testCalculateDiversityScore() throws {
        let service = LibraryFilterService()

        let modelContext = createTestModelContext()

        // Create diverse authors
        let author1 = Author(name: "Author 1", gender: .female, culturalRegion: .asia)
        let author2 = Author(name: "Author 2", gender: .male, culturalRegion: .europe)
        let author3 = Author(name: "Author 3", gender: .nonBinary, culturalRegion: .africa)

        let work1 = Work(title: "Book 1", authors: [author1])
        let work2 = Work(title: "Book 2", authors: [author2])
        let work3 = Work(title: "Book 3", authors: [author3])

        modelContext.insert(work1)
        modelContext.insert(work2)
        modelContext.insert(work3)

        let works = [work1, work2, work3]
        let score = service.calculateDiversityScore(for: works)

        #expect(score > 0.0, "Diversity score should be positive for diverse authors")
        #expect(score <= 100.0, "Diversity score should be <= 100")
    }

    // MARK: - Helpers

    private func createTestModelContext() -> ModelContext {
        let schema = Schema([Work.self, Author.self, UserLibraryEntry.self, Edition.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}
