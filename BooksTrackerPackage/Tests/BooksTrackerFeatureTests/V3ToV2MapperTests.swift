import Foundation
import Testing
@testable import BooksTrackerFeature
import CryptoKit

@Suite("V3ToV2Mapper Tests")
struct V3ToV2MapperTests {

    // MARK: - Test Data Helpers

    /// Helper to create a V3Book instance for testing.
    private func makeV3Book(
        isbn: String = "9780134685991",
        isbn10: String? = nil,
        title: String = "Effective Java",
        subtitle: String? = nil,
        authors: [String] = ["Joshua Bloch"],
        publisher: String? = "Addison-Wesley",
        publishedDate: String? = "2018-01-06",
        description: String? = "A classic book on Java programming best practices.",
        pageCount: Int? = 416,
        categories: [String]? = ["Programming", "Java"],
        language: String? = "en",
        coverUrl: String? = "https://covers.openlibrary.org/b/isbn/9780134685991-L.jpg",
        thumbnailUrl: String? = nil,
        workKey: String? = nil,
        editionKey: String? = nil,
        provider: String = "google",
        quality: Double = 0.95
    ) -> V3Book {
        V3Book(
            isbn: isbn,
            isbn10: isbn10,
            title: title,
            subtitle: subtitle,
            authors: authors,
            publisher: publisher,
            publishedDate: publishedDate,
            description: description,
            pageCount: pageCount,
            categories: categories,
            language: language,
            coverUrl: coverUrl,
            thumbnailUrl: thumbnailUrl,
            workKey: workKey,
            editionKey: editionKey,
            provider: provider,
            quality: quality
        )
    }

    /// Helper to create a V3SearchResponse instance.
    private func makeV3SearchResponse(books: [V3Book], total: Int) -> V3SearchResponse {
        V3SearchResponse(
            success: true,
            data: V3SearchData(
                books: books,
                total: total,
                query: V3SearchQuery(q: "test", mode: "text"),
                pagination: V3Pagination(
                    type: "offset",
                    page: 1,
                    limit: 20,
                    totalPages: 1,
                    hasNext: false,
                    hasPrev: false
                )
            ),
            metadata: V3ResponseMetadata(
                timestamp: "2025-12-05T00:00:00Z",
                provider: "google",
                cached: false
            ),
            links: nil
        )
    }

    /// Helper to create a V3EnrichedBook instance.
    private func makeV3EnrichedBook(
        isbn: String = "9780134685991",
        isbn10: String? = nil,
        title: String = "Effective Java",
        subtitle: String? = nil,
        authors: [String] = ["Joshua Bloch"],
        publisher: String? = "Addison-Wesley",
        publishedDate: String? = "2018-01-06",
        description: String? = "A classic book on Java programming best practices.",
        pageCount: Int? = 416,
        categories: [String]? = ["Programming", "Java"],
        language: String? = "en",
        coverUrl: String? = "https://covers.openlibrary.org/b/isbn/9780134685991-L.jpg",
        thumbnailUrl: String? = nil,
        workKey: String? = nil,
        editionKey: String? = nil,
        provider: String = "google",
        quality: Double = 0.95,
        vectorized: Bool = true
    ) -> V3EnrichedBook {
        V3EnrichedBook(
            isbn: isbn,
            isbn10: isbn10,
            title: title,
            subtitle: subtitle,
            authors: authors,
            publisher: publisher,
            publishedDate: publishedDate,
            description: description,
            pageCount: pageCount,
            categories: categories,
            language: language,
            coverUrl: coverUrl,
            thumbnailUrl: thumbnailUrl,
            workKey: workKey,
            editionKey: editionKey,
            provider: provider,
            quality: quality,
            vectorized: vectorized
        )
    }

    /// Helper to create a V3EnrichResponse instance.
    private func makeV3EnrichResponse(enrichedBooks: [V3EnrichedBook], found: Int) -> V3EnrichResponse {
        V3EnrichResponse(
            success: true,
            data: V3EnrichData(
                books: enrichedBooks,
                requested: found,
                found: found,
                notFound: nil
            ),
            metadata: V3ResponseMetadata(
                timestamp: "2025-12-05T00:00:00Z",
                provider: "google",
                cached: false
            )
        )
    }

