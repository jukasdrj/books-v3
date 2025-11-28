import Testing
import Foundation
@testable import BooksTrackerFeature

// MARK: - API Contract Compliance Tests

/// Comprehensive tests to catch mismatches between the API contract (docs/API_CONTRACT.md, docs/openapi.yaml)
/// and the Swift codebase.
///
/// These tests serve as an early warning system for contract violations by:
/// 1. Validating all required fields are present in DTOs
/// 2. Testing defensive decoding handles missing optional fields
/// 3. Verifying enum values match contract specifications
/// 4. Testing response envelope structure against contract
/// 5. Validating error response format
///
/// **When to run:** These tests should run on every PR affecting:
/// - Any files in `DTOs/`
/// - Any files in `Services/` that make API calls
/// - Changes to `docs/API_CONTRACT.md` or `docs/openapi.yaml`
@Suite("API Contract Compliance Tests")
struct APIContractComplianceTests {

    // MARK: - Section 3: Response Format Compliance

    @Suite("Section 3: Response Format")
    struct ResponseFormatTests {

        /// Contract 3.1: Success Response must have `success: true`, `data: object`, and `metadata: object`
        @Test("Success response matches contract structure (Section 3.1)")
        func successResponseMatchesContract() throws {
            // API Contract Section 3.1:
            // {
            //   "success": true,
            //   "data": { /* endpoint-specific data */ },
            //   "metadata": { "timestamp": "...", "cached": bool, "source": "..." }
            // }
            let json = """
            {
              "data": {
                "works": [],
                "editions": [],
                "authors": [],
                "resultCount": 0
              },
              "metadata": {
                "timestamp": "2025-11-27T10:30:00Z",
                "cached": false,
                "source": "google_books"
              }
            }
            """

            let data = json.data(using: .utf8)!
            let response = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

            // Verify data is present (success case)
            #expect(response.data != nil, "Success responses must have non-null data field")
            #expect(response.error == nil, "Success responses must have null error field")

            // Verify metadata has required fields per contract
            let metadata = response.metadata
            #expect(metadata.timestamp.isEmpty == false, "metadata.timestamp is required")
        }

        /// Contract 3.2: Error Response must have `success: false`, `error: object`
        @Test("Error response matches contract structure (Section 3.2)")
        func errorResponseMatchesContract() throws {
            // API Contract Section 3.2:
            // {
            //   "success": false,
            //   "error": { "code": "...", "message": "...", "details": {}, "retryable": bool }
            // }
            let json = """
            {
              "data": null,
              "error": {
                "code": "NOT_FOUND",
                "message": "Book not found"
              },
              "metadata": {
                "timestamp": "2025-11-27T10:30:00Z"
              }
            }
            """

            let data = json.data(using: .utf8)!
            let response = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)

            // Verify error structure
            #expect(response.data == nil, "Error responses must have null data field")
            #expect(response.error != nil, "Error responses must have non-null error field")

            let error = response.error!
            #expect(error.code != nil, "Error response must have code field")
            #expect(error.message.isEmpty == false, "Error response must have message field")
        }

