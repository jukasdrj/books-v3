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
        let work1 = Work(title: "Test Book 1")
        let work2 = Work(title: "Test Book 2")

        modelContext.insert(work1)
        modelContext.insert(work2)

        // Add work1 to library, leave work2 out
        let entry = UserLibraryEntry(readingStatus: .toRead)
        modelContext.insert(entry)

        // Link entry to work (insert-before-relate)
        entry.work = work1
        work1.userLibraryEntries = [entry]

        let allWorks = [work1, work2]
        let filtered = service.filterLibraryWorks(from: allWorks, modelContext: modelContext)

        #expect(filtered.count == 1, "Should only include works in library")
        #expect(filtered.first?.title == "Test Book 1")
    }

    @Test("searchWorks filters by title")
    func testSearchWorksFiltersByTitle() throws {
        let service = LibraryFilterService()

        let modelContext = createTestModelContext()
        let work1 = Work(title: "Swift Programming")
        let work2 = Work(title: "Python for Beginners")

        modelContext.insert(work1)
        modelContext.insert(work2)

        let allWorks = [work1, work2]
        let results = service.searchWorks(allWorks, searchText: "Swift", modelContext: modelContext)

        #expect(results.count == 1)
        #expect(results.first?.title == "Swift Programming")
    }

    @Test("calculateDiversityScore computes correctly")
    func testCalculateDiversityScore() throws {
        let service = LibraryFilterService()

        let modelContext = createTestModelContext()

        // Create diverse authors - follow insert-before-relate pattern
        let author1 = Author(name: "Author 1", gender: .female, culturalRegion: .asia)
        let author2 = Author(name: "Author 2", gender: .male, culturalRegion: .europe)
        let author3 = Author(name: "Author 3", gender: .nonBinary, culturalRegion: .africa)

        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")
        let work3 = Work(title: "Book 3")

        // Insert all models first
        modelContext.insert(author1)
        modelContext.insert(author2)
        modelContext.insert(author3)
        modelContext.insert(work1)
        modelContext.insert(work2)
        modelContext.insert(work3)

        // Set relationships after insert
        work1.authors = [author1]
        work2.authors = [author2]
        work3.authors = [author3]

        let works = [work1, work2, work3]
        let score = service.calculateDiversityScore(for: works, modelContext: modelContext)

        #expect(score > 0.0, "Diversity score should be positive for diverse authors")
        #expect(score <= 100.0, "Diversity score should be <= 100")
    }
    
    @Test("filterLibraryWorks handles deleted objects gracefully")
    func testFilterLibraryWorksWithDeletedObjects() throws {
        let service = LibraryFilterService()
        let modelContext = createTestModelContext()
        
        // Create works with library entries
        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")
        modelContext.insert(work1)
        modelContext.insert(work2)
        
        let entry1 = UserLibraryEntry(readingStatus: .reading)
        let entry2 = UserLibraryEntry(readingStatus: .read)
        modelContext.insert(entry1)
        modelContext.insert(entry2)
        
        entry1.work = work1
        work1.userLibraryEntries = [entry1]
        entry2.work = work2
        work2.userLibraryEntries = [entry2]
        
        try modelContext.save()
        
        // Keep references to works
        let allWorks = [work1, work2]
        
        // Delete work2 (simulating library reset)
        modelContext.delete(work2)
        try modelContext.save()
        
        // Filter should exclude the deleted work without crashing
        let filtered = service.filterLibraryWorks(from: allWorks, modelContext: modelContext)
        
        #expect(filtered.count == 1, "Should only include non-deleted works")
        #expect(filtered.first?.title == "Book 1")
    }
    
    @Test("searchWorks handles deleted objects gracefully")
    func testSearchWorksWithDeletedObjects() throws {
        let service = LibraryFilterService()
        let modelContext = createTestModelContext()
        
        let work1 = Work(title: "Swift Programming")
        let work2 = Work(title: "Swift Advanced")
        modelContext.insert(work1)
        modelContext.insert(work2)
        
        try modelContext.save()
        
        let allWorks = [work1, work2]
        
        // Delete work2
        modelContext.delete(work2)
        try modelContext.save()
        
        // Search should work without crashing
        let results = service.searchWorks(allWorks, searchText: "Swift", modelContext: modelContext)
        
        #expect(results.count == 1, "Should only find non-deleted works")
        #expect(results.first?.title == "Swift Programming")
    }
    
    @Test("calculateDiversityScore handles deleted objects gracefully")
    func testCalculateDiversityScoreWithDeletedObjects() throws {
        let service = LibraryFilterService()
        let modelContext = createTestModelContext()
        
        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")
        modelContext.insert(work1)
        modelContext.insert(work2)
        
        let author1 = Author(name: "Author 1", gender: .female, culturalRegion: .asia)
        modelContext.insert(author1)
        work1.authors = [author1]
        
        try modelContext.save()
        
        let allWorks = [work1, work2]
        
        // Delete work2
        modelContext.delete(work2)
        try modelContext.save()
        
        // Calculation should work without crashing
        let score = service.calculateDiversityScore(for: allWorks, modelContext: modelContext)
        
        #expect(score >= 0.0, "Score should be non-negative")
    }

    // MARK: - Helpers

    private func createTestModelContext() -> ModelContext {
        let schema = Schema([Work.self, Author.self, UserLibraryEntry.self, Edition.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: configuration)
        return ModelContext(container)
    }
}
