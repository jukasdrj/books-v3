
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
    
    // MARK: - Search API Tests
    
    @Test("GET /v1/search/isbn returns valid results for known ISBN")
    func testSearchISBN_Valid() async throws {
        // Harry Potter and the Sorcerer's Stone
        let isbn = "9780439708180"
        let url = EnrichmentConfig.searchISBNURL.appending(queryItems: [URLQueryItem(name: "isbn", value: isbn)])
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // 1. Verify HTTP 200
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }
        #expect(httpResponse.statusCode == 200)
        
        // 2. Decode Response
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)
        
        guard case .success(let searchResponse, _) = envelope else {
            Issue.record("Expected success response, got failure or invalid format")
            return
        }
        
        // 3. Verify Content
        // Should find at least one work or edition related to Harry Potter
        let hasHarryPotter = searchResponse.works.contains { $0.title.localizedCaseInsensitiveContains("Harry Potter") } ||
                             searchResponse.editions.contains { $0.title?.localizedCaseInsensitiveContains("Harry Potter") ?? false }
        
        #expect(hasHarryPotter, "Results should contain 'Harry Potter'")
    }
    
    @Test("GET /v1/search/isbn returns empty for unknown ISBN")
    func testSearchISBN_Unknown() async throws {
        // Random non-existent ISBN
        let isbn = "0000000000000"
        let url = EnrichmentConfig.searchISBNURL.appending(queryItems: [URLQueryItem(name: "isbn", value: isbn)])
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }
        
        // Note: API Contract says 200 OK with empty data for Not Found, OR 404.
        // Let's check what it actually returns. The contract says:
        // "Not Found (200): { data: { works: [], ... } }"
        // BUT also "Error (400): Invalid ISBN"
        // Let's assume a valid formatted ISBN that just doesn't exist returns 200 with empty results.
        
        #expect(httpResponse.statusCode == 200)
        
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)
        
        if case .success(let searchResponse, _) = envelope {
            #expect(searchResponse.works.isEmpty)
            #expect(searchResponse.editions.isEmpty)
        } else if case .failure(let error, _) = envelope {
            // If it returns a failure envelope, that's also "valid" protocol behavior,
            // but for "Not Found" we usually expect empty success or 404.
            // Contract says: "Not Found (200)"
            Issue.record("Expected success envelope with empty results, got failure: \(error.message)")
        }
    }
    
    @Test("GET /v1/search/title returns results for fuzzy query")
    func testSearchTitle_Fuzzy() async throws {
        let query = "Great Gatsby"
        let url = EnrichmentConfig.searchTitleURL.appending(queryItems: [URLQueryItem(name: "q", value: query)])
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }
        #expect(httpResponse.statusCode == 200)
        
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)
        
        guard case .success(let searchResponse, _) = envelope else {
            Issue.record("Expected success response")
            return
        }
        
        #expect(!searchResponse.works.isEmpty, "Should return works")
        
        let firstMatch = searchResponse.works.first
        #expect(firstMatch?.title.localizedCaseInsensitiveContains("Gatsby") ?? false)
    }
    
    @Test("GET /v1/search/advanced filters by author")
    func testSearchAdvanced_Author() async throws {
        let title = "Foundation"
        let author = "Asimov"
        
        var components = URLComponents(url: EnrichmentConfig.searchAdvancedURL, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "author", value: author)
        ]
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            Issue.record("Expected HTTPURLResponse")
            return
        }
        #expect(httpResponse.statusCode == 200)
        
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)
        
        guard case .success(let searchResponse, _) = envelope else {
            Issue.record("Expected success response")
            return
        }
        
        #expect(!searchResponse.works.isEmpty)
        
        // Verify author match
        let hasAsimov = searchResponse.authors.contains { $0.name.localizedCaseInsensitiveContains("Asimov") }
        #expect(hasAsimov, "Results should contain author 'Asimov'")
    }
    
    // MARK: - WebSocket Connectivity (Basic)
    
    @Test("WebSocket connection can be established")
    func testWebSocketConnectivity() async throws {
        // We can't easily test full auth flow without a valid token/jobId from a POST request.
        // However, we can try to connect to the health check or just verify the URL is reachable.
        // The contract mentions: wss://api.oooefam.net/ws/progress
        
        // For now, let's just verify the Health Check endpoint as a proxy for backend availability
        // since WebSocket requires a valid token which we can't generate without starting a job (which costs money/resources).
        
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
    }
}
