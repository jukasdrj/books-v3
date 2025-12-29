
import Testing
import Foundation
@testable import BooksTrackerFeature

/// Integration tests for live API endpoints
///
/// **Purpose:**
/// Validates that the frontend can successfully communicate with the backend API.
/// These tests make REAL network requests to the production API.
///
/// **Prerequisites:**
/// - Internet connection
/// - Production API availability (api.oooefam.net)
///
/// **Note:**
/// These tests are designed to be read-only (Search) or non-destructive.
@Suite("API Integration Tests")
struct APIIntegrationTests {

    // MARK: - Configuration

    // Use the production URL from config, but ensure we are testing what we think we are
    private let baseURL = EnrichmentConfig.baseURL

    // MARK: - Search API Tests (V3)

    // Migrated to V3 API (V1 sunset March 1, 2026)
    // Use V3 endpoints: bookByISBNURL(isbn:) and searchURL with query parameters

    @Test("GET /v3/books/{isbn} returns valid results for known ISBN")
    func testSearchISBN_Valid() async throws {
        // Harry Potter and the Sorcerer's Stone
        let isbn = "9780439708180"
        let url = EnrichmentConfig.bookByISBNURL(isbn: isbn)

        let (data, response) = try await URLSession.shared.data(from: url)

        // 1. Verify HTTP 200
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }
        #expect(httpResponse.statusCode == 200)

        // 2. Decode Response
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        // V3 returns V3BookResponse for single ISBN lookup
        let envelope = try decoder.decode(V3BookResponse.self, from: data)

        guard envelope.success else {
            Issue.record("Expected success response, got failure")
            return
        }

        // 3. Verify Content
        // Should find Harry Potter
        let book = envelope.data
        #expect(book.title.localizedCaseInsensitiveContains("Harry Potter"), "Title should contain 'Harry Potter'")
        #expect(book.isbn == isbn, "ISBN should match")
    }

    @Test("GET /v3/books/{isbn} returns 404 for unknown ISBN")
    func testSearchISBN_Unknown() async throws {
        // Random non-existent ISBN
        let isbn = "0000000000000"
        let url = EnrichmentConfig.bookByISBNURL(isbn: isbn)

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        // V3 API should return 404 for unknown ISBN
        if httpResponse.statusCode == 404 {
            // This is expected behavior for V3
            #expect(httpResponse.statusCode == 404)
        } else if httpResponse.statusCode == 200 {
            // Check if it's a success=false response (soft 404)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            // Try decoding as error response
            if let errorResponse = try? decoder.decode(V3ErrorResponse.self, from: data) {
                #expect(!errorResponse.success)
            } else {
                 Issue.record("Expected 404 or Error Response, got 200 OK with unknown body")
            }
        } else {
             // 400 or other errors are also possible
             #expect(httpResponse.statusCode == 404 || httpResponse.statusCode == 400)
        }
    }

    @Test("GET /v3/books/search returns results for fuzzy query")
    func testSearchTitle_Fuzzy() async throws {
        let query = "Great Gatsby"
        let url = EnrichmentConfig.searchURL.appending(queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "5")
        ])

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }
        #expect(httpResponse.statusCode == 200)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(V3SearchResponse.self, from: data)

        guard envelope.success else {
            Issue.record("Expected success response")
            return
        }

        #expect(!envelope.data.books.isEmpty, "Should return books")

        let firstMatch = envelope.data.books.first
        #expect(firstMatch?.title.localizedCaseInsensitiveContains("Gatsby") ?? false)
    }

    @Test("GET /v3/books/search handles combined query (Advanced Search)")
    func testSearchAdvanced_Author() async throws {
        let title = "Foundation"
        let author = "Asimov"

        // V3 Unified Search uses a single 'q' parameter
        let query = "\(title) \(author)"

        let url = EnrichmentConfig.searchURL.appending(queryItems: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: "5")
        ])

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }
        #expect(httpResponse.statusCode == 200)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(V3SearchResponse.self, from: data)

        guard envelope.success else {
            Issue.record("Expected success response")
            return
        }

        #expect(!envelope.data.books.isEmpty)

        // Verify author match in results
        let hasAsimov = envelope.data.books.contains { book in
            book.authors.contains { authorName in
                authorName.localizedCaseInsensitiveContains("Asimov")
            }
        }
        #expect(hasAsimov, "Results should contain author 'Asimov'")
    }

    // MARK: - Health Check

    @Test("API Health Check is accessible")
    func testHealthCheck() async throws {
        // WebSocket is deprecated. V3 uses SSE.
        // We verify the API health endpoint as a proxy for connectivity.

        let healthURL = EnrichmentConfig.healthCheckURL
        let (data, response) = try await URLSession.shared.data(from: healthURL)

        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }

        #expect(httpResponse.statusCode == 200)

        // Optional: Check body if it returns "OK" or similar
        let body = String(data: data, encoding: .utf8)
        #expect(body != nil)

        // V3 API typically returns a JSON health status
        // e.g., {"status":"ok","version":"..."}
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
             #expect(json["status"] as? String == "ok" || json["status"] as? String == "healthy")
        }
    }
}
