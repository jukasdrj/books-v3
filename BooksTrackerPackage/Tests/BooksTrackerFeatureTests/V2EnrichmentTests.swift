import Testing
import Foundation
@testable import BooksTrackerFeature

/// Tests for V2 synchronous book enrichment
@MainActor
struct V2EnrichmentTests {
    
    // MARK: - DTO Tests
    
    @Test("V2 enrichment request encodes correctly")
    func testV2EnrichmentRequestEncoding() throws {
        let request = V2EnrichmentRequest(
            barcode: "9780747532743",
            preferProvider: "auto",
            idempotencyKey: "scan_20251125_test"
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try #require(String(data: data, encoding: .utf8))
        
        #expect(json.contains("\"barcode\":\"9780747532743\""))
        #expect(json.contains("\"prefer_provider\":\"auto\""))
        #expect(json.contains("\"idempotency_key\":\"scan_20251125_test\""))
    }
    
    @Test("V2 enrichment response decodes correctly")
    func testV2EnrichmentResponseDecoding() throws {
        let json = """
        {
          "isbn": "9780747532743",
          "title": "Harry Potter and the Philosopher's Stone",
          "authors": ["J.K. Rowling"],
          "publisher": "Bloomsbury",
          "published_date": "1997-06-26",
          "page_count": 223,
          "cover_url": "https://example.com/cover.jpg",
          "description": "Harry Potter has never been...",
          "provider": "orchestrated:google+openlibrary",
          "enriched_at": "2025-11-25T10:30:00Z"
        }
        """
        
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let response = try decoder.decode(V2EnrichmentResponse.self, from: data)
        
        #expect(response.isbn == "9780747532743")
        #expect(response.title == "Harry Potter and the Philosopher's Stone")
        #expect(response.authors == ["J.K. Rowling"])
        #expect(response.publisher == "Bloomsbury")
        #expect(response.publishedDate == "1997-06-26")
        #expect(response.pageCount == 223)
        #expect(response.coverUrl == "https://example.com/cover.jpg")
        #expect(response.provider == "orchestrated:google+openlibrary")
    }
    
    @Test("V2 enrichment error response decodes correctly")
    func testV2EnrichmentErrorDecoding() throws {
        let json = """
        {
          "error": "BOOK_NOT_FOUND",
          "message": "No book data found for ISBN",
          "providers_checked": ["google", "openlibrary"]
        }
        """
        
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let response = try decoder.decode(V2EnrichmentErrorResponse.self, from: data)
        
        #expect(response.code == "BOOK_NOT_FOUND")
        #expect(response.message == "No book data found for ISBN")
        #expect(response.providersChecked == ["google", "openlibrary"])
    }
    
    @Test("V2 rate limit error response decodes correctly")
    func testV2RateLimitErrorDecoding() throws {
        let json = """
        {
          "error": "rate_limit_exceeded",
          "message": "Rate limit of 1000 requests per hour exceeded",
          "retry_after": 3600,
          "limit": 1000,
          "remaining": 0,
          "reset_at": "2025-11-25T11:00:00Z"
        }
        """
        
        let data = try #require(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let response = try decoder.decode(V2RateLimitErrorResponse.self, from: data)
        
        #expect(response.code == "rate_limit_exceeded")
        #expect(response.message == "Rate limit of 1000 requests per hour exceeded")
        #expect(response.retryAfter == 3600)
        #expect(response.limit == 1000)
        #expect(response.remaining == 0)
    }
    
    // MARK: - Error Message Tests
    
    @Test("Book not found error has user-friendly message")
    func testBookNotFoundErrorMessage() {
        let error = EnrichmentV2Error.bookNotFound(
            message: "No book data found for ISBN",
            providersChecked: ["google", "openlibrary"]
        )
        
        let description = error.errorDescription
        #expect(description != nil)
        #expect(description!.contains("No book data found"))
        #expect(description!.contains("google"))
        #expect(description!.contains("openlibrary"))
    }
    
    @Test("Rate limit error shows retry time in minutes")
    func testRateLimitErrorMessageMinutes() {
        let error = EnrichmentV2Error.rateLimitExceeded(
            retryAfter: 120,
            message: "Rate limit exceeded"
        )
        
        let description = error.errorDescription
        #expect(description != nil)
        #expect(description!.contains("2 minute"))
    }
    
    @Test("Rate limit error shows retry time in seconds for short waits")
    func testRateLimitErrorMessageSeconds() {
        let error = EnrichmentV2Error.rateLimitExceeded(
            retryAfter: 30,
            message: "Rate limit exceeded"
        )
        
        let description = error.errorDescription
        #expect(description != nil)
        #expect(description!.contains("30 seconds"))
    }
    
    @Test("Invalid barcode error includes barcode value")
    func testInvalidBarcodeError() {
        let error = EnrichmentV2Error.invalidBarcode(barcode: "invalid123")
        
        let description = error.errorDescription
        #expect(description != nil)
        #expect(description!.contains("invalid123"))
    }
    
    // MARK: - Sendable Compliance Tests
    
    @Test("V2 enrichment request is Sendable")
    func testV2EnrichmentRequestIsSendable() {
        let request = V2EnrichmentRequest(
            barcode: "9780747532743",
            preferProvider: "auto",
            idempotencyKey: "test_key"
        )
        
        // If this compiles, Sendable conformance is working
        Task.detached {
            let _ = request
        }
    }
    
    @Test("V2 enrichment response is Sendable")
    func testV2EnrichmentResponseIsSendable() {
        let response = V2EnrichmentResponse(
            isbn: "9780747532743",
            title: "Test Book",
            authors: ["Test Author"],
            publisher: "Test Publisher",
            publishedDate: "2025-01-01",
            pageCount: 100,
            coverUrl: "https://example.com/cover.jpg",
            description: "Test description",
            categories: ["Fiction"],
            language: "en",
            provider: "test",
            enrichedAt: "2025-11-25T10:30:00Z"
        )
        
        // If this compiles, Sendable conformance is working
        Task.detached {
            let _ = response
        }
    }
    
    @Test("EnrichmentV2Error is Sendable")
    func testEnrichmentV2ErrorIsSendable() {
        let error = EnrichmentV2Error.bookNotFound(
            message: "Not found",
            providersChecked: ["google"]
        )
        
        // If this compiles, Sendable conformance is working
        Task.detached {
            let _ = error
        }
    }
}