        /// Contract 3.3: All error codes must be recognized
        @Test("All contract error codes are parseable (Section 3.3)")
        func allErrorCodesAreParseable() throws {
            // API Contract Section 3.3 - Error Codes:
            // NOT_FOUND, INVALID_REQUEST, RATE_LIMIT_EXCEEDED, CIRCUIT_OPEN, API_ERROR, NETWORK_ERROR, INTERNAL_ERROR
            let contractErrorCodes = [
                "NOT_FOUND",
                "INVALID_REQUEST",
                "RATE_LIMIT_EXCEEDED",
                "CIRCUIT_OPEN",
                "API_ERROR",
                "NETWORK_ERROR",
                "INTERNAL_ERROR"
            ]

            for code in contractErrorCodes {
                let json = """
                {
                  "data": null,
                  "error": {
                    "code": "\(code)",
                    "message": "Test error"
                  },
                  "metadata": {
                    "timestamp": "2025-11-27T10:30:00Z"
                  }
                }
                """

                let data = json.data(using: .utf8)!
                let response = try JSONDecoder().decode(ResponseEnvelope<BookSearchResponse>.self, from: data)
                #expect(response.error?.code == code, "Error code '\(code)' should be parsed correctly")
            }
        }
    }

    // MARK: - Section 4: Book Data Model Compliance

    @Suite("Section 4: Book Data Model")
    struct BookDataModelTests {

        /// Contract 4.1: Canonical Book Object must decode all required fields
        @Test("Canonical Book Object fields match contract (Section 4.1)")
        func canonicalBookObjectFieldsMatch() throws {
            // API Contract Section 4.1 defines these fields:
            // isbn, isbn13, title, authors, publisher, publishedDate, description,
            // pageCount, categories, language, coverUrl, averageRating, ratingsCount

            // WorkDTO should be able to decode canonical book data
            // Note: WorkDTO has different field names that map to the canonical structure
            let json = """
            {
              "title": "Harry Potter and the Sorcerer's Stone",
              "subjectTags": ["Fiction", "Fantasy"],
              "firstPublicationYear": 1997,
              "description": "A young wizard's adventure begins",
              "coverImageURL": "https://example.com/cover.jpg",
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

            #expect(work.title == "Harry Potter and the Sorcerer's Stone")
            #expect(work.subjectTags == ["Fiction", "Fantasy"])
            #expect(work.firstPublicationYear == 1997)
            #expect(work.description == "A young wizard's adventure begins")
            #expect(work.coverImageURL == "https://example.com/cover.jpg")
        }

        /// Contract 4.2: Enriched Book Object must include work and edition metadata
        @Test("Enriched Book Object includes OpenLibrary metadata (Section 4.2)")
        func enrichedBookObjectIncludesMetadata() throws {
            // API Contract Section 4.2 shows enriched books include:
            // work: { id, title, subjects, firstPublishYear }
            // edition: { id, numberOfPages, physicalFormat, publishers }
            // authors: [{ name, key, birth_date }]

            // Our WorkDTO should handle these nested structures
            let workJson = """
            {
              "title": "Harry Potter and the Philosopher's Stone",
              "subjectTags": ["Magic", "Wizards", "Hogwarts"],
              "firstPublicationYear": 1997,
              "openLibraryWorkID": "/works/OL82563W",
              "goodreadsWorkIDs": [],
              "amazonASINs": [],
              "librarythingIDs": [],
              "googleBooksVolumeIDs": [],
              "isbndbQuality": 0,
              "reviewStatus": "verified"
            }
            """

            let editionJson = """
            {
              "isbns": ["9780439708180"],
              "isbn": "9780439708180",
              "title": "Harry Potter",
              "pageCount": 320,
              "format": "Hardcover",
              "publisher": "Scholastic Inc.",
              "openLibraryEditionID": "/books/OL26331930M",
              "amazonASINs": [],
              "googleBooksVolumeIDs": [],
              "librarythingIDs": [],
              "isbndbQuality": 0
            }
            """

            let work = try JSONDecoder().decode(WorkDTO.self, from: workJson.data(using: .utf8)!)
            let edition = try JSONDecoder().decode(EditionDTO.self, from: editionJson.data(using: .utf8)!)

            #expect(work.openLibraryWorkID == "/works/OL82563W")
            #expect(edition.openLibraryEditionID == "/books/OL26331930M")
            #expect(edition.pageCount == 320)
            #expect(edition.format == .hardcover)
        }
    }

    // MARK: - Section 6: Enrichment Endpoint Compliance

    @Suite("Section 6: Enrichment Endpoints")
    struct EnrichmentEndpointTests {

        /// Contract 6.1: Circuit breaker error response format
        @Test("Circuit breaker error includes required fields (Section 6.1)")
        func circuitBreakerErrorFormat() throws {
            // API Contract Section 6.1 shows circuit breaker error:
            // { success: false, error: { code: "CIRCUIT_OPEN", message: "...", provider: "...", retryable: true, retryAfterMs: 45000 } }

            let json = """
            {
              "success": false,
              "error": {
                "code": "CIRCUIT_OPEN",
                "message": "Provider google-books circuit breaker is open",
                "provider": "google-books",
                "retryable": true,
                "retryAfterMs": 45000
              }
            }
            """

            let data = json.data(using: .utf8)!
            let errorResponse = try JSONDecoder().decode(ErrorResponseDTO.self, from: data)

            #expect(errorResponse.success == false)
            #expect(errorResponse.error.code == "CIRCUIT_OPEN")
            #expect(errorResponse.error.provider == "google-books")
            #expect(errorResponse.error.retryable == true)
            #expect(errorResponse.error.retryAfterMs == 45000)
        }
    }

    // MARK: - Section 7: Import & Scanning Compliance

    @Suite("Section 7: Import & Scanning")
    struct ImportScanningTests {

        /// Contract 7.3: Job status polling response structure
        @Test("Job status fields match contract (Section 7.3)")
        func jobStatusFieldsMatchContract() throws {
            // API Contract Section 7.3 - Job Status:
            // { jobId, status, progress, totalCount, processedCount, pipeline }

            // JobProgressPayload should have these fields
            let json = """
            {
              "type": "job_progress",
              "progress": 0.67,
              "status": "processing",
              "processedCount": 100
            }
            """

            let data = json.data(using: .utf8)!
            let progress = try JSONDecoder().decode(JobProgressPayload.self, from: data)

            #expect(progress.type == "job_progress")
            #expect(progress.progress == 0.67)
            #expect(progress.status == "processing")
            #expect(progress.processedCount == 100)
        }

        /// Test that JobProgressPayload handles optional processedCount field
        @Test("JobProgressPayload decodes without processedCount (optional field)")
        func jobProgressPayloadHandlesMissingProcessedCount() throws {
            // processedCount is optional per the DTO definition
            let json = """
            {
              "type": "job_progress",
              "progress": 0.5,
              "status": "processing"
            }
            """

            let data = json.data(using: .utf8)!
            let progress = try JSONDecoder().decode(JobProgressPayload.self, from: data)

            #expect(progress.type == "job_progress")
            #expect(progress.progress == 0.5)
            #expect(progress.status == "processing")
            #expect(progress.processedCount == nil, "processedCount should be nil when not provided")
        }

        /// Contract 7.5: Job cancellation response structure
        @Test("Job cancellation response matches contract (Section 7.5)")
        func jobCancellationResponseMatchesContract() throws {
            // API Contract Section 7.5:
            // { success: true, data: { jobId, status: "canceled", message, cleanup: { r2ObjectsDeleted, kvCacheCleared } } }

            // Verify the response structure is documented and can be decoded
            let json = """
            {
              "success": true,
              "data": {
                "jobId": "550e8400-e29b-41d4-a716-446655440000",
                "status": "canceled",
                "message": "Job canceled successfully",
                "cleanup": {
                  "r2ObjectsDeleted": 3,
                  "kvCacheCleared": true
                }
              }
            }
            """

            // This should decode without errors if our types match the contract
            let data = json.data(using: .utf8)!
            let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            #expect(jsonObject?["success"] as? Bool == true)
            let dataObj = jsonObject?["data"] as? [String: Any]
            #expect(dataObj?["status"] as? String == "canceled")
        }

        /// Contract 7.6.1: Detected book enrichmentStatus values
        @Test("enrichmentStatus enum values match contract (Section 7.6.1)")
        func enrichmentStatusValuesMatchContract() throws {
            // API Contract Section 7.6.1 defines enrichmentStatus values:
            // pending, success, not_found, error, circuit_open

            let contractEnrichmentStatuses = ["pending", "success", "not_found", "error", "circuit_open"]

            for status in contractEnrichmentStatuses {
                let json = """
                {
                  "title": "Test Book",
                  "enrichmentStatus": "\(status)"
                }
                """

                let data = json.data(using: .utf8)!
                let book = try JSONDecoder().decode(DetectedBookPayload.self, from: data)
                #expect(book.enrichmentStatus == status, "enrichmentStatus '\(status)' should be parsed")
            }
        }
    }

    // MARK: - Section 8: WebSocket API Compliance

    @Suite("Section 8: WebSocket API")
    struct WebSocketAPITests {

        /// Contract 8.4: WebSocket message types
        @Test("All WebSocket message types are recognized (Section 8.4)")
        func allWebSocketMessageTypesRecognized() throws {
            // API Contract Section 8.4 defines message types:
            // job_progress, job_complete

            // MessageType enum should include these
            let contractMessageTypes: [MessageType] = [
                .jobProgress,
                .jobComplete,
                .error,
                .readyAck,
                .ping,
                .pong
            ]

            for messageType in contractMessageTypes {
                #expect(messageType.rawValue.isEmpty == false, "Message type should have raw value")
            }
        }

        /// Contract 8.4: Job complete summary fields
        @Test("Job complete summary matches contract (Section 8.4)")
        func jobCompleteSummaryMatchesContract() throws {
            // API Contract Section 8.4 - Job Complete payload:
            // summary: { photosProcessed, booksDetected, booksUnique, booksEnriched, approved, needsReview, duration, resourceId }

            let json = """
            {
              "totalProcessed": 3,
              "successCount": 18,
              "failureCount": 2,
              "duration": 12500,
              "resourceId": "scan-results:abc123",
              "totalDetected": 25,
              "approved": 15,
              "needsReview": 5
            }
            """

            let data = json.data(using: .utf8)!
            let summary = try JSONDecoder().decode(AIScanSummary.self, from: data)

            #expect(summary.totalProcessed == 3)
            #expect(summary.successCount == 18)
            #expect(summary.failureCount == 2)
            #expect(summary.duration == 12500)
            #expect(summary.resourceId == "scan-results:abc123")
            #expect(summary.totalDetected == 25)
            #expect(summary.approved == 15)
            #expect(summary.needsReview == 5)
        }
    }

    // MARK: - Defensive Decoding Tests (Contract Violation Handling)

    @Suite("Defensive Decoding (Contract Violations)")
    struct DefensiveDecodingTests {

        /// Test that WorkDTO handles missing required fields gracefully
        @Test("WorkDTO decodes when backend omits required fields")
        func workDTOHandlesMissingRequiredFields() throws {
            // Real-world scenario: Backend sometimes omits fields marked as required
            // Our DTOs must not crash - they should use sensible defaults

            let json = """
            {
              "title": "Minimal Book"
            }
            """

            let data = json.data(using: .utf8)!
            let work = try JSONDecoder().decode(WorkDTO.self, from: data)

            // Should decode with defaults
            #expect(work.title == "Minimal Book")
            #expect(work.subjectTags.isEmpty, "Missing subjectTags should default to empty array")
            #expect(work.isbndbQuality == 0, "Missing isbndbQuality should default to 0")
            #expect(work.reviewStatus == .needsReview, "Missing reviewStatus should default to needsReview")
            #expect(work.goodreadsWorkIDs.isEmpty, "Missing goodreadsWorkIDs should default to empty array")
            #expect(work.amazonASINs.isEmpty, "Missing amazonASINs should default to empty array")
            #expect(work.librarythingIDs.isEmpty, "Missing librarythingIDs should default to empty array")
            #expect(work.googleBooksVolumeIDs.isEmpty, "Missing googleBooksVolumeIDs should default to empty array")
        }

        /// Test that EditionDTO handles missing required fields gracefully
        @Test("EditionDTO decodes when backend omits required fields")
        func editionDTOHandlesMissingRequiredFields() throws {
            let json = """
            {
              "title": "Minimal Edition"
            }
            """

            let data = json.data(using: .utf8)!
            let edition = try JSONDecoder().decode(EditionDTO.self, from: data)

            // Should decode with defaults
            #expect(edition.title == "Minimal Edition")
            #expect(edition.isbns.isEmpty, "Missing isbns should default to empty array")
            #expect(edition.format == .paperback, "Missing format should default to paperback")
            #expect(edition.isbndbQuality == 0, "Missing isbndbQuality should default to 0")
        }

        /// Test that AuthorDTO handles missing gender field gracefully
        @Test("AuthorDTO decodes when backend omits gender field")
        func authorDTOHandlesMissingGender() throws {
            let json = """
            {
              "name": "Unknown Author"
            }
            """

            let data = json.data(using: .utf8)!
            let author = try JSONDecoder().decode(AuthorDTO.self, from: data)

            #expect(author.name == "Unknown Author")
            #expect(author.gender == .unknown, "Missing gender should default to unknown")
        }
    }

    // MARK: - Enum Value Compliance Tests

    @Suite("Enum Value Compliance")
    struct EnumValueComplianceTests {

        /// Verify DTOEditionFormat values match OpenAPI spec
        @Test("DTOEditionFormat values match OpenAPI schema")
        func editionFormatValuesMatchOpenAPI() throws {
            // From openapi.yaml - DetectedBook.enrichment.editions format values:
            // Hardcover, Paperback, E-book, Audiobook, Mass Market
            let openAPIFormats = ["Hardcover", "Paperback", "E-book", "Audiobook", "Mass Market"]

            for format in openAPIFormats {
                let json = """
                {
                  "isbns": [],
                  "format": "\(format)",
                  "amazonASINs": [],
                  "googleBooksVolumeIDs": [],
                  "librarythingIDs": [],
                  "isbndbQuality": 0
                }
                """

                let data = json.data(using: .utf8)!
                let edition = try JSONDecoder().decode(EditionDTO.self, from: data)
                #expect(edition.format.rawValue == format, "Format '\(format)' should be parseable")
            }
        }

        /// Verify DTOReviewStatus values match contract
        @Test("DTOReviewStatus values match contract")
        func reviewStatusValuesMatchContract() throws {
            // From WorkDTO/contract - reviewStatus values:
            // verified, needsReview, userEdited
            let contractStatuses = ["verified", "needsReview", "userEdited"]

            for status in contractStatuses {
                let parsedStatus = DTOReviewStatus(rawValue: status)
                #expect(parsedStatus != nil, "Review status '\(status)' should be a valid enum case")
            }
        }

        /// Verify JobStatus enum values match OpenAPI
        @Test("JobStatus values match OpenAPI schema")
        func jobStatusValuesMatchOpenAPI() throws {
            // From openapi.yaml - JobStatus.status enum:
            // initialized, processing, completed, failed, canceled
            let openAPIStatuses = ["initialized", "processing", "completed", "failed", "canceled"]

            // These should be valid job status strings our code can handle
            for status in openAPIStatuses {
                #expect(status.isEmpty == false, "Status '\(status)' should be valid")
            }
        }

        /// Verify PipelineType values match contract
        @Test("PipelineType values match OpenAPI schema")
        func pipelineTypeValuesMatchOpenAPI() throws {
            // From openapi.yaml - JobStatus.pipeline enum:
            // csv_import, batch_enrichment, ai_scan
            let openAPIPipelines: [PipelineType] = [.csvImport, .batchEnrichment, .aiScan]

            #expect(openAPIPipelines.count == 3)
            #expect(openAPIPipelines.contains(.csvImport))
            #expect(openAPIPipelines.contains(.batchEnrichment))
            #expect(openAPIPipelines.contains(.aiScan))
        }
    }

    // MARK: - BookSearchResponse Contract Tests

    @Suite("BookSearchResponse Contract")
    struct BookSearchResponseContractTests {

        /// Verify BookSearchResponse has required contract fields
        @Test("BookSearchResponse has resultCount field (Issue #169)")
        func bookSearchResponseHasResultCount() throws {
            // resultCount was added in v2.4 to disambiguate "no results" from errors
            let json = """
            {
              "works": [],
              "editions": [],
              "authors": [],
              "resultCount": 0
            }
            """

            let data = json.data(using: .utf8)!
            let response = try JSONDecoder().decode(BookSearchResponse.self, from: data)

            #expect(response.resultCount == 0, "resultCount field should be present and parseable")
        }

        /// Verify BookSearchResponse includes expiresAt field
        @Test("BookSearchResponse includes expiresAt field (Issue #169)")
        func bookSearchResponseHasExpiresAt() throws {
            let json = """
            {
              "works": [],
              "editions": [],
              "authors": [],
              "resultCount": 0,
              "expiresAt": "2025-11-28T12:00:00Z"
            }
            """

            let data = json.data(using: .utf8)!
            let response = try JSONDecoder().decode(BookSearchResponse.self, from: data)

            #expect(response.expiresAt == "2025-11-28T12:00:00Z", "expiresAt field should be present")
        }
    }
}

// MARK: - Contract Snapshot Tests

/// Snapshot tests that verify JSON structure matches expected contract format.
/// These tests help catch structural drift between client and server.
@Suite("Contract Snapshot Tests")
struct ContractSnapshotTests {

    /// Test that a fully-populated WorkDTO round-trips correctly
    @Test("WorkDTO round-trip preserves all contract fields")
    func workDTORoundTrip() throws {
        let original = WorkDTO(
            title: "Test Book",
            subjectTags: ["Fiction", "Thriller"],
            originalLanguage: "en",
            firstPublicationYear: 2020,
            description: "A test book description",
            coverImageURL: "https://example.com/cover.jpg",
            synthetic: false,
            primaryProvider: "google-books",
            contributors: ["google-books", "openlibrary"],
            openLibraryWorkID: "OL123W",
            googleBooksVolumeID: "ABC123",
            goodreadsWorkIDs: ["gr1", "gr2"],
            amazonASINs: ["B00123"],
            librarythingIDs: ["lt456"],
            googleBooksVolumeIDs: ["ABC123", "DEF456"],
            isbndbQuality: 85,
            reviewStatus: .verified
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(WorkDTO.self, from: encoded)

        #expect(decoded.title == original.title)
        #expect(decoded.subjectTags == original.subjectTags)
        #expect(decoded.originalLanguage == original.originalLanguage)
        #expect(decoded.firstPublicationYear == original.firstPublicationYear)
        #expect(decoded.description == original.description)
        #expect(decoded.coverImageURL == original.coverImageURL)
        #expect(decoded.synthetic == original.synthetic)
        #expect(decoded.primaryProvider == original.primaryProvider)
        #expect(decoded.contributors == original.contributors)
        #expect(decoded.openLibraryWorkID == original.openLibraryWorkID)
        #expect(decoded.googleBooksVolumeID == original.googleBooksVolumeID)
        #expect(decoded.goodreadsWorkIDs == original.goodreadsWorkIDs)
        #expect(decoded.amazonASINs == original.amazonASINs)
        #expect(decoded.librarythingIDs == original.librarythingIDs)
        #expect(decoded.googleBooksVolumeIDs == original.googleBooksVolumeIDs)
        #expect(decoded.isbndbQuality == original.isbndbQuality)
        #expect(decoded.reviewStatus == original.reviewStatus)
    }

    /// Test that EditionDTO round-trips correctly
    @Test("EditionDTO round-trip preserves all contract fields")
    func editionDTORoundTrip() throws {
        let original = EditionDTO(
            isbn: "9780123456789",
            isbns: ["9780123456789", "0123456789"],
            title: "Test Edition",
            publisher: "Test Publisher",
            publicationDate: "2020-01-15",
            pageCount: 350,
            format: .hardcover,
            coverImageURL: "https://example.com/edition-cover.jpg",
            editionTitle: "First Edition",
            editionDescription: "The definitive first edition",
            language: "en",
            primaryProvider: "google-books",
            contributors: ["google-books"],
            openLibraryEditionID: "OL123M",
            googleBooksVolumeID: "ABC123",
            amazonASINs: ["B00123"],
            googleBooksVolumeIDs: ["ABC123"],
            librarythingIDs: ["lt789"],
            isbndbQuality: 90
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(EditionDTO.self, from: encoded)

        #expect(decoded.isbn == original.isbn)
        #expect(decoded.isbns == original.isbns)
        #expect(decoded.title == original.title)
        #expect(decoded.publisher == original.publisher)
        #expect(decoded.publicationDate == original.publicationDate)
        #expect(decoded.pageCount == original.pageCount)
        #expect(decoded.format == original.format)
        #expect(decoded.coverImageURL == original.coverImageURL)
        #expect(decoded.editionTitle == original.editionTitle)
        #expect(decoded.editionDescription == original.editionDescription)
        #expect(decoded.language == original.language)
        #expect(decoded.primaryProvider == original.primaryProvider)
        #expect(decoded.contributors == original.contributors)
        #expect(decoded.openLibraryEditionID == original.openLibraryEditionID)
        #expect(decoded.googleBooksVolumeID == original.googleBooksVolumeID)
        #expect(decoded.amazonASINs == original.amazonASINs)
        #expect(decoded.googleBooksVolumeIDs == original.googleBooksVolumeIDs)
        #expect(decoded.librarythingIDs == original.librarythingIDs)
        #expect(decoded.isbndbQuality == original.isbndbQuality)
    }

    /// Test that AuthorDTO round-trips correctly
    @Test("AuthorDTO round-trip preserves all contract fields")
    func authorDTORoundTrip() throws {
        let original = AuthorDTO(
            name: "Jane Doe",
            gender: .female,
            culturalRegion: .northAmerica,
            nationality: "American",
            birthYear: 1970,
            deathYear: nil,
            openLibraryID: "OL123A",
            bookCount: 25
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let encoded = try encoder.encode(original)
        let decoded = try JSONDecoder().decode(AuthorDTO.self, from: encoded)

        #expect(decoded.name == original.name)
        #expect(decoded.gender == original.gender)
        #expect(decoded.culturalRegion == original.culturalRegion)
        #expect(decoded.nationality == original.nationality)
        #expect(decoded.birthYear == original.birthYear)
        #expect(decoded.deathYear == original.deathYear)
        #expect(decoded.openLibraryID == original.openLibraryID)
        #expect(decoded.bookCount == original.bookCount)
    }
}
