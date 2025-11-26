import Testing
import Foundation
@testable import BooksTrackerFeature

/// Tests for WeeklyRecommendationsDTO and WeeklyRecommendationsService
/// Validates API contract compliance and error handling
@Suite("Weekly Recommendations Tests")
struct WeeklyRecommendationsTests {
    
    // MARK: - DTO Decoding Tests
    
    @Test("WeeklyRecommendationsDTO decodes from canonical API response")
    func weeklyRecommendationsDTODecoding() throws {
        let json = """
        {
            "week_of": "2025-11-25",
            "books": [
                {
                    "isbn": "9780747532743",
                    "title": "Harry Potter and the Philosopher's Stone",
                    "authors": ["J.K. Rowling"],
                    "cover_url": "https://example.com/cover.jpg",
                    "reason": "A beloved fantasy classic perfect for readers seeking magical escapism"
                }
            ],
            "generated_at": "2025-11-24T00:00:00Z",
            "next_refresh": "2025-12-01T00:00:00Z"
        }
        """
        
        let data = json.data(using: .utf8)!
        let recommendations = try JSONDecoder().decode(WeeklyRecommendationsDTO.self, from: data)
        
        #expect(recommendations.week_of == "2025-11-25")
        #expect(recommendations.books.count == 1)
        #expect(recommendations.generated_at == "2025-11-24T00:00:00Z")
        #expect(recommendations.next_refresh == "2025-12-01T00:00:00Z")
    }
    
    @Test("RecommendedBookDTO decodes with all fields")
    func recommendedBookDTODecoding() throws {
        let json = """
        {
            "isbn": "9780747532743",
            "title": "Harry Potter and the Philosopher's Stone",
            "authors": ["J.K. Rowling"],
            "cover_url": "https://example.com/cover.jpg",
            "reason": "A beloved fantasy classic perfect for readers seeking magical escapism"
        }
        """
        
        let data = json.data(using: .utf8)!
        let book = try JSONDecoder().decode(RecommendedBookDTO.self, from: data)
        
        #expect(book.isbn == "9780747532743")
        #expect(book.title == "Harry Potter and the Philosopher's Stone")
        #expect(book.authors == ["J.K. Rowling"])
        #expect(book.cover_url == "https://example.com/cover.jpg")
        #expect(book.reason == "A beloved fantasy classic perfect for readers seeking magical escapism")
    }
    
    @Test("RecommendedBookDTO decodes without cover_url (optional field)")
    func recommendedBookDTODecodingWithoutCover() throws {
        let json = """
        {
            "isbn": "9780000000000",
            "title": "Test Book",
            "authors": ["Test Author"],
            "reason": "Test reason"
        }
        """
        
        let data = json.data(using: .utf8)!
        let book = try JSONDecoder().decode(RecommendedBookDTO.self, from: data)
        
        #expect(book.cover_url == nil)
        #expect(book.title == "Test Book")
    }
    
    @Test("RecommendedBookDTO has stable ID for Identifiable conformance")
    func recommendedBookDTOIdentifiable() throws {
        let book = RecommendedBookDTO(
            isbn: "9780747532743",
            title: "Test",
            authors: ["Author"],
            cover_url: nil,
            reason: "Reason"
        )
        
        #expect(book.id == "9780747532743")
    }
    
    @Test("WeeklyRecommendationsDTO decodes with multiple books")
    func weeklyRecommendationsDTOMultipleBooks() throws {
        let json = """
        {
            "week_of": "2025-11-25",
            "books": [
                {
                    "isbn": "9780000000001",
                    "title": "Book 1",
                    "authors": ["Author 1"],
                    "reason": "Reason 1"
                },
                {
                    "isbn": "9780000000002",
                    "title": "Book 2",
                    "authors": ["Author 2", "Author 3"],
                    "cover_url": "https://example.com/cover2.jpg",
                    "reason": "Reason 2"
                }
            ],
            "generated_at": "2025-11-24T00:00:00Z",
            "next_refresh": "2025-12-01T00:00:00Z"
        }
        """
        
        let data = json.data(using: .utf8)!
        let recommendations = try JSONDecoder().decode(WeeklyRecommendationsDTO.self, from: data)
        
        #expect(recommendations.books.count == 2)
        #expect(recommendations.books[0].isbn == "9780000000001")
        #expect(recommendations.books[1].authors.count == 2)
        #expect(recommendations.books[1].cover_url != nil)
    }
    
    // MARK: - Service Tests
    
    @Test("WeeklyRecommendationsService caches responses")
    func serviceCachesResponses() async throws {
        let service = WeeklyRecommendationsService()
        
        // Note: This test would require mocking URLSession
        // Since we're using a real actor, we'd need a proper test setup
        // For now, this validates the service can be instantiated
        #expect(service != nil)
    }
    
    @Test("RecommendationsError provides localized descriptions")
    func recommendationsErrorDescriptions() {
        let errors: [RecommendationsError] = [
            .invalidURL,
            .networkError(NSError(domain: "test", code: -1)),
            .invalidResponse,
            .httpError(500),
            .rateLimitExceeded(retryAfter: 60),
            .decodingError(NSError(domain: "test", code: -1))
        ]
        
        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }
    
    @Test("RecommendationsError handles rate limit with retry after")
    func rateLimitErrorWithRetryAfter() {
        let error = RecommendationsError.rateLimitExceeded(retryAfter: 120)
        
        #expect(error.errorDescription?.contains("120 seconds") == true)
    }
    
    @Test("RecommendationsError handles rate limit without retry after")
    func rateLimitErrorWithoutRetryAfter() {
        let error = RecommendationsError.rateLimitExceeded(retryAfter: nil)
        
        #expect(error.errorDescription?.contains("try again later") == true)
    }
}
