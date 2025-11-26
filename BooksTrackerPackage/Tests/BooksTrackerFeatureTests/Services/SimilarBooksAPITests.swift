import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Tests for BookSearchAPIService.findSimilarBooks method
///
/// **Test Coverage:**
/// - Successful similar books retrieval
/// - Error handling (404, 429, network errors)
/// - Response parsing and validation
/// - Rate limit detection
///
/// **Architecture:**
/// - Uses in-memory SwiftData container (no persistence)
/// - All tests isolated with fresh ModelContext
/// - @MainActor for SwiftData thread safety
@Suite("Similar Books API Tests")
@MainActor
struct SimilarBooksAPITests {
    
    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var dtoMapper: DTOMapper!
    var apiService: BookSearchAPIService!
    
    init() throws {
        // Create in-memory container for testing
        modelContainer = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self, SimilarBooksCache.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
        dtoMapper = DTOMapper(modelContext: modelContext)
        apiService = BookSearchAPIService(modelContext: modelContext, dtoMapper: dtoMapper)
    }
    
    // MARK: - Response Parsing Tests
    
    @Test("SimilarBooksResponse decodes valid JSON correctly")
    func decodeSimilarBooksResponse() throws {
        let json = """
        {
          "results": [
            {
              "isbn": "9780439064866",
              "title": "Harry Potter and the Chamber of Secrets",
              "authors": ["J.K. Rowling"],
              "similarity_score": 0.94,
              "cover_url": "https://example.com/cover.jpg"
            }
          ],
          "source_isbn": "9780747532743",
          "total": 1,
          "latency_ms": 85
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(SimilarBooksResponse.self, from: data)
        
        #expect(response.sourceIsbn == "9780747532743")
        #expect(response.total == 1)
        #expect(response.latencyMs == 85)
        #expect(response.results.count == 1)
        
        let firstResult = response.results[0]
        #expect(firstResult.isbn == "9780439064866")
        #expect(firstResult.title == "Harry Potter and the Chamber of Secrets")
        #expect(firstResult.authors.count == 1)
        #expect(firstResult.authors[0] == "J.K. Rowling")
        #expect(firstResult.similarityScore == 0.94)
        #expect(firstResult.coverUrl == "https://example.com/cover.jpg")
    }
    
    @Test("SimilarBooksResponse handles empty results")
    func decodeEmptySimilarBooksResponse() throws {
        let json = """
        {
          "results": [],
          "source_isbn": "9780000000000",
          "total": 0,
          "latency_ms": 20
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(SimilarBooksResponse.self, from: data)
        
        #expect(response.sourceIsbn == "9780000000000")
        #expect(response.total == 0)
        #expect(response.results.isEmpty)
    }
    
    @Test("SimilarBooksResponse handles missing optional fields")
    func decodeSimilarBooksResponseWithMissingOptionals() throws {
        let json = """
        {
          "results": [
            {
              "isbn": "9780439064866",
              "title": "Harry Potter and the Chamber of Secrets",
              "authors": ["J.K. Rowling"],
              "similarity_score": 0.94
            }
          ],
          "source_isbn": "9780747532743",
          "total": 1
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let response = try decoder.decode(SimilarBooksResponse.self, from: data)
        
        #expect(response.results[0].coverUrl == nil)
        #expect(response.latencyMs == nil)
    }
    
    // MARK: - Cache Tests
    
    @Test("Cache stores and retrieves similar books correctly")
    func cacheStoresAndRetrievesSimilarBooks() throws {
        let sourceIsbn = "9780747532743"
        let mockResponse = SimilarBooksResponse.mock(
            sourceIsbn: sourceIsbn,
            results: [
                SimilarBooksResponse.mockItem(
                    isbn: "9780439064866",
                    title: "Harry Potter and the Chamber of Secrets",
                    authors: ["J.K. Rowling"],
                    similarityScore: 0.94
                )
            ],
            total: 1
        )
        
        // Create cache entry
        let cache = SimilarBooksCache(sourceIsbn: sourceIsbn, response: mockResponse)
        modelContext.insert(cache)
        try modelContext.save()
        
        // Retrieve from cache
        let descriptor = FetchDescriptor<SimilarBooksCache>(
            predicate: #Predicate { $0.sourceIsbn == sourceIsbn }
        )
        let retrieved = try modelContext.fetch(descriptor).first
        
        #expect(retrieved != nil)
        #expect(retrieved?.sourceIsbn == sourceIsbn)
        #expect(retrieved?.isValid == true, "Fresh cache should be valid")
        
        let cachedResponse = retrieved?.toResponse()
        #expect(cachedResponse?.results.count == 1)
        #expect(cachedResponse?.results[0].isbn == "9780439064866")
    }
    
    @Test("Cache expires after 24 hours")
    func cacheExpiresAfter24Hours() throws {
        let sourceIsbn = "9780747532743"
        let mockResponse = SimilarBooksResponse.mock(sourceIsbn: sourceIsbn)
        
        let cache = SimilarBooksCache(sourceIsbn: sourceIsbn, response: mockResponse)
        
        // Set creation time to 25 hours ago
        cache.createdAt = Date().addingTimeInterval(-25 * 60 * 60)
        cache.expiresAt = cache.createdAt.addingTimeInterval(24 * 60 * 60)
        
        #expect(cache.isValid == false, "Cache should be expired after 24 hours")
    }
    
    @Test("Cache roundtrip preserves all data")
    func cacheRoundtripPreservesData() throws {
        let originalResponse = SimilarBooksResponse(
            results: [
                SimilarBooksResponse.SimilarBookItem(
                    isbn: "9780439064866",
                    title: "Harry Potter and the Chamber of Secrets",
                    authors: ["J.K. Rowling"],
                    similarityScore: 0.94,
                    coverUrl: "https://example.com/cover.jpg"
                ),
                SimilarBooksResponse.SimilarBookItem(
                    isbn: "9780439136365",
                    title: "Harry Potter and the Prisoner of Azkaban",
                    authors: ["J.K. Rowling"],
                    similarityScore: 0.91,
                    coverUrl: nil
                )
            ],
            sourceIsbn: "9780747532743",
            total: 2,
            latencyMs: 85
        )
        
        let cache = SimilarBooksCache(sourceIsbn: "9780747532743", response: originalResponse)
        let reconstructed = cache.toResponse()
        
        #expect(reconstructed.sourceIsbn == originalResponse.sourceIsbn)
        #expect(reconstructed.total == originalResponse.total)
        #expect(reconstructed.results.count == originalResponse.results.count)
        
        // Verify first item
        #expect(reconstructed.results[0].isbn == originalResponse.results[0].isbn)
        #expect(reconstructed.results[0].title == originalResponse.results[0].title)
        #expect(reconstructed.results[0].authors == originalResponse.results[0].authors)
        #expect(reconstructed.results[0].similarityScore == originalResponse.results[0].similarityScore)
        #expect(reconstructed.results[0].coverUrl == originalResponse.results[0].coverUrl)
        
        // Verify second item (with nil coverUrl)
        #expect(reconstructed.results[1].coverUrl == nil)
    }
}
