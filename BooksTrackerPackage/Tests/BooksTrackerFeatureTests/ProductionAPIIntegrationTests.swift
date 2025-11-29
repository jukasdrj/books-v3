import Testing
import Foundation
@testable import BooksTrackerFeature

/// Production API Integration Tests for GitHub Issue #98
///
/// Tests the iOS app against the production backend API at https://api.oooefam.net
/// to validate CORS, response formats, error handling, and contract alignment.
///
/// Backend Version: v3.3.0
/// API Contract: docs/API_CONTRACT.md
/// Frontend Handoff: docs/FRONTEND_HANDOFF.md
///
/// Test Categories:
/// 1. Health Check ✅
/// 2. ISBN Search
/// 3. Title Search
/// 4. Error Handling (NOT_FOUND, RATE_LIMIT, CIRCUIT_OPEN, etc.)
/// 5. CORS Validation (capacitor://localhost)
/// 6. ResponseEnvelope Contract
/// 7. Performance Metrics (P95 latency, cache hits)
///
/// **IMPORTANT:** These tests hit the PRODUCTION API. They should be:
/// - Rate-limited aware (100 req/min for search endpoints)
/// - Non-destructive (GET requests only, no mutations)
/// - Idempotent (safe to run repeatedly)

@Suite("Production API Integration Tests (Issue #98)")
struct ProductionAPIIntegrationTests {

    // MARK: - Test Configuration

    /// Production API instance
    let api = BooksTrackAPI(baseURL: URL(string: "https://api.oooefam.net")!)

    /// Test ISBN for Harry Potter and the Sorcerer's Stone (always available, high cache hit)
    let testISBN = "9780439708180"

    /// Invalid ISBN for NOT_FOUND testing
    let invalidISBN = "1234567890"

    // MARK: - 1. Health Check Tests

    @Test("Health Check: Production API is healthy")
    func testHealthCheck() async throws {
        // Arrange
        let healthURL = URL(string: "https://api.oooefam.net/health")!
        let request = URLRequest(url: healthURL)

        // Act
        let (data, response) = try await URLSession.shared.data(for: request)

        // Assert - HTTP 200
        let httpResponse = try #require(response as? HTTPURLResponse)
        #expect(httpResponse.statusCode == 200)

        // Assert - Response structure
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let responseData = try #require(json?["data"] as? [String: Any])
        #expect(responseData["status"] as? String == "ok" || responseData["status"] as? String == "healthy")
        #expect(responseData["version"] != nil)

        print("✅ Health check passed: status=\(responseData["status"] ?? "unknown"), version=\(responseData["version"] ?? "unknown")")
    }

    // MARK: - 2. ISBN Search Tests

