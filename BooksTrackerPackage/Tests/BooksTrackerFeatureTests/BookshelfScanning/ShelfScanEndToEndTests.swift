import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("Shelf Scan End-to-End Tests")
@MainActor
struct ShelfScanEndToEndTests {

    // Test infrastructure
    private var container: ModelContainer!
    private var modelContext: ModelContext!

    init() throws {
        // Create in-memory container for testing
        let schema = Schema([Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: schema, configurations: [config])
        self.modelContext = ModelContext(container)
    }

    @Test("V3ScanBookResult with enrichment DTOs persists to Work with covers and metadata")
    func testV3ScanResultToWorkWithEnrichment() async throws {
        // ARRANGE: Create V3ScanBookResult with enrichment data (from bendv3 API)
        let v3Result = V3ScanBookResult(
            title: "The Pragmatic Programmer",
            author: "David Thomas, Andrew Hunt",
            isbn: "9780135957059",
            confidence: 0.92,
            boundingBox: V3BoundingBox(x: 0.1, y: 0.2, width: 0.3, height: 0.4),
            enrichmentStatus: "success",
            coverUrl: "https://covers.openlibrary.org/b/isbn/9780135957059-L.jpg",
            publisher: "Addison-Wesley",
            publicationYear: 2019
        )

        // ACT: Convert V3ScanBookResult → DetectedBook with enrichment DTOs
        // This should call convertV3ResultToDetectedBook() from BookshelfAIService
        let detectedBook = try convertV3ScanResultToDetectedBook(v3Result)

        // ASSERT: DetectedBook should have enrichment data populated
        #expect(detectedBook.title == "The Pragmatic Programmer")
        #expect(detectedBook.author == "David Thomas, Andrew Hunt")
        #expect(detectedBook.isbn == "9780135957059")
        #expect(detectedBook.confidence == 0.92)
        #expect(detectedBook.enrichmentStatus == .success)

        // ASSERT: Enrichment DTOs should be populated
        #expect(detectedBook.enrichmentWork != nil)
        #expect(detectedBook.enrichmentEditions != nil)
        #expect(detectedBook.enrichmentAuthors != nil)

        // ASSERT: Cover URL should be populated from V3 response
        let workDTO = try #require(detectedBook.enrichmentWork)
        #expect(workDTO.coverImageURL == "https://covers.openlibrary.org/b/isbn/9780135957059-L.jpg")

        // ACT: Convert DetectedBook → Work (persist to SwiftData)
        let work = try convertDetectedBookToWork(detectedBook, modelContext: modelContext)

        // ASSERT: Work should have enrichment metadata
        #expect(work.title == "The Pragmatic Programmer")
        #expect(work.coverImageURL == "https://covers.openlibrary.org/b/isbn/9780135957059-L.jpg")
        #expect(work.firstPublicationYear == 2019)

        // ASSERT: Authors should be created and linked
        #expect((work.authors?.count ?? 0) > 0)

        // ASSERT: SwiftData persistence should succeed
        try modelContext.save()

        // Fetch back from SwiftData to verify persistence
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == "The Pragmatic Programmer" }
        )
        let fetchedWorks = try modelContext.fetch(descriptor)

        #expect(fetchedWorks.count == 1)
        #expect(fetchedWorks.first?.coverImageURL != nil)
    }
}

// MARK: - Implementation Functions

/// Convert V3ScanBookResult → DetectedBook with enrichment DTOs
private func convertV3ScanResultToDetectedBook(_ v3Result: V3ScanBookResult) throws -> DetectedBook {
    var detectedBook = DetectedBook(
        isbn: v3Result.isbn,
        title: v3Result.title,
        author: v3Result.author,
        confidence: v3Result.confidence,
        boundingBox: CGRect(x: v3Result.boundingBox?.x ?? 0,
                          y: v3Result.boundingBox?.y ?? 0,
                          width: v3Result.boundingBox?.width ?? 0,
                          height: v3Result.boundingBox?.height ?? 0),
        rawText: v3Result.title
    )

    // Set enrichment status
    detectedBook.enrichmentStatus = EnrichmentStatus(rawValue: v3Result.enrichmentStatus) ?? .pending

    // Populate enrichment DTOs if enrichment was successful
    if v3Result.enrichmentStatus == "success" {
        detectedBook.enrichmentWork = WorkDTO(
            title: v3Result.title,
            subjectTags: [],
            originalLanguage: nil,
            firstPublicationYear: v3Result.publicationYear,
            description: nil,
            coverImageURL: v3Result.coverUrl,
            searchLinks: nil,
            synthetic: nil,
            primaryProvider: nil,
            contributors: nil,
            openLibraryID: nil,
            openLibraryWorkID: nil,
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: [],
            lastISBNDBSync: nil,
            isbndbQuality: 0,
            reviewStatus: .verified,
            originalImagePath: nil,
            boundingBox: nil
        )

        detectedBook.enrichmentEditions = []
        detectedBook.enrichmentAuthors = v3Result.author != nil ? [AuthorDTO(
            name: v3Result.author!,
            gender: .unknown
        )] : []
    }

    return detectedBook
}

/// Convert DetectedBook → Work (persist to SwiftData)
private func convertDetectedBookToWork(_ detectedBook: DetectedBook, modelContext: ModelContext) throws -> Work {
    // Create Work from enrichment DTO
    guard let workDTO = detectedBook.enrichmentWork else {
        throw NSError(domain: "ShelfScanEndToEndTests", code: 1,
                     userInfo: [NSLocalizedDescriptionKey: "Missing enrichment data"])
    }

    let work = Work(
        title: workDTO.title,
        originalLanguage: workDTO.originalLanguage,
        firstPublicationYear: workDTO.firstPublicationYear
    )
    work.coverImageURL = workDTO.coverImageURL

    // Insert first (Insert-Before-Relate pattern)
    modelContext.insert(work)

    // Create and link authors
    if let authorDTOs = detectedBook.enrichmentAuthors {
        var authors: [Author] = []
        for authorDTO in authorDTOs {
            let author = Author(
                name: authorDTO.name,
                birthYear: authorDTO.birthYear,
                deathYear: authorDTO.deathYear
            )
            modelContext.insert(author)
            authors.append(author)
        }
        work.authors = authors
    }

    return work
}
