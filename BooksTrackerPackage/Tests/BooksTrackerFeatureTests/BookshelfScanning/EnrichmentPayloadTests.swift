import Testing
import Foundation
@testable import BooksTrackerFeature

@MainActor
struct EnrichmentPayloadTests {

    @Test("EnrichmentPayload decodes canonical DTOs from backend")
    func decodesCanonicalDTOs() throws {
        // Arrange: Mock backend enrichment response
        let json = """
        {
            "status": "success",
            "work": {
                "title": "The Great Gatsby",
                "subjectTags": ["Fiction", "Classic"],
                "firstPublicationYear": 1925,
                "goodreadsWorkIDs": [],
                "amazonASINs": [],
                "librarythingIDs": [],
                "googleBooksVolumeIDs": ["abc123"],
                "isbndbQuality": 85,
                "reviewStatus": "verified"
            },
            "editions": [{
                "isbn": "9780743273565",
                "isbns": ["9780743273565"],
                "publisher": "Scribner",
                "publicationDate": "2004",
                "format": "Paperback",
                "amazonASINs": [],
                "googleBooksVolumeIDs": [],
                "librarythingIDs": [],
                "isbndbQuality": 85
            }],
            "authors": [{
                "name": "F. Scott Fitzgerald",
                "gender": "Male"
            }],
            "provider": "google-books",
            "cachedResult": false
        }
        """.data(using: .utf8)!

        // Act
        let payload = try JSONDecoder().decode(ScanResultPayload.BookPayload.EnrichmentPayload.self, from: json)

        // Assert
        #expect(payload.status == "success")
        #expect(payload.work?.title == "The Great Gatsby")
        #expect(payload.editions?.count == 1)
        #expect(payload.editions?.first?.isbn == "9780743273565")
        #expect(payload.authors?.count == 1)
        #expect(payload.authors?.first?.name == "F. Scott Fitzgerald")
        #expect(payload.provider == "google-books")
        #expect(payload.cachedResult == false)
    }

    @Test("EnrichmentPayload handles not_found status gracefully")
    func handlesNotFoundStatus() throws {
        // Arrange
        let json = """
        {
            "status": "not_found",
            "work": null,
            "editions": null,
            "authors": null,
            "provider": "google-books",
            "cachedResult": false
        }
        """.data(using: .utf8)!

        // Act
        let payload = try JSONDecoder().decode(ScanResultPayload.BookPayload.EnrichmentPayload.self, from: json)

        // Assert
        #expect(payload.status == "not_found")
        #expect(payload.work == nil)
        #expect(payload.editions == nil)
        #expect(payload.authors == nil)
    }
}