    /// Helper to generate SHA256 hash for direct comparison in tests
    private func stableHash(_ input: String) -> UInt64 {
        let hash = SHA256.hash(data: Data(input.utf8))
        let truncatedHash = hash.withUnsafeBytes { bytes in
            bytes.load(as: UInt64.self)
        }
        return truncatedHash
    }

    // MARK: - Synthetic ID Stability Tests

    @Test("Synthetic Work ID is deterministic and stable (SHA256)")
    func syntheticWorkIDStability() async throws {
        let isbn = "9780134685991"
        let expectedHash = stableHash(isbn)
        let expectedID = "OL\(expectedHash)W"

        // Test multiple calls with the same input
        let id1 = V3ToV2Mapper.generateWorkID(from: isbn)
        let id2 = V3ToV2Mapper.generateWorkID(from: isbn)
        let id3 = V3ToV2Mapper.generateWorkID(from: "9780134685991")

        #expect(id1 == expectedID, "Generated ID should match expected SHA256 hash format")
        #expect(id1 == id2, "Work ID must be stable across multiple calls")
        #expect(id1 == id3, "Work ID must be stable for equivalent string inputs")

        let differentIsbn = "9781234567890"
        let differentID = V3ToV2Mapper.generateWorkID(from: differentIsbn)
        #expect(id1 != differentID, "Different ISBNs should produce different Work IDs")
    }

    @Test("Synthetic Edition ID is deterministic and stable (SHA256)")
    func syntheticEditionIDStability() async throws {
        let isbn = "9780134685991"
        let expectedHash = stableHash(isbn)
        let expectedID = "OL\(expectedHash)M"

        let id1 = V3ToV2Mapper.generateEditionID(from: isbn)
        let id2 = V3ToV2Mapper.generateEditionID(from: isbn)

        #expect(id1 == expectedID, "Generated ID should match expected SHA256 hash format")
        #expect(id1 == id2, "Edition ID must be stable across multiple calls")

        let differentIsbn = "9781234567890"
        let differentID = V3ToV2Mapper.generateEditionID(from: differentIsbn)
        #expect(id1 != differentID, "Different ISBNs should produce different Edition IDs")
    }

    @Test("Synthetic Author ID is deterministic and stable (SHA256)")
    func syntheticAuthorIDStability() async throws {
        let authorName = "Joshua Bloch"
        let expectedHash = stableHash(authorName)
        let expectedID = "OL\(expectedHash)A"

        let id1 = V3ToV2Mapper.generateAuthorID(from: authorName)
        let id2 = V3ToV2Mapper.generateAuthorID(from: authorName)

        #expect(id1 == expectedID, "Generated ID should match expected SHA256 hash format")
        #expect(id1 == id2, "Author ID must be stable across multiple calls")

        let differentAuthorName = "Erich Gamma"
        let differentID = V3ToV2Mapper.generateAuthorID(from: differentAuthorName)
        #expect(id1 != differentID, "Different author names should produce different Author IDs")
    }

    @Test("Synthetic IDs for identical V3Books are the same")
    func syntheticIDsDeterministicAcrossDifferentObjects() async throws {
        let isbn = "9780134685991"
        let authorName = "Joshua Bloch"

        let v3Book1 = makeV3Book(isbn: isbn, authors: [authorName], workKey: nil, editionKey: nil)
        let v3Book2 = makeV3Book(isbn: isbn, authors: [authorName], workKey: nil, editionKey: nil)

        let (work1, edition1, authors1) = V3ToV2Mapper.mapBook(v3Book1)
        let (work2, edition2, authors2) = V3ToV2Mapper.mapBook(v3Book2)

        #expect(work1.openLibraryID == work2.openLibraryID, "Identical V3Books should produce identical Work IDs")
        #expect(edition1.openLibraryID == edition2.openLibraryID, "Identical V3Books should produce identical Edition IDs")
        #expect(authors1.first?.openLibraryID == authors2.first?.openLibraryID, "Identical V3Books with same author should produce identical Author IDs")
        #expect(authors1.count == 1 && authors2.count == 1, "Should have one author each")
    }

    // MARK: - Search Response Mapping

