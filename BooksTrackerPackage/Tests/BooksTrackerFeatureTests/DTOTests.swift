import Testing
import Foundation
@testable import BooksTrackerFeature

/// Tests for Codable DTOs matching TypeScript canonical contracts
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md
@Suite("DTO Codable Tests")
struct DTOTests {

    // MARK: - WorkDTO Tests

    @Test("WorkDTO decodes from canonical JSON")
    func workDTODecoding() throws {
        let json = """
        {
            "title": "1984",
            "subjectTags": ["Fiction", "Dystopian"],
            "originalLanguage": "English",
            "firstPublicationYear": 1949,
            "description": "A dystopian novel",
            "coverImageURL": "https://example.com/covers/1984.jpg",
            "synthetic": false,
            "primaryProvider": "google-books",
            "contributors": ["google-books"],
            "goodreadsWorkIDs": ["work123"],
            "amazonASINs": ["B001ABC123"],
            "librarythingIDs": ["thing456"],
            "googleBooksVolumeIDs": ["vol789"],
            "isbndbQuality": 95,
            "reviewStatus": "verified"
        }
        """

        let data = json.data(using: .utf8)!
        let work = try JSONDecoder().decode(WorkDTO.self, from: data)

        #expect(work.title == "1984")
        #expect(work.subjectTags == ["Fiction", "Dystopian"])
        #expect(work.originalLanguage == "English")
        #expect(work.firstPublicationYear == 1949)
        #expect(work.description == "A dystopian novel")
        #expect(work.coverImageURL == "https://example.com/covers/1984.jpg")
        #expect(work.synthetic == false)
        #expect(work.primaryProvider == "google-books")
        #expect(work.contributors == ["google-books"])
        #expect(work.isbndbQuality == 95)
        #expect(work.reviewStatus == .verified)
    }

    @Test("WorkDTO decodes with minimal required fields")
    func workDTOMinimalDecoding() throws {
        let json = """
        {
            "title": "Unknown Book",
            "subjectTags": [],
            "goodreadsWorkIDs": [],
            "amazonASINs": [],
            "librarythingIDs": [],
            "googleBooksVolumeIDs": [],
            "isbndbQuality": 0,
            "reviewStatus": "needsReview"
        }
        """

        let data = json.data(using: .utf8)!
        let work = try JSONDecoder().decode(WorkDTO.self, from: data)

        #expect(work.title == "Unknown Book")
        #expect(work.subjectTags.isEmpty)
        #expect(work.synthetic == nil)
        #expect(work.primaryProvider == nil)
    }

    @Test("WorkDTO decodes when backend omits required fields (contract violation)")
    func workDTODecodesWithMissingRequiredFields() throws {
        // Reproduces real-world API responses where backend violates TypeScript contract
        // by omitting fields declared as required: subjectTags, isbndbQuality, reviewStatus
        // Issue: Barcode scanning fails with "keyNotFound" decoding error
        let json = """
        {
            "title": "The Scarlet Letter",
            "goodreadsWorkIDs": [],
            "amazonASINs": [],
            "librarythingIDs": [],
            "googleBooksVolumeIDs": ["vol123"]
        }
        """

        let data = json.data(using: .utf8)!
        let work = try JSONDecoder().decode(WorkDTO.self, from: data)

        // Should decode successfully with defaults
        #expect(work.title == "The Scarlet Letter")
        #expect(work.subjectTags == [])              // Default: empty array
        #expect(work.isbndbQuality == 0)             // Default: 0
        #expect(work.reviewStatus == .verified)      // Default: verified (for API sources)
    }

    @Test("WorkDTO decodes with coverImageURL from backend normalizers")
    func workDTODecodesWithCoverImageURL() throws {
        // Backend normalizers (google-books.ts, openlibrary.ts, isbndb.ts) set coverImageURL
        // This field is copied from EditionDTO for enrichment purposes
        let json = """
        {
            "title": "The Great Gatsby",
            "subjectTags": ["Fiction", "Classic Literature"],
            "coverImageURL": "https://books.google.com/books/content?id=abc123&printsec=frontcover&img=1",
            "synthetic": false,
            "primaryProvider": "google-books",
            "goodreadsWorkIDs": [],
            "amazonASINs": [],
            "librarythingIDs": [],
            "googleBooksVolumeIDs": ["abc123"],
            "isbndbQuality": 0,
            "reviewStatus": "verified"
        }
        """

        let data = json.data(using: .utf8)!
        let work = try JSONDecoder().decode(WorkDTO.self, from: data)

        #expect(work.coverImageURL == "https://books.google.com/books/content?id=abc123&printsec=frontcover&img=1")
        #expect(work.title == "The Great Gatsby")
    }

    // MARK: - EditionDTO Tests

