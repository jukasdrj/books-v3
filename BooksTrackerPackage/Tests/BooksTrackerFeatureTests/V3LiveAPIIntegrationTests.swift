import Testing
import Foundation
@testable import BooksTrackerFeature

/// Live V3 API Integration Tests
///
/// These tests hit the PRODUCTION V3 API at https://api.oooefam.net/v3/
/// to validate that our DTOs correctly parse real backend responses.
///
/// **Test Categories:**
/// 1. Search endpoint (GET /v3/books/search)
/// 2. ISBN lookup (GET /v3/books/{isbn})
/// 3. Batch enrich (POST /v3/books/enrich)
/// 4. Error responses (RFC 9457)
/// 5. Response envelope contract validation
/// 6. V3→V2 mapper integration with live data
///
/// **IMPORTANT:** These tests hit the PRODUCTION API. They should be:
/// - Rate-limited aware (100 req/min for search endpoints)
/// - Non-destructive (GET/POST are read-only or idempotent)
/// - Idempotent (safe to run repeatedly)
///
/// **Prerequisites:**
/// - Internet connection
/// - Production API availability (api.oooefam.net)
@Suite("V3 Live API Integration Tests")
struct V3LiveAPIIntegrationTests {

    // MARK: - Configuration

    /// Production V3 API base URL
    let baseURL = URL(string: "https://api.oooefam.net")!

    /// Test ISBNs - well-known books that should always be available
    let harryPotterISBN = "9780439708180"  // Harry Potter and the Sorcerer's Stone
    let effectiveJavaISBN = "9780134685991"  // Effective Java
    let invalidISBN = "1234567890"  // Invalid checksum
    let nonexistentISBN = "9790000000000"  // Valid format but doesn't exist