    @Test("Search response mapping basic functionality and counts")
    func searchResponseMappingBasic() async throws {
        let book1 = makeV3Book(isbn: "9780134685991", title: "Book A", authors: ["Author One"])
        let book2 = makeV3Book(isbn: "9780134685992", title: "Book B", authors: ["Author Two", "Author Three"])
        let book3 = makeV3Book(isbn: "9780134685993", title: "Book C", authors: ["Author One"])

        let v3Response = makeV3SearchResponse(books: [book1, book2, book3], total: 100)
        let mappedResponse = V3ToV2Mapper.mapSearchResponse(v3Response)

        #expect(mappedResponse.resultCount == 3, "Result count should match number of books mapped")
        #expect(mappedResponse.totalResults == 100, "Total results should match V3 response")
        #expect(mappedResponse.works.count == 3, "Should have 3 works")
        #expect(mappedResponse.editions.count == 3, "Should have 3 editions")
        #expect(mappedResponse.authors.count == 3, "Should have 3 unique authors after deduplication")
        #expect(mappedResponse.expiresAt == nil, "expiresAt should be nil")
    }

    @Test("Search response mapping preserves relationships and deduplicates authors")
    func searchResponseRelationshipsAndDeduplication() async throws {
        let authorJKR = "J.K. Rowling"
        let authorStephenKing = "Stephen King"

        let book1 = makeV3Book(isbn: "9780747532743", title: "Harry Potter 1", authors: [authorJKR], workKey: "OLW1", editionKey: "OLE1")
        let book2 = makeV3Book(isbn: "9780747532750", title: "Harry Potter 2", authors: [authorJKR], workKey: "OLW2", editionKey: "OLE2")
        let book3 = makeV3Book(isbn: "9780743273565", title: "It", authors: [authorStephenKing], workKey: "OLW3", editionKey: "OLE3")

        let v3Response = makeV3SearchResponse(books: [book1, book2, book3], total: 3)
        let mappedResponse = V3ToV2Mapper.mapSearchResponse(v3Response)

        #expect(mappedResponse.works.count == 3, "Should have 3 works")
        #expect(mappedResponse.editions.count == 3, "Should have 3 editions")
        #expect(mappedResponse.authors.count == 2, "Should have 2 unique authors: J.K. Rowling, Stephen King")

        // Verify relationships
        let works = mappedResponse.works
        let editions = mappedResponse.editions
        let authors = mappedResponse.authors

        // Ensure all edition.workID link to actual works
        for edition in editions {
            let workExists = works.contains(where: { $0.openLibraryID == edition.workID })
            #expect(workExists, "Edition \(edition.openLibraryID!) links to a non-existent work ID \(edition.workID)")
        }

        // Check specific author IDs (Work↔Author relationships managed at SwiftData model level, not DTO)
        let jkRowlingAuthor = authors.first(where: { $0.name == authorJKR })
        let stephenKingAuthor = authors.first(where: { $0.name == authorStephenKing })
        #expect(jkRowlingAuthor != nil, "J.K. Rowling author should exist")
        #expect(stephenKingAuthor != nil, "Stephen King author should exist")

        // Verify work IDs
        let workHP1 = works.first(where: { $0.openLibraryWorkID == "OLW1" })
        #expect(workHP1 != nil, "Harry Potter 1 work should exist")
    }

    @Test("Search response mapping with empty author array in V3Book")
    func searchResponseMappingEmptyAuthors() async throws {
        let book = makeV3Book(isbn: "9781234567891", authors: [], workKey: "OLW-Empty", editionKey: "OLE-Empty")
        let v3Response = makeV3SearchResponse(books: [book], total: 1)
        let mappedResponse = V3ToV2Mapper.mapSearchResponse(v3Response)

        #expect(mappedResponse.works.count == 1)
        #expect(mappedResponse.editions.count == 1)
        #expect(mappedResponse.authors.isEmpty, "No authors should be generated for empty author array")

        // Work↔Author relationships managed at SwiftData model level, not DTO
        let work = mappedResponse.works.first
        #expect(work != nil, "Work should exist even with empty authors")
    }

    @Test("Search response with no books returns empty arrays")
    func searchResponseEmptyBookList() async throws {
        let v3Response = makeV3SearchResponse(books: [], total: 0)
        let mappedResponse = V3ToV2Mapper.mapSearchResponse(v3Response)

        #expect(mappedResponse.resultCount == 0)
        #expect(mappedResponse.totalResults == 0)
        #expect(mappedResponse.works.isEmpty)
        #expect(mappedResponse.editions.isEmpty)
        #expect(mappedResponse.authors.isEmpty)
    }

    // MARK: - Enrich Response Mapping