    @Test("EditionDTO decodes from canonical JSON with editionDescription")
    func editionDTODecoding() throws {
        let json = """
        {
            "isbn": "9780451524935",
            "isbns": ["9780451524935", "0451524934"],
            "title": "1984",
            "publisher": "Signet Classic",
            "publicationDate": "1950-06-01",
            "pageCount": 328,
            "format": "Paperback",
            "coverImageURL": "https://example.com/cover.jpg",
            "editionTitle": "First Edition",
            "editionDescription": "Classic dystopian novel",
            "language": "en",
            "primaryProvider": "google-books",
            "contributors": ["google-books"],
            "amazonASINs": ["B001ABC123"],
            "googleBooksVolumeIDs": ["vol789"],
            "librarythingIDs": ["thing456"],
            "isbndbQuality": 90
        }
        """

        let data = json.data(using: .utf8)!
        let edition = try JSONDecoder().decode(EditionDTO.self, from: data)

        #expect(edition.isbn == "9780451524935")
        #expect(edition.isbns == ["9780451524935", "0451524934"])
        #expect(edition.title == "1984")
        #expect(edition.publisher == "Signet Classic")
        #expect(edition.pageCount == 328)
        #expect(edition.format == .paperback)
        #expect(edition.editionDescription == "Classic dystopian novel")
        #expect(edition.language == "en")
        #expect(edition.primaryProvider == "google-books")
    }

    @Test("EditionDTO decodes with minimal required fields")
    func editionDTOMinimalDecoding() throws {
        let json = """
        {
            "isbns": [],
            "format": "E-book",
            "amazonASINs": [],
            "googleBooksVolumeIDs": [],
            "librarythingIDs": [],
            "isbndbQuality": 0
        }
        """

        let data = json.data(using: .utf8)!
        let edition = try JSONDecoder().decode(EditionDTO.self, from: data)

        #expect(edition.isbns.isEmpty)
        #expect(edition.format == .ebook)
        #expect(edition.isbn == nil)
        #expect(edition.editionDescription == nil)
    }

    // MARK: - AuthorDTO Tests

    @Test("AuthorDTO decodes from canonical JSON")
    func authorDTODecoding() throws {
        let json = """
        {
            "name": "George Orwell",
            "gender": "Male",
            "culturalRegion": "Europe",
            "nationality": "British",
            "birthYear": 1903,
            "deathYear": 1950,
            "openLibraryID": "OL123A",
            "bookCount": 15
        }
        """

        let data = json.data(using: .utf8)!
        let author = try JSONDecoder().decode(AuthorDTO.self, from: data)

        #expect(author.name == "George Orwell")
        #expect(author.gender == .male)
        #expect(author.culturalRegion == .europe)
        #expect(author.nationality == "British")
        #expect(author.birthYear == 1903)
        #expect(author.deathYear == 1950)
        #expect(author.bookCount == 15)
    }

    @Test("AuthorDTO decodes with minimal required fields")
    func authorDTOMinimalDecoding() throws {
        let json = """
        {
            "name": "Unknown Author",
            "gender": "Unknown"
        }
        """

        let data = json.data(using: .utf8)!
        let author = try JSONDecoder().decode(AuthorDTO.self, from: data)

        #expect(author.name == "Unknown Author")
        #expect(author.gender == .unknown)
        #expect(author.culturalRegion == nil)
    }

    // MARK: - Response Envelope Tests

    @Test("ResponseEnvelope decodes success envelope with BookSearchResponse")
    func responseEnvelopeSuccessDecoding() throws {
        let json = """
        {
            "data": {
                "works": [{
                    "title": "1984",
                    "subjectTags": ["Fiction"],
                    "goodreadsWorkIDs": [],
                    "amazonASINs": [],
                    "librarythingIDs": [],
                    "googleBooksVolumeIDs": ["vol123"],
                    "isbndbQuality": 0,
                    "reviewStatus": "verified"
                }],
                "authors": [{
                    "name": "George Orwell",
                    "gender": "Male"
                }]
            },
            "metadata": {
                "timestamp": "2025-11-18T12:00:00Z",
                "processingTime": 123,
                "provider": "google-books",
                "cached": false
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        guard let searchResponse = response.data else {
            Issue.record("Expected data in response")
            return
        }

        let metadata = response.metadata

        #expect(searchResponse.works.count == 1)
        #expect(searchResponse.works[0].title == "1984")
        #expect(searchResponse.authors.count == 1)
        #expect(searchResponse.authors[0].name == "George Orwell")
        #expect(metadata.processingTime == 123)
        #expect(metadata.provider == "google-books")
    }

    @Test("ResponseEnvelope decodes error envelope")
    func responseEnvelopeErrorDecoding() throws {
        let json = """
        {
            "data": null,
            "error": {
                "message": "Invalid ISBN format",
                "code": "INVALID_ISBN"
            },
            "metadata": {
                "timestamp": "2025-11-18T12:00:00Z",
                "processingTime": 5
            }
        }
        """

        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

        guard let error = response.error else {
            Issue.record("Expected error in response")
            return
        }

        let metadata = response.metadata

        #expect(error.message == "Invalid ISBN format")
        #expect(error.code == "INVALID_ISBN")
        #expect(metadata.processingTime == 5)
    }
}
