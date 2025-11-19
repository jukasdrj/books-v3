import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Test suite for ImportService background import functionality
///
/// **Test Coverage:**
/// - Large imports (100+ books) without UI blocking
/// - CloudKit context merging (no data loss)
/// - Deduplication logic (skip duplicate books)
/// - Relationship creation (Work ↔ Author ↔ UserLibraryEntry ↔ Edition)
///
/// **Architecture:**
/// - Uses in-memory SwiftData container (no persistence between tests)
/// - Tests actor isolation and background processing
/// - Verifies automatic context merging between main and background contexts
///
/// - SeeAlso: `docs/plans/2025-11-12-phase-3-4-implementation-plan.md` Phase 3.4
@Suite("ImportService Tests")
@MainActor
struct ImportServiceTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    init() throws {
        // Create in-memory container for testing
        modelContainer = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
    }

    // MARK: - Large Import Tests

    @Test("Import 100 books completes successfully")
    func largeImport() async throws {
        let service = ImportService(modelContainer: modelContainer)
        let books = makeLargeDataset(count: 100)

        let result = try await service.importCSVBooks(books)

        #expect(result.successCount == 100)
        #expect(result.failedCount == 0)
        #expect(result.errors.isEmpty)
        #expect(result.totalProcessed == 100)
        #expect(result.duration > 0)

        // Verify books are actually in the database
        let descriptor = FetchDescriptor<Work>()
        let allWorks = try modelContext.fetch(descriptor)
        #expect(allWorks.count == 100)
    }

    @Test("Import creates all required relationships")
    func relationshipCreation() async throws {
        let service = ImportService(modelContainer: modelContainer)
        let books = [
            GeminiCSVImportJob.ParsedBook(
                title: "Test Book",
                author: "Test Author",
                isbn: "9781234567890",
                coverUrl: nil,
                publisher: "Test Publisher",
                publicationYear: 2020,
                enrichmentError: nil
            )
        ]

        let result = try await service.importCSVBooks(books)

        #expect(result.successCount == 1)

        // Verify Work exists
        let workDescriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == "Test Book" }
        )
        let works = try modelContext.fetch(workDescriptor)
        #expect(works.count == 1)

        let work = works[0]
        #expect(work.title == "Test Book")

        // Verify Author relationship
        #expect(work.authors?.count == 1)
        #expect(work.authors?.first?.name == "Test Author")

        // Verify UserLibraryEntry relationship
        #expect(work.userLibraryEntries?.count == 1)
        #expect(work.userLibraryEntries?.first?.readingStatus == .toRead)

        // Verify Edition relationship (when ISBN provided)
        let editionDescriptor = FetchDescriptor<Edition>(
            predicate: #Predicate { $0.isbn == "9781234567890" }
        )
        let editions = try modelContext.fetch(editionDescriptor)
        #expect(editions.count == 1)

        let edition = editions[0]
        #expect(edition.publisher == "Test Publisher")
        #expect(edition.work?.title == "Test Book")
    }

    // MARK: - CloudKit Merge Tests

    @Test("Background import merges with main context (no data loss)")
    func cloudKitMerge() async throws {
        // 1. Insert data via main context
        let mainWork = Work(title: "Main Context Book", originalLanguage: "English")
        modelContext.insert(mainWork)
        try modelContext.save()

        // 2. Import via background context
        let service = ImportService(modelContainer: modelContainer)
        let books = [
            GeminiCSVImportJob.ParsedBook(
                title: "Background Book",
                author: "Background Author",
                isbn: nil,
                publicationYear: nil,
                publisher: nil,
                coverUrl: nil
            )
        ]
        let result = try await service.importCSVBooks(books)

        #expect(result.successCount == 1)

        // 3. Verify both books exist in main context
        let descriptor = FetchDescriptor<Work>(
            sortBy: [SortDescriptor(\.title)]
        )
        let allWorks = try modelContext.fetch(descriptor)
        #expect(allWorks.count == 2)
        #expect(allWorks[0].title == "Background Book")
        #expect(allWorks[1].title == "Main Context Book")
    }

    // MARK: - Deduplication Tests

    @Test("Duplicate books are skipped (same title and author)")
    func deduplicationSameTitle() async throws {
        // 1. Import first book
        let service = ImportService(modelContainer: modelContainer)
        let books1 = [
            GeminiCSVImportJob.ParsedBook(
                title: "Harry Potter",
                author: "J.K. Rowling",
                isbn: nil,
                publicationYear: 1997,
                publisher: nil,
                coverUrl: nil
            )
        ]
        let result1 = try await service.importCSVBooks(books1)
        #expect(result1.successCount == 1)

        // 2. Attempt to import duplicate (case-insensitive match)
        let books2 = [
            GeminiCSVImportJob.ParsedBook(
                title: "harry potter",  // Lowercase
                author: "j.k. rowling",  // Lowercase
                isbn: nil,
                publicationYear: 1997,
                publisher: nil,
                coverUrl: nil
            )
        ]
        let result2 = try await service.importCSVBooks(books2)
        #expect(result2.successCount == 0)
        #expect(result2.failedCount == 1)  // Skipped

        // 3. Verify only one book exists
        let descriptor = FetchDescriptor<Work>()
        let allWorks = try modelContext.fetch(descriptor)
        #expect(allWorks.count == 1)
    }

    @Test("Different books with same title are not duplicates")
    func differentAuthors() async throws {
        let service = ImportService(modelContainer: modelContainer)
        let books = [
            GeminiCSVImportJob.ParsedBook(
                title: "Foundation",
                author: "Isaac Asimov",
                isbn: nil,
                publicationYear: 1951,
                publisher: nil,
                coverUrl: nil
            ),
            GeminiCSVImportJob.ParsedBook(
                title: "Foundation",
                author: "Peter Ackroyd",  // Different author!
                isbn: nil,
                publicationYear: 2011,
                publisher: nil,
                coverUrl: nil
            )
        ]

        let result = try await service.importCSVBooks(books)

        #expect(result.successCount == 2)
        #expect(result.failedCount == 0)

        // Verify both books exist
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == "Foundation" }
        )
        let allWorks = try modelContext.fetch(descriptor)
        #expect(allWorks.count == 2)
    }

    // MARK: - Edge Cases

    @Test("Empty book list returns zero results")
    func emptyImport() async throws {
        let service = ImportService(modelContainer: modelContainer)
        let books: [GeminiCSVImportJob.ParsedBook] = []

        let result = try await service.importCSVBooks(books)

        #expect(result.successCount == 0)
        #expect(result.failedCount == 0)
        #expect(result.errors.isEmpty)
        #expect(result.totalProcessed == 0)
    }

    @Test("Books without ISBN are still imported")
    func noISBN() async throws {
        let service = ImportService(modelContainer: modelContainer)
        let books = [
            GeminiCSVImportJob.ParsedBook(
                title: "Ancient Book",
                author: "Unknown Author",
                isbn: nil,  // No ISBN
                publicationYear: nil,
                publisher: nil,
                coverUrl: nil
            )
        ]

        let result = try await service.importCSVBooks(books)

        #expect(result.successCount == 1)

        // Verify Work exists but no Edition created
        let workDescriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == "Ancient Book" }
        )
        let works = try modelContext.fetch(workDescriptor)
        #expect(works.count == 1)

        // No Edition should be created
        let editionDescriptor = FetchDescriptor<Edition>()
        let editions = try modelContext.fetch(editionDescriptor)
        #expect(editions.isEmpty)
    }

    @Test("Books with publication year are saved correctly")
    func publicationYearStorage() async throws {
        let service = ImportService(modelContainer: modelContainer)
        let books = [
            GeminiCSVImportJob.ParsedBook(
                title: "1984",
                author: "George Orwell",
                isbn: nil,
                publicationYear: 1949,
                publisher: nil,
                coverUrl: nil
            )
        ]

        let result = try await service.importCSVBooks(books)

        #expect(result.successCount == 1)

        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == "1984" }
        )
        let works = try modelContext.fetch(descriptor)
        #expect(works.count == 1)
        #expect(works[0].firstPublicationYear == 1949)
    }

    // MARK: - Test Helpers

    /// Creates a large dataset for performance testing
    private func makeLargeDataset(count: Int) -> [GeminiCSVImportJob.ParsedBook] {
        (1...count).map { i in
            GeminiCSVImportJob.ParsedBook(
                title: "Book \(i)",
                author: "Author \(i)",
                isbn: nil,
                publicationYear: 2000 + (i % 25),
                publisher: "Publisher \(i % 10)",
                coverUrl: nil
            )
        }
    }
}