    @Test("Enrich response mapping ignores vectorized field and maps correctly")
    func enrichResponseMapping() async throws {
        let enrichedBook1 = makeV3EnrichedBook(isbn: "9781234567891", title: "Enriched Book 1", authors: ["Author A"], vectorized: true)
        let enrichedBook2 = makeV3EnrichedBook(isbn: "9781234567892", title: "Enriched Book 2", authors: ["Author B"], vectorized: false)

        let v3Response = makeV3EnrichResponse(enrichedBooks: [enrichedBook1, enrichedBook2], found: 2)
        let mappedResponse = V3ToV2Mapper.mapEnrichResponse(v3Response)

        #expect(mappedResponse.resultCount == 2, "Result count should match number of enriched books mapped")
        #expect(mappedResponse.totalResults == 2, "Total results should match V3 enrich response 'found' count")
        #expect(mappedResponse.works.count == 2, "Should have 2 works")
        #expect(mappedResponse.editions.count == 2, "Should have 2 editions")
        #expect(mappedResponse.authors.count == 2, "Should have 2 authors")

        let work1 = mappedResponse.works.first(where: { $0.title == "Enriched Book 1" })
        #expect(work1?.title == "Enriched Book 1", "Work title should be mapped correctly")
    }

    // MARK: - Edge Cases

    @Test("Mapping a book with missing workKey and editionKey uses synthetic IDs")
    func missingOpenLibraryKeysUsesSyntheticIDs() async throws {
        let isbn = "9781111111111"
        let v3Book = makeV3Book(isbn: isbn, workKey: nil, editionKey: nil)
        let (work, edition, _) = V3ToV2Mapper.mapBook(v3Book)

        let expectedWorkIDHash = stableHash(isbn)
        let expectedEditionIDHash = stableHash(isbn)

        #expect(work.synthetic == true, "Work should be marked as synthetic")
        #expect(work.openLibraryID == "OL\(expectedWorkIDHash)W", "Work ID should be synthetic based on ISBN")
        #expect(edition.openLibraryID == "OL\(expectedEditionIDHash)M", "Edition ID should be synthetic based on ISBN")
        #expect(work.openLibraryWorkID == nil, "openLibraryWorkID should be nil when workKey is missing")
        #expect(edition.openLibraryEditionID == nil, "openLibraryEditionID should be nil when editionKey is missing")
    }

    @Test("Mapping a book with provided workKey and editionKey uses those IDs")
    func providedOpenLibraryKeysAreUsed() async throws {
        let isbn = "9782222222222"
        let providedWorkKey = "OLW123456"
        let providedEditionKey = "OLE987654"
        let v3Book = makeV3Book(isbn: isbn, workKey: providedWorkKey, editionKey: providedEditionKey)
        let (work, edition, _) = V3ToV2Mapper.mapBook(v3Book)

        #expect(work.synthetic == false, "Work should not be marked as synthetic")
        #expect(work.openLibraryID == providedWorkKey, "Work ID should be the provided workKey")
        #expect(work.openLibraryWorkID == providedWorkKey, "openLibraryWorkID should be the provided workKey")
        #expect(edition.openLibraryID == providedEditionKey, "Edition ID should be the provided editionKey")
        #expect(edition.openLibraryEditionID == providedEditionKey, "openLibraryEditionID should be the provided editionKey")
    }

    @Test("Mapping with missing optional fields results in nil DTO properties or defaults")
    func mappingMissingOptionalFields() async throws {
        let v3Book = makeV3Book(
            isbn: "9783333333333",
            title: "Minimal Book",
            subtitle: nil,
            authors: ["Minimal Author"],
            publisher: nil,
            publishedDate: nil,
            description: nil,
            pageCount: nil,
            categories: nil,
            language: nil,
            coverUrl: nil,
            thumbnailUrl: nil
        )
        let (work, edition, authors) = V3ToV2Mapper.mapBook(v3Book)

        #expect(work.title == "Minimal Book")
        #expect(work.subjectTags.isEmpty, "Categories should default to empty array")
        #expect(work.originalLanguage == nil)
        #expect(work.firstPublicationYear == nil, "Published date is nil, so year should be nil")
        #expect(work.description == nil)
        #expect(work.coverImageURL == nil, "Cover URL should be nil when both are missing")
        #expect(work.primaryProvider == "google")
        #expect(work.isbndbQuality == 0)
        #expect(work.reviewStatus == .verified)

        #expect(edition.isbn == "9783333333333")
        #expect(edition.isbns.count == 1)
        #expect(edition.title == "Minimal Book")
        #expect(edition.publisher == nil)
        #expect(edition.publicationDate == nil)
        #expect(edition.pageCount == nil)
        #expect(edition.format == .paperback, "Format should default to paperback")
        #expect(edition.coverImageURL == nil)
        #expect(edition.editionTitle == nil)
        #expect(edition.editionDescription == nil)
        #expect(edition.language == nil)
        #expect(edition.primaryProvider == "google")
        #expect(edition.isbndbQuality == 0)
        #expect(authors.count == 1)
        #expect(authors.first?.name == "Minimal Author")
    }