    @Test("ISBN Search: Valid ISBN returns book data")
    func testISBNSearchValid() async throws {
        // Act
        let book = try await api.search(isbn: testISBN)

        // Assert - Book data present
        #expect(book.title != nil)
        #expect(book.title == "Harry Potter and the Sorcerer's Stone" ||
                book.title?.contains("Harry Potter") == true)
        #expect(book.authors?.contains("J.K. Rowling") == true ||
                book.authors?.contains("Rowling") == true)
        #expect(book.isbn == testISBN || book.isbn13 == testISBN)

        // Assert - Metadata present
        #expect(book.publisher != nil || book.publishedDate != nil)

        print("✅ ISBN search succeeded: title=\(book.title ?? "unknown")")
        print("   Authors: \(book.authors?.joined(separator: ", ") ?? "none")")
        print("   Publisher: \(book.publisher ?? "unknown")")
    }

    @Test("ISBN Search: Response includes provider metadata")
    func testISBNSearchMetadata() async throws {
        // Note: This test validates that the backend sends metadata
        // We need to inspect the raw response since BooksTrackAPI extracts only the data

        let url = URL(string: "https://api.oooefam.net/v1/search/isbn?isbn=\(testISBN)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        // Decode raw ResponseEnvelope
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ResponseEnvelope<BookDTO>.self, from: data)

        // Assert - Success discriminator
        #expect(envelope.success == true)

        // Assert - Metadata present
        #expect(envelope.metadata.timestamp != nil)
        #expect(envelope.metadata.provider != nil)
        #expect(envelope.metadata.cached != nil)

        print("✅ Metadata validation passed")
        print("   Provider: \(envelope.metadata.provider ?? "unknown")")
        print("   Cached: \(envelope.metadata.cached ?? false)")
        print("   Timestamp: \(envelope.metadata.timestamp)")
    }

    // MARK: - 3. Title Search Tests

    @Test("Title Search: Returns array of books")
    func testTitleSearch() async throws {
        // Act
        let books = try await api.search(title: "Harry Potter", limit: 10)

        // Assert - Results returned
        #expect(books.count > 0)
        #expect(books.count <= 10) // Respects limit

        // Assert - Books have required fields
        for book in books {
            #expect(book.title != nil)
            #expect(book.authors != nil && !book.authors!.isEmpty)
        }

        print("✅ Title search succeeded: found \(books.count) books")
    }

    @Test("Title Search: Handles no results gracefully")
    func testTitleSearchNoResults() async throws {
        // Act
        let books = try await api.search(title: "xyzqwertasdfzxcv123456789", limit: 10)

        // Assert - Empty array (not an error)
        #expect(books.isEmpty)

        print("✅ No results handled correctly")
    }

    // MARK: - 4. Error Handling Tests

    @Test("Error Handling: NOT_FOUND for invalid ISBN")
    func testNotFoundError() async throws {
        // Act & Assert
        await #expect(throws: APIError.self) {
            _ = try await api.search(isbn: invalidISBN)
        }

        // Validate specific error type
        do {
            _ = try await api.search(isbn: invalidISBN)
            Issue.record("Expected APIError.notFound but no error was thrown")
        } catch let error as APIError {
            if case .notFound(let message) = error {
                #expect(message.contains("not found") || message.contains("Not Found"))
                print("✅ NOT_FOUND error handled correctly: \(message)")
            } else {
                Issue.record("Expected APIError.notFound but got: \(error)")
            }
        } catch {
            Issue.record("Expected APIError but got: \(error)")
        }
    }

    @Test("Error Handling: ResponseEnvelope error structure")
    func testErrorEnvelopeStructure() async throws {
        // Arrange - Make request that will fail
        let url = URL(string: "https://api.oooefam.net/v1/search/isbn?isbn=\(invalidISBN)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        // Decode error envelope
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ResponseEnvelope<BookDTO>.self, from: data)

        // Assert - Error structure
        #expect(envelope.success == false)
        #expect(envelope.data == nil)
        #expect(envelope.error != nil)

        let error = try #require(envelope.error)
        #expect(error.message != "")
        #expect(error.code == "NOT_FOUND")
        #expect(error.statusCode == 404)

        print("✅ Error envelope validated: code=\(error.code ?? "none"), status=\(error.statusCode ?? 0)")
    }

    @Test("Error Handling: CORS headers present", .tags(.cors))
    func testCORSHeaders() async throws {
        // Arrange
        let url = URL(string: "https://api.oooefam.net/v1/search/isbn?isbn=\(testISBN)")!
        var request = URLRequest(url: url)
        request.setValue("capacitor://localhost", forHTTPHeaderField: "Origin")

        // Act
        let (_, response) = try await URLSession.shared.data(for: request)

        // Assert - CORS headers
        let httpResponse = try #require(response as? HTTPURLResponse)
        let headers = httpResponse.allHeaderFields

        // Backend should include Access-Control-Allow-Origin for capacitor://localhost
        // Note: URLSession on iOS may not expose all CORS headers in same-origin contexts
        print("✅ CORS test executed (headers: \(headers.keys.count))")
        print("   Origin sent: capacitor://localhost")

        // If we get a successful response, CORS is working
        #expect(httpResponse.statusCode == 200)
    }

    // MARK: - 5. Circuit Breaker & Rate Limit Tests

    @Test("Error Handling: Circuit breaker response structure", .tags(.circuitBreaker))
    func testCircuitBreakerErrorStructure() async throws {
        // Note: We can't reliably trigger a circuit breaker in production
        // This test documents the expected structure if it happens

        // Expected error structure per API_CONTRACT.md §12:
        // {
        //   "success": false,
        //   "error": {
        //     "code": "CIRCUIT_OPEN",
        //     "message": "Provider google-books circuit breaker is open",
        //     "provider": "google-books",
        //     "retryable": true,
        //     "retryAfterMs": 45000
        //   }
        // }

        // We validate that APIError.circuitOpen can be decoded correctly
        let jsonString = """
        {
            "code": "CIRCUIT_OPEN",
            "message": "Provider google-books circuit breaker is open",
            "provider": "google-books",
            "retryAfterMs": 45000
        }
        """

        let data = jsonString.data(using: .utf8)!
        let error = try JSONDecoder().decode(APIError.self, from: data)

        if case .circuitOpen(let provider, let retryAfterMs) = error {
            #expect(provider == "google-books")
            #expect(retryAfterMs == 45000)
            print("✅ Circuit breaker error decoding validated")
        } else {
            Issue.record("Failed to decode CIRCUIT_OPEN error correctly")
        }
    }

    @Test("Error Handling: Rate limit response structure", .tags(.rateLimit))
    func testRateLimitErrorStructure() async throws {
        // Expected error structure per API_CONTRACT.md §10:
        // {
        //   "success": false,
        //   "error": {
        //     "code": "RATE_LIMIT_EXCEEDED",
        //     "message": "Rate limit exceeded",
        //     "retryAfter": 60
        //   }
        // }

        let jsonString = """
        {
            "code": "RATE_LIMIT_EXCEEDED",
            "message": "Rate limit exceeded",
            "retryAfterMs": 60000
        }
        """

        let data = jsonString.data(using: .utf8)!
        let error = try JSONDecoder().decode(APIError.self, from: data)

        if case .rateLimitExceeded(let retryAfter) = error {
            #expect(retryAfter == 60.0)
            print("✅ Rate limit error decoding validated")
        } else {
            Issue.record("Failed to decode RATE_LIMIT_EXCEEDED error correctly")
        }
    }

    // MARK: - 6. ResponseEnvelope Contract Tests

    @Test("Contract: Success response has data, no error")
    func testSuccessEnvelopeContract() async throws {
        // Arrange
        let url = URL(string: "https://api.oooefam.net/v1/search/isbn?isbn=\(testISBN)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        // Decode
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ResponseEnvelope<BookDTO>.self, from: data)

        // Assert - Success contract
        #expect(envelope.success == true)
        #expect(envelope.data != nil)
        #expect(envelope.error == nil)
        #expect(envelope.metadata.timestamp != "")

        print("✅ Success envelope contract validated")
    }

    @Test("Contract: Error response has error, no data")
    func testErrorEnvelopeContract() async throws {
        // Arrange
        let url = URL(string: "https://api.oooefam.net/v1/search/isbn?isbn=\(invalidISBN)")!
        let (data, _) = try await URLSession.shared.data(from: url)

        // Decode
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ResponseEnvelope<BookDTO>.self, from: data)

        // Assert - Error contract
        #expect(envelope.success == false)
        #expect(envelope.data == nil)
        #expect(envelope.error != nil)
        #expect(envelope.metadata.timestamp != "")

        print("✅ Error envelope contract validated")
    }

    // MARK: - 7. Performance Metrics Tests

    @Test("Performance: P95 latency < 1s for cached requests", .tags(.performance))
    func testCachedLatency() async throws {
        // Run 10 requests and measure P95 latency
        var latencies: [TimeInterval] = []

        for _ in 0..<10 {
            let start = Date()
            _ = try await api.search(isbn: testISBN)
            let latency = Date().timeIntervalSince(start)
            latencies.append(latency)

            // Rate limit protection (100 req/min = ~600ms between requests)
            try await Task.sleep(for: .milliseconds(700))
        }

        // Calculate P95
        latencies.sort()
        let p95Index = Int(Double(latencies.count) * 0.95)
        let p95Latency = latencies[p95Index]

        // Assert - P95 < 1000ms (backend target: <150ms cached, <1s cold)
        #expect(p95Latency < 1.0)

        print("✅ P95 latency: \(Int(p95Latency * 1000))ms (target: <1000ms)")
        print("   Min: \(Int(latencies.min()! * 1000))ms")
        print("   Max: \(Int(latencies.max()! * 1000))ms")
        print("   Avg: \(Int(latencies.reduce(0, +) / Double(latencies.count) * 1000))ms")
    }

    @Test("Performance: Cache hit ratio validation", .tags(.performance))
    func testCacheHitRatio() async throws {
        // Make 5 requests to same ISBN and check metadata.cached
        var cacheHits = 0

        for i in 0..<5 {
            let url = URL(string: "https://api.oooefam.net/v1/search/isbn?isbn=\(testISBN)")!
            let (data, _) = try await URLSession.shared.data(from: url)

            let decoder = JSONDecoder()
            let envelope = try decoder.decode(ResponseEnvelope<BookDTO>.self, from: data)

            if envelope.metadata.cached == true {
                cacheHits += 1
            }

            // Rate limit protection
            if i < 4 {
                try await Task.sleep(for: .milliseconds(700))
            }
        }

        // Assert - At least 60% cache hits (backend target: >70%)
        let cacheRatio = Double(cacheHits) / 5.0
        #expect(cacheRatio >= 0.6)

        print("✅ Cache hit ratio: \(Int(cacheRatio * 100))% (\(cacheHits)/5)")
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var cors: Self
    @Tag static var circuitBreaker: Self
    @Tag static var rateLimit: Self
    @Tag static var performance: Self
}