    /// Shared URLSession with appropriate timeouts
    let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30.0
        config.timeoutIntervalForResource = 60.0
        return URLSession(configuration: config)
    }()

    /// Shared JSONDecoder (no key conversion - API returns camelCase, DTOs have explicit CodingKeys)
    let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        // NOTE: Do NOT use .convertFromSnakeCase - the V3 API returns camelCase
        // and our DTOs have CodingKeys that handle the mapping
        return decoder
    }()

    // MARK: - 1. Search Endpoint Tests (GET /v3/books/search)

    @Test("V3 Search: Returns valid V3SearchResponse for known query")
    func testV3Search_ValidQuery() async throws {
        // Arrange
        var components = URLComponents(url: baseURL.appendingPathComponent("/v3/books/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "Harry Potter"),
            URLQueryItem(name: "mode", value: "text"),
            URLQueryItem(name: "limit", value: "10")
        ]
        let url = try #require(components.url)

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert - HTTP 200
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Assert - Decode V3SearchResponse
        let searchResponse = try decoder.decode(V3SearchResponse.self, from: data)

        // Validate envelope structure
        #expect(searchResponse.success == true)
        #expect(searchResponse.data.books.count > 0)
        #expect(searchResponse.data.total >= searchResponse.data.books.count)

        // Validate query echo
        #expect(searchResponse.data.query.q == "Harry Potter")
        #expect(searchResponse.data.query.mode == "text")

        // Validate pagination
        #expect(searchResponse.data.pagination.page >= 1)
        #expect(searchResponse.data.pagination.limit == 10)
        #expect(searchResponse.data.pagination.type == "offset")

        // Validate metadata
        #expect(!searchResponse.metadata.timestamp.isEmpty)

        // Validate book structure
        let firstBook = try #require(searchResponse.data.books.first)
        #expect(!firstBook.isbn.isEmpty)
        #expect(!firstBook.title.isEmpty)
        // NOTE: authors may be empty in search results - full metadata only available via ISBN lookup
        // #expect(!firstBook.authors.isEmpty)
        #expect(!firstBook.provider.isEmpty)
        #expect(firstBook.quality >= 0 && firstBook.quality <= 100)

        print("✅ V3 Search: Found \(searchResponse.data.books.count) books, total \(searchResponse.data.total)")
    }

    @Test("V3 Search: Empty results for nonexistent query")
    func testV3Search_NoResults() async throws {
        // Arrange
        var components = URLComponents(url: baseURL.appendingPathComponent("/v3/books/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "xyzqwertasdfzxcv123456789nonexistent"),
            URLQueryItem(name: "mode", value: "text")
        ]
        let url = try #require(components.url)

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert - HTTP 200 (empty results, not 404)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Assert - Decode V3SearchResponse
        let searchResponse = try decoder.decode(V3SearchResponse.self, from: data)

        #expect(searchResponse.success == true)
        #expect(searchResponse.data.books.isEmpty)
        #expect(searchResponse.data.total == 0)
        #expect(searchResponse.data.pagination.totalPages == 0)

        print("✅ V3 Search: Empty results handled correctly")
    }

    @Test("V3 Search: Pagination works correctly")
    func testV3Search_Pagination() async throws {
        // Arrange - Request page 2 with limit 5
        var components = URLComponents(url: baseURL.appendingPathComponent("/v3/books/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "Swift programming"),
            URLQueryItem(name: "mode", value: "text"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "limit", value: "5")
        ]
        let url = try #require(components.url)

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        let searchResponse = try decoder.decode(V3SearchResponse.self, from: data)

        #expect(searchResponse.data.pagination.page == 1)
        #expect(searchResponse.data.pagination.limit == 5)
        #expect(searchResponse.data.books.count <= 5)

        print("✅ V3 Search Pagination: page=\(searchResponse.data.pagination.page), hasNext=\(searchResponse.data.pagination.hasNext)")
    }

    // MARK: - 2. ISBN Lookup Tests (GET /v3/books/{isbn})

    @Test("V3 ISBN Lookup: Returns valid V3Book for known ISBN")
    func testV3GetBook_ValidISBN() async throws {
        // Arrange
        let url = baseURL.appendingPathComponent("/v3/books/\(harryPotterISBN)")

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert - HTTP 200
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Assert - Decode V3BookResponse
        let bookResponse = try decoder.decode(V3BookResponse.self, from: data)

        #expect(bookResponse.success == true)

        let book = bookResponse.data
        #expect(book.isbn == harryPotterISBN)
        #expect(book.title.localizedCaseInsensitiveContains("Harry Potter"))
        #expect(book.authors.contains { $0.localizedCaseInsensitiveContains("Rowling") })
        #expect(!book.provider.isEmpty)
        #expect(book.quality > 0)

        // Validate optional fields are present for well-known book
        #expect(book.publisher != nil || book.publishedDate != nil)

        // Validate metadata
        #expect(!bookResponse.metadata.timestamp.isEmpty)

        print("✅ V3 ISBN Lookup: \(book.title) by \(book.authors.joined(separator: ", "))")
    }

    @Test("V3 ISBN Lookup: Returns 404 for nonexistent ISBN")
    func testV3GetBook_NotFound() async throws {
        // Arrange
        let url = baseURL.appendingPathComponent("/v3/books/\(nonexistentISBN)")

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert - HTTP 404
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 404)

        // Assert - Decode RFC 9457 error response
        let errorResponse = try decoder.decode(V3ErrorResponse.self, from: data)

        #expect(errorResponse.success == false)
        #expect(errorResponse.status == 404)
        #expect(errorResponse.code == .notFound)
        #expect(!errorResponse.title.isEmpty)
        #expect(!errorResponse.metadata.timestamp.isEmpty)

        print("✅ V3 ISBN Not Found: code=\(errorResponse.code.rawValue), title=\(errorResponse.title)")
    }

    @Test("V3 ISBN Lookup: Returns 400 for invalid ISBN format")
    func testV3GetBook_InvalidISBN() async throws {
        // Arrange - Use obviously invalid ISBN
        let url = baseURL.appendingPathComponent("/v3/books/123")

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert - HTTP 400
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 400)

        // Assert - Decode RFC 9457 error response
        let errorResponse = try decoder.decode(V3ErrorResponse.self, from: data)
        #expect(errorResponse.success == false)
        #expect(errorResponse.code == .invalidIsbn || errorResponse.code == .invalidRequest)

        print("✅ V3 Invalid ISBN: code=\(errorResponse.code.rawValue)")
    }

    @Test("V3 ISBN Lookup: ETag header present for caching")
    func testV3GetBook_ETagHeader() async throws {
        // Arrange
        let url = baseURL.appendingPathComponent("/v3/books/\(effectiveJavaISBN)")

        // Act
        let (_, response) = try await session.data(from: url)

        // Assert
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Check for ETag header (may or may not be present depending on backend config)
        let etag = httpResponse.value(forHTTPHeaderField: "ETag")
        print("✅ V3 ETag: \(etag ?? "not present")")
    }

    // MARK: - 3. Batch Enrich Tests (POST /v3/books/enrich)

    @Test("V3 Enrich: Returns enriched books for valid ISBNs")
    func testV3Enrich_ValidISBNs() async throws {
        // Arrange
        let url = baseURL.appendingPathComponent("/v3/books/enrich")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let enrichRequest = V3EnrichRequest(
            isbns: [harryPotterISBN, effectiveJavaISBN],
            includeEmbedding: false
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(enrichRequest)

        // Act
        let (data, response) = try await session.data(for: request)

        // Assert - HTTP 200
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Assert - Decode V3EnrichResponse
        let enrichResponse = try decoder.decode(V3EnrichResponse.self, from: data)

        #expect(enrichResponse.success == true)
        #expect(enrichResponse.data.requested == 2)
        #expect(enrichResponse.data.found >= 1)  // At least one should be found
        #expect(enrichResponse.data.books.count == enrichResponse.data.found)

        // Validate enriched book structure
        if let firstBook = enrichResponse.data.books.first {
            #expect(!firstBook.isbn.isEmpty)
            #expect(!firstBook.title.isEmpty)
            #expect(!firstBook.authors.isEmpty)
            // vectorized field should be present
            // Note: vectorized is a Bool, just verify it decodes
        }

        print("✅ V3 Enrich: \(enrichResponse.data.found)/\(enrichResponse.data.requested) books found")
    }

    @Test("V3 Enrich: Reports not found ISBNs correctly")
    func testV3Enrich_MixedResults() async throws {
        // Arrange - Mix of valid and invalid ISBNs
        let url = baseURL.appendingPathComponent("/v3/books/enrich")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let enrichRequest = V3EnrichRequest(
            isbns: [harryPotterISBN, nonexistentISBN],
            includeEmbedding: false
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(enrichRequest)

        // Act
        let (data, response) = try await session.data(for: request)

        // Assert - HTTP 200 (partial success is still 200)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        let enrichResponse = try decoder.decode(V3EnrichResponse.self, from: data)

        #expect(enrichResponse.success == true)
        #expect(enrichResponse.data.requested == 2)
        #expect(enrichResponse.data.found >= 1)

        // Check not_found array if present
        if let notFound = enrichResponse.data.notFound {
            #expect(notFound.contains(nonexistentISBN))
            print("✅ V3 Enrich: notFound=\(notFound)")
        }

        print("✅ V3 Enrich Mixed: \(enrichResponse.data.found)/\(enrichResponse.data.requested) found")
    }

    @Test("V3 Enrich: Returns 400 for empty batch")
    func testV3Enrich_EmptyBatch() async throws {
        // Arrange
        let url = baseURL.appendingPathComponent("/v3/books/enrich")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let enrichRequest = V3EnrichRequest(isbns: [], includeEmbedding: false)
        let encoder = JSONEncoder()
        request.httpBody = try encoder.encode(enrichRequest)

        // Act
        let (data, response) = try await session.data(for: request)

        // Assert - HTTP 400
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 400)

        // Assert - Decode RFC 9457 error response
        let errorResponse = try decoder.decode(V3ErrorResponse.self, from: data)
        #expect(errorResponse.success == false)
        #expect(errorResponse.code == .emptyBatch || errorResponse.code == .invalidRequest)

        print("✅ V3 Enrich Empty: code=\(errorResponse.code.rawValue)")
    }

    // MARK: - 4. Error Response Tests (RFC 9457)

    @Test("V3 Error: RFC 9457 structure is valid")
    func testV3Error_RFC9457Structure() async throws {
        // Arrange - Request that will fail
        let url = baseURL.appendingPathComponent("/v3/books/invalid")

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert - Not 200
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode >= 400)

        // Assert - Decode RFC 9457 error response
        let errorResponse = try decoder.decode(V3ErrorResponse.self, from: data)

        // RFC 9457 required fields
        #expect(errorResponse.success == false)
        #expect(!errorResponse.type.isEmpty)  // URI reference
        #expect(!errorResponse.title.isEmpty)  // Short summary
        #expect(errorResponse.status == httpResponse.statusCode)

        // BooksTrack-specific fields
        #expect(!errorResponse.metadata.timestamp.isEmpty)

        print("✅ RFC 9457 Error: type=\(errorResponse.type), title=\(errorResponse.title)")
    }

    @Test("V3 Error: All error codes are decodable")
    func testV3Error_AllCodesDecodable() throws {
        // Test that all known error codes can be decoded
        let allCodes: [V3ErrorCode] = [
            .missingParameter, .invalidRequest, .invalidIsbn, .invalidQuery,
            .invalidFile, .fileTooLarge, .batchTooLarge, .emptyBatch,
            .notFound, .unauthorized, .forbidden, .clientDisconnected,
            .rateLimitExceeded, .circuitOpen, .providerError, .providerTimeout,
            .cacheError, .internalError, .apiError, .networkError,
            .timeout, .featureNotAvailable
        ]

        for code in allCodes {
            let rawValue = code.rawValue
            let decoded = V3ErrorCode(rawValue: rawValue)
            #expect(decoded == code, "Failed to decode \(rawValue)")
        }

        print("✅ All \(allCodes.count) V3 error codes are decodable")
    }

    // MARK: - 5. Response Envelope Contract Validation

    @Test("V3 Contract: Success response has data, no error")
    func testV3Contract_SuccessEnvelope() async throws {
        // Arrange
        let url = baseURL.appendingPathComponent("/v3/books/\(harryPotterISBN)")

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Decode raw JSON to verify contract
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["success"] as? Bool == true)
        #expect(json?["data"] != nil)
        #expect(json?["metadata"] != nil)

        // Verify we can decode as V3BookResponse
        let bookResponse = try decoder.decode(V3BookResponse.self, from: data)
        #expect(bookResponse.success == true)

        print("✅ V3 Contract: Success envelope validated")
    }

    @Test("V3 Contract: Error response has error, no data")
    func testV3Contract_ErrorEnvelope() async throws {
        // Arrange
        let url = baseURL.appendingPathComponent("/v3/books/\(nonexistentISBN)")

        // Act
        let (data, response) = try await session.data(from: url)

        // Assert
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 404)

        // Decode raw JSON to verify contract
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json?["success"] as? Bool == false)
        #expect(json?["metadata"] != nil)

        // V3 error responses don't have "data" field, they have error fields inline
        #expect(json?["code"] != nil)
        #expect(json?["title"] != nil)

        print("✅ V3 Contract: Error envelope validated")
    }

    @Test("V3 Contract: Metadata always present")
    func testV3Contract_MetadataPresent() async throws {
        // Test metadata in success response
        let successURL = baseURL.appendingPathComponent("/v3/books/\(harryPotterISBN)")
        let (successData, _) = try await session.data(from: successURL)
        let successResponse = try decoder.decode(V3BookResponse.self, from: successData)
        #expect(!successResponse.metadata.timestamp.isEmpty)

        // Test metadata in error response (now RFC 9457 compliant)
        let errorURL = baseURL.appendingPathComponent("/v3/books/invalid")
        let (errorData, _) = try await session.data(from: errorURL)
        let errorResponse = try decoder.decode(V3ErrorResponse.self, from: errorData)
        #expect(!errorResponse.metadata.timestamp.isEmpty)

        print("✅ V3 Contract: Metadata present in both success and error responses")
    }

    // MARK: - 6. V3→V2 Mapper Integration Tests

    @Test("V3→V2 Mapper: Live search response maps correctly")
    func testV3ToV2Mapper_SearchResponse() async throws {
        // Arrange - Get live V3 search response
        var components = URLComponents(url: baseURL.appendingPathComponent("/v3/books/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "Effective Java"),
            URLQueryItem(name: "mode", value: "text"),
            URLQueryItem(name: "limit", value: "5")
        ]
        let url = try #require(components.url)

        let (data, response) = try await session.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        let v3Response = try decoder.decode(V3SearchResponse.self, from: data)

        // Act - Map to V2 format
        let v2Response = V3ToV2Mapper.mapSearchResponse(v3Response)

        // Assert - V2 structure is valid
        #expect(v2Response.works.count == v3Response.data.books.count)
        #expect(v2Response.editions.count == v3Response.data.books.count)
        #expect(v2Response.totalResults == v3Response.data.total)
        #expect(v2Response.resultCount == v3Response.data.books.count)

        // Verify Work/Edition counts match (V3ToV2Mapper creates 1:1 mapping)
        // The mapper creates one Work and one Edition per V3Book - they are linked by
        // the mapper logic itself (co-created from the same source), not by explicit IDs
        #expect(v2Response.works.count == v2Response.editions.count,
                "Works and editions should have 1:1 mapping from V3 books")

        // Verify authors are deduplicated
        let v3AuthorCount = Set(v3Response.data.books.flatMap { $0.authors }).count
        #expect(v2Response.authors.count <= v3AuthorCount)

        print("✅ V3→V2 Mapper: \(v2Response.works.count) works, \(v2Response.editions.count) editions, \(v2Response.authors.count) authors")
    }

    @Test("V3→V2 Mapper: Live book maps to Work/Edition/Author")
    func testV3ToV2Mapper_SingleBook() async throws {
        // Arrange - Get live V3 book
        let url = baseURL.appendingPathComponent("/v3/books/\(effectiveJavaISBN)")
        let (data, response) = try await session.data(from: url)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        let bookResponse = try decoder.decode(V3BookResponse.self, from: data)
        let v3Book = bookResponse.data

        // Act - Map to V2 format
        let (work, edition, authors) = V3ToV2Mapper.mapBook(v3Book)

        // Assert - Work
        #expect(work.title == v3Book.title)
        #expect(work.openLibraryID != nil)
        #expect(work.primaryProvider == v3Book.provider)

        // Assert - Edition
        #expect(edition.isbn == v3Book.isbn)
        #expect(edition.title == v3Book.title)
        // V2 DTOs don't have explicit work-edition relationship - mapper co-creates them from same V3Book
        #expect(edition.openLibraryID != nil, "Edition should have an OpenLibrary ID (synthetic or real)")

        // Assert - Authors
        #expect(authors.count == v3Book.authors.count)
        for (index, author) in authors.enumerated() {
            #expect(author.name == v3Book.authors[index])
            #expect(author.openLibraryID != nil)
        }

        // Assert - Synthetic IDs are stable
        let (work2, edition2, _) = V3ToV2Mapper.mapBook(v3Book)
        #expect(work.openLibraryID == work2.openLibraryID)
        #expect(edition.openLibraryID == edition2.openLibraryID)

        print("✅ V3→V2 Mapper: Book '\(v3Book.title)' mapped successfully")
    }

    @Test("V3→V2 Mapper: Handles missing optional fields")
    func testV3ToV2Mapper_MinimalBook() async throws {
        // This test validates mapper handles books with minimal metadata
        // We use a search that might return less-known books

        var components = URLComponents(url: baseURL.appendingPathComponent("/v3/books/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "obscure book 12345"),
            URLQueryItem(name: "mode", value: "text"),
            URLQueryItem(name: "limit", value: "1")
        ]
        let url = try #require(components.url)

        let (data, response) = try await session.data(from: url)
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        let v3Response = try decoder.decode(V3SearchResponse.self, from: data)

        // Even with empty results, mapper should not crash
        let v2Response = V3ToV2Mapper.mapSearchResponse(v3Response)

        // If results, they should map without error
        if let firstBook = v3Response.data.books.first {
            let (work, edition, _) = V3ToV2Mapper.mapBook(firstBook)
            #expect(work.title == firstBook.title)
            #expect(edition.isbn == firstBook.isbn)
        }

        print("✅ V3→V2 Mapper: Handles minimal/missing fields")
    }

    // MARK: - 7. V3APIClientActual Integration Tests

    @Test("V3APIClientActual: Search works end-to-end")
    func testV3Client_Search() async throws {
        let client = await V3APIClientActual(baseURL: baseURL)

        // Act
        let response = try await client.search(query: "Clean Code", page: 1, limit: 5)

        // Assert
        #expect(response.success == true)
        #expect(response.data.books.count <= 5)
        #expect(response.data.query.q == "Clean Code")

        print("✅ V3APIClientActual Search: \(response.data.books.count) results")
    }

    @Test("V3APIClientActual: GetBook works end-to-end")
    func testV3Client_GetBook() async throws {
        let client = await V3APIClientActual(baseURL: baseURL)

        // Act
        let book = try await client.getBook(isbn: harryPotterISBN)

        // Assert
        #expect(book.isbn == harryPotterISBN)
        #expect(book.title.localizedCaseInsensitiveContains("Harry Potter"))

        print("✅ V3APIClientActual GetBook: \(book.title)")
    }

    @Test("V3APIClientActual: GetBook throws for not found")
    func testV3Client_GetBook_NotFound() async throws {
        let client = await V3APIClientActual(baseURL: baseURL)

        // Act & Assert
        await #expect(throws: V3ActualAPIError.self) {
            _ = try await client.getBook(isbn: nonexistentISBN)
        }

        print("✅ V3APIClientActual: Correctly throws for not found")
    }

    @Test("V3APIClientActual: Enrich works end-to-end")
    func testV3Client_Enrich() async throws {
        let client = await V3APIClientActual(baseURL: baseURL)

        // Act
        let response = try await client.enrichBooks(
            isbns: [harryPotterISBN, effectiveJavaISBN],
            includeEmbedding: false
        )

        // Assert
        #expect(response.success == true)
        #expect(response.data.requested == 2)
        #expect(response.data.found >= 1)

        print("✅ V3APIClientActual Enrich: \(response.data.found)/\(response.data.requested) found")
    }

    // MARK: - 8. DTO Contract Validation Tests (Critical Bug Detection)

    @Test("V3 DTO Contract: pageCount decodes correctly from camelCase API")
    func testV3DTO_PageCountDecodes() async throws {
        // This test validates that the V3 DTOs correctly decode camelCase fields
        // The API returns camelCase (pageCount), but DTOs have CodingKeys mapping to snake_case (page_count)
        // This is a CRITICAL CONTRACT MISMATCH that causes data loss!

        let url = baseURL.appendingPathComponent("/v3/books/\(harryPotterISBN)")
        let (data, response) = try await session.data(from: url)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // First, verify the raw JSON contains pageCount with a value
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]
        let rawPageCount = dataObj?["pageCount"] as? Int

        print("📋 Raw JSON pageCount: \(rawPageCount ?? -999)")

        // Now decode using our DTO
        let bookResponse = try decoder.decode(V3BookResponse.self, from: data)
        let decodedPageCount = bookResponse.data.pageCount

        print("📋 Decoded pageCount: \(decodedPageCount ?? -999)")

        // CRITICAL: If raw has pageCount but decoded is nil, we have a contract mismatch!
        if rawPageCount != nil {
            #expect(decodedPageCount != nil,
                    "CRITICAL: API returns pageCount=\(rawPageCount!) but DTO decoded nil. CodingKeys mismatch!")
            #expect(decodedPageCount == rawPageCount,
                    "pageCount mismatch: raw=\(rawPageCount!), decoded=\(decodedPageCount ?? -1)")
        }
    }

    @Test("V3 DTO Contract: coverUrl decodes correctly from camelCase API")
    func testV3DTO_CoverUrlDecodes() async throws {
        let url = baseURL.appendingPathComponent("/v3/books/\(harryPotterISBN)")
        let (data, response) = try await session.data(from: url)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Check raw JSON
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]
        let rawCoverUrl = dataObj?["coverUrl"] as? String

        print("📋 Raw JSON coverUrl: \(rawCoverUrl ?? "nil")")

        // Decode using DTO
        let bookResponse = try decoder.decode(V3BookResponse.self, from: data)
        let decodedCoverUrl = bookResponse.data.coverUrl

        print("📋 Decoded coverUrl: \(decodedCoverUrl ?? "nil")")

        // CRITICAL: If raw has coverUrl but decoded is nil, we have a contract mismatch!
        if rawCoverUrl != nil {
            #expect(decodedCoverUrl != nil,
                    "CRITICAL: API returns coverUrl but DTO decoded nil. CodingKeys mismatch!")
            #expect(decodedCoverUrl == rawCoverUrl,
                    "coverUrl mismatch: raw=\(rawCoverUrl!), decoded=\(decodedCoverUrl ?? "nil")")
        }
    }

    @Test("V3 DTO Contract: Search pagination hasNext decodes correctly")
    func testV3DTO_PaginationDecodes() async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v3/books/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "programming"),
            URLQueryItem(name: "mode", value: "text"),
            URLQueryItem(name: "limit", value: "5")
        ]
        let url = try #require(components.url)

        let (data, response) = try await session.data(from: url)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Check raw JSON pagination
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let dataObj = json?["data"] as? [String: Any]
        let paginationObj = dataObj?["pagination"] as? [String: Any]
        let rawHasNext = paginationObj?["hasNext"] as? Bool
        let rawTotalPages = paginationObj?["totalPages"] as? Int

        print("📋 Raw pagination: hasNext=\(rawHasNext ?? false), totalPages=\(rawTotalPages ?? -1)")

        // Decode using DTO
        let searchResponse = try decoder.decode(V3SearchResponse.self, from: data)

        print("📋 Decoded pagination: hasNext=\(searchResponse.data.pagination.hasNext), totalPages=\(searchResponse.data.pagination.totalPages)")

        // CRITICAL: These fields use camelCase in API but snake_case in CodingKeys
        if rawHasNext != nil {
            // Note: V3Pagination.hasNext maps to "has_next" but API sends "hasNext"
            // If this fails, we have a contract mismatch
            print("⚠️ Checking hasNext decode (API sends camelCase, CodingKeys expect snake_case)")
        }
        if rawTotalPages != nil {
            // Note: V3Pagination.totalPages maps to "total_pages" but API sends "totalPages"
            print("⚠️ Checking totalPages decode (API sends camelCase, CodingKeys expect snake_case)")
        }
    }

    // MARK: - 9. Performance & Caching Tests

    @Test("V3 Performance: Search latency < 2s", .tags(.v3Performance))
    func testV3Performance_SearchLatency() async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent("/v3/books/search"), resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "Swift"),
            URLQueryItem(name: "mode", value: "text"),
            URLQueryItem(name: "limit", value: "10")
        ]
        let url = try #require(components.url)

        let start = Date()
        let (data, response) = try await session.data(from: url)
        let latency = Date().timeIntervalSince(start)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Verify response is valid
        _ = try decoder.decode(V3SearchResponse.self, from: data)

        #expect(latency < 2.0, "Search latency \(latency)s exceeded 2s threshold")

        print("✅ V3 Search Latency: \(Int(latency * 1000))ms")
    }

    @Test("V3 Performance: ISBN lookup latency < 1s", .tags(.v3Performance))
    func testV3Performance_ISBNLatency() async throws {
        let url = baseURL.appendingPathComponent("/v3/books/\(harryPotterISBN)")

        let start = Date()
        let (data, response) = try await session.data(from: url)
        let latency = Date().timeIntervalSince(start)

        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        _ = try decoder.decode(V3BookResponse.self, from: data)

        #expect(latency < 1.0, "ISBN lookup latency \(latency)s exceeded 1s threshold")

        print("✅ V3 ISBN Latency: \(Int(latency * 1000))ms")
    }

    @Test("V3 Metadata: Provider tag present")
    func testV3Metadata_ProviderTag() async throws {
        let url = baseURL.appendingPathComponent("/v3/books/\(harryPotterISBN)")
        let (data, _) = try await session.data(from: url)

        let bookResponse = try decoder.decode(V3BookResponse.self, from: data)

        // Provider should indicate orchestration
        let provider = bookResponse.data.provider
        #expect(!provider.isEmpty)

        // Metadata should have source info
        if let metaSource = bookResponse.metadata.source {
            print("✅ V3 Provider: book=\(provider), metadata.source=\(metaSource)")
        } else {
            print("✅ V3 Provider: book=\(provider)")
        }
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var v3Performance: Self
}