    @Test("Books with identical ISBNs (but distinct V3Book objects) map to same Work/Edition IDs")
    func identicalIsbnsProduceSameIDs() async throws {
        let commonISBN = "9784444444444"
        let bookA = makeV3Book(isbn: commonISBN, title: "Title A", authors: ["Author X"])
        let bookB = makeV3Book(isbn: commonISBN, title: "Title B", authors: ["Author Y"])

        let v3Response = makeV3SearchResponse(books: [bookA, bookB], total: 2)
        let mappedResponse = V3ToV2Mapper.mapSearchResponse(v3Response)

        #expect(mappedResponse.works.count == 2)
        #expect(mappedResponse.editions.count == 2)

        let work1 = mappedResponse.works[0]
        let work2 = mappedResponse.works[1]
        let edition1 = mappedResponse.editions[0]
        let edition2 = mappedResponse.editions[1]

        #expect(work1.openLibraryID == work2.openLibraryID, "Works from same ISBN should have same synthetic ID")
        #expect(edition1.openLibraryID == edition2.openLibraryID, "Editions from same ISBN should have same synthetic ID")
        #expect(mappedResponse.authors.count == 2, "Authors X and Y should be distinct")
    }

    @Test("Mapping with ISBN-10 and ISBN-13 populates isbns array correctly")
    func isbnsArrayPopulation() async throws {
        let isbn13 = "9781234567897"
        let isbn10 = "123456789X"
        let v3Book = makeV3Book(isbn: isbn13, isbn10: isbn10)
        let (_, edition, _) = V3ToV2Mapper.mapBook(v3Book)

        #expect(edition.isbn == isbn13, "Primary ISBN should be ISBN-13")
        #expect(edition.isbns.count == 2, "isbns array should contain both ISBN-13 and ISBN-10")
        #expect(edition.isbns.contains(isbn13))
        #expect(edition.isbns.contains(isbn10))
    }

    @Test("Mapping with only ISBN-13 uses it for primary ISBN and array")
    func onlyIsbn13PopulatesIsbns() async throws {
        let isbn13 = "9781234567897"
        let v3Book = makeV3Book(isbn: isbn13, isbn10: nil)
        let (_, edition, _) = V3ToV2Mapper.mapBook(v3Book)

        #expect(edition.isbn == isbn13, "Primary ISBN should be ISBN-13")
        #expect(edition.isbns.count == 1, "isbns array should contain only ISBN-13")
        #expect(edition.isbns.contains(isbn13))
    }

    @Test("Cover URL preference: coverUrl over thumbnailUrl")
    func coverUrlPreference() async throws {
        let coverUrl = "https://example.com/cover.jpg"
        let thumbnailUrl = "https://example.com/thumb.jpg"

        // Case 1: Only coverUrl
        let book1 = makeV3Book(isbn: "9781", coverUrl: coverUrl, thumbnailUrl: nil)
        let (work1, edition1, _) = V3ToV2Mapper.mapBook(book1)
        #expect(work1.coverImageURL == coverUrl)
        #expect(edition1.coverImageURL == coverUrl)

        // Case 2: Only thumbnailUrl
        let book2 = makeV3Book(isbn: "9782", coverUrl: nil, thumbnailUrl: thumbnailUrl)
        let (work2, edition2, _) = V3ToV2Mapper.mapBook(book2)
        #expect(work2.coverImageURL == thumbnailUrl)
        #expect(edition2.coverImageURL == thumbnailUrl)

        // Case 3: Both, coverUrl preferred
        let book3 = makeV3Book(isbn: "9783", coverUrl: coverUrl, thumbnailUrl: thumbnailUrl)
        let (work3, edition3, _) = V3ToV2Mapper.mapBook(book3)
        #expect(work3.coverImageURL == coverUrl)
        #expect(edition3.coverImageURL == coverUrl)

        // Case 4: Neither
        let book4 = makeV3Book(isbn: "9784", coverUrl: nil, thumbnailUrl: nil)
        let (work4, edition4, _) = V3ToV2Mapper.mapBook(book4)
        #expect(work4.coverImageURL == nil)
        #expect(edition4.coverImageURL == nil)
    }

