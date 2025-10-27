import Testing
import SwiftData
@testable import BooksTrackerFeature

@Suite("SwiftData Model Lifecycle Tests")
@MainActor
struct ModelLifecycleTests {

    @Test("Creating Work with Author should not crash")
    func createWorkWithAuthorSafely() async throws {
        // Setup in-memory container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        // Test the CORRECT pattern
        let work = Work(
            title: "Test Book",
            authors: [],  // Empty initially
            originalLanguage: "English",
            firstPublicationYear: 2025
        )
        context.insert(work)  // Get permanent ID

        let author = Author(name: "Test Author")
        context.insert(author)  // Get permanent ID

        work.authors = [author]  // Safe - both have permanent IDs

        try context.save()

        // Verify
        #expect(work.authors?.count == 1)
        #expect(work.authors?.first?.name == "Test Author")
    }

    @Test("Creating Edition with Work should not crash")
    func createEditionWithWorkSafely() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self,
            configurations: config
        )
        let context = container.mainContext

        let work = Work(
            title: "Test Book",
            authors: [],
            originalLanguage: "English",
            firstPublicationYear: 2025
        )
        context.insert(work)

        let edition = Edition(
            isbn: "1234567890",
            publisher: "Test Publisher",
            publicationDate: "2025",
            pageCount: 300,
            format: .paperback,
            work: nil  // Don't set in constructor
        )
        context.insert(edition)  // Get permanent ID

        edition.work = work  // Safe - both have permanent IDs
        work.editions = [edition]

        try context.save()

        // Verify
        #expect(work.editions?.count == 1)
        #expect(edition.work?.title == "Test Book")
    }

    @Test("ScanResults pattern: Work created without authors, linked after insert")
    func scannedBookLinkedAfterInsert() async throws {
        // Given: SwiftData container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        // When: Processing scanned book (correct order)
        let work = Work(
            title: "Scanned Book",
            authors: [],  // Empty initially
            originalLanguage: "English",
            firstPublicationYear: nil
        )
        work.reviewStatus = .verified

        context.insert(work)  // Insert Work first

        let author = Author(name: "Scanned Author")
        context.insert(author)  // Insert author
        work.authors = [author]  // Link last

        // Create edition
        let edition = Edition(
            isbn: "9781234567890",
            publisher: nil,
            publicationDate: nil,
            pageCount: nil,
            format: .paperback,
            work: nil
        )
        context.insert(edition)  // Insert first
        edition.work = work
        work.editions = [edition]  // Link second

        // Then: No crash, all relationships saved
        try context.save()

        #expect(work.authors?.count == 1)
        #expect(work.editions?.count == 1)
        #expect(work.reviewStatus == .verified)
    }

    @Test("GeminiCSV pattern: Work linked to Authors after both inserted")
    func csvImportWorkLinkedAfterInsert() async throws {
        // Given: SwiftData container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self,
            configurations: config
        )
        let context = container.mainContext

        // When: Creating book from CSV import (correct order)
        let author = Author(name: "CSV Author")
        context.insert(author)  // Insert first

        let work = Work(
            title: "CSV Book",
            authors: [],  // Empty initially
            originalLanguage: "Unknown",
            firstPublicationYear: 2025
        )
        context.insert(work)  // Insert second

        work.authors = [author]  // Link third

        // Then: No crash, relationship saved
        try context.save()

        #expect(work.authors?.count == 1)
        #expect(work.authors?.first?.name == "CSV Author")
    }

    @Test("WorkDiscovery pattern: Multiple authors linked after Work inserted")
    func workDiscoveryMultipleAuthorsLinked() async throws {
        // Given: SwiftData container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self,
            configurations: config
        )
        let context = container.mainContext

        // When: Creating work from search result (correct order)
        // CRITICAL: Create Work with authors: [] (never pass objects to constructor)
        let work = Work(
            title: "Multi-Author Book",
            authors: [],  // Empty in constructor per fix
            originalLanguage: "English",
            firstPublicationYear: 2025,
            subjectTags: ["Fiction"]
        )
        context.insert(work)  // Insert Work first - gets permanent ID

        // Create authors AFTER work is inserted
        let authors = [
            Author(name: "Author 1", gender: .female, culturalRegion: .asia),
            Author(name: "Author 2", gender: .male, culturalRegion: .europe)
        ]
        authors.forEach { context.insert($0) }  // Insert each author - gets permanent ID

        // NOW safe to link - both work and all authors have permanent IDs
        work.authors = authors  // Link last

        // Then: No crash, relationship saved correctly
        try context.save()

        #expect(work.authors?.count == 2)
        #expect(work.authors?.first?.name == "Author 1")
    }

    @Test("EnrichmentService pattern: Edition linked to existing Work after insert")
    func enrichmentEditionLinkedAfterInsert() async throws {
        // Given: SwiftData container with existing work
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self,
            configurations: config
        )
        let context = container.mainContext

        // Existing work (simulates enrichment scenario)
        let work = Work(
            title: "Existing Book",
            authors: [],
            originalLanguage: "English",
            firstPublicationYear: 2025
        )
        context.insert(work)
        try context.save()

        // When: Creating edition during enrichment (correct order)
        let edition = Edition(
            isbn: "9781234567890",
            publisher: "Enriched Publisher",
            publicationDate: "2025",
            pageCount: 300,
            format: .paperback,
            work: nil  // Don't set in constructor
        )
        context.insert(edition)  // Insert first

        // Set relationship after insert
        edition.work = work

        // Then: No crash, relationship saved
        try context.save()

        #expect(edition.work?.title == "Existing Book")
    }
}