    @Test("Published date extraction for firstPublicationYear")
    func extractPublicationYear() async throws {
        // Valid full date
        let book1 = makeV3Book(isbn: "9785", publishedDate: "2023-11-20")
        let (work1, _, _) = V3ToV2Mapper.mapBook(book1)
        #expect(work1.firstPublicationYear == 2023)

        // Valid year only
        let book2 = makeV3Book(isbn: "9786", publishedDate: "1999")
        let (work2, _, _) = V3ToV2Mapper.mapBook(book2)
        #expect(work2.firstPublicationYear == 1999)

        // Valid year-month
        let book3 = makeV3Book(isbn: "9787", publishedDate: "1985-06")
        let (work3, _, _) = V3ToV2Mapper.mapBook(book3)
        #expect(work3.firstPublicationYear == 1985)

        // Invalid format
        let book4 = makeV3Book(isbn: "9788", publishedDate: "November 2023")
        let (work4, _, _) = V3ToV2Mapper.mapBook(book4)
        #expect(work4.firstPublicationYear == nil)

        // Nil date
        let book5 = makeV3Book(isbn: "9789", publishedDate: nil)
        let (work5, _, _) = V3ToV2Mapper.mapBook(book5)
        #expect(work5.firstPublicationYear == nil)

        // Empty string date
        let book6 = makeV3Book(isbn: "97810", publishedDate: "")
        let (work6, _, _) = V3ToV2Mapper.mapBook(book6)
        #expect(work6.firstPublicationYear == nil)
    }

    @Test("V3Book provider maps to Work and Edition primaryProvider")
    func providerMapping() async throws {
        let providerName = "myCustomProvider"
        let book = makeV3Book(isbn: "97811", provider: providerName)
        let (work, edition, _) = V3ToV2Mapper.mapBook(book)

        #expect(work.primaryProvider == providerName)
        #expect(edition.primaryProvider == providerName)
    }

    @Test("V3Book categories map to WorkDTO subjectTags")
    func categoriesToSubjectTags() async throws {
        let categories = ["Fiction", "Fantasy", "Young Adult"]
        let book = makeV3Book(isbn: "97812", categories: categories)
        let (work, _, _) = V3ToV2Mapper.mapBook(book)

        #expect(work.subjectTags == categories, "Subject tags should match V3Book categories")
    }

    @Test("V3Book quality and reviewStatus mappings")
    func qualityAndReviewStatusMappings() async throws {
        let book = makeV3Book(isbn: "97813", quality: 0.88)
        let (work, edition, _) = V3ToV2Mapper.mapBook(book)

        #expect(work.isbndbQuality == 0)
        #expect(edition.isbndbQuality == 0)
        #expect(work.reviewStatus == .verified)
    }

    @Test("V3Book.language maps to WorkDTO.originalLanguage and EditionDTO.language")
    func languageMapping() async throws {
        let langCode = "fr"
        let v3Book = makeV3Book(isbn: "97815", language: langCode)
        let (work, edition, _) = V3ToV2Mapper.mapBook(v3Book)

        #expect(work.originalLanguage == langCode)
        #expect(edition.language == langCode)
    }

    @Test("V3Book.subtitle maps to EditionDTO.editionTitle")
    func subtitleToEditionTitle() async throws {
        let subtitle = "A Definitive Guide"
        let v3Book = makeV3Book(isbn: "97816", subtitle: subtitle)
        let (_, edition, _) = V3ToV2Mapper.mapBook(v3Book)

        #expect(edition.editionTitle == subtitle)
    }

    @Test("V3Book.description maps to WorkDTO.description and EditionDTO.editionDescription")
    func descriptionMapping() async throws {
        let bookDescription = "This is a detailed description of the book."
        let v3Book = makeV3Book(isbn: "97817", description: bookDescription)
        let (work, edition, _) = V3ToV2Mapper.mapBook(v3Book)

        #expect(work.description == bookDescription)
        #expect(edition.editionDescription == bookDescription)
    }
}
