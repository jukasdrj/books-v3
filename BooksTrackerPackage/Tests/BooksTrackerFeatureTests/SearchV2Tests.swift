//
//  SearchV2Tests.swift
//  BooksTrackerFeatureTests
//
//  Tests for V2 Unified Search API integration
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("V2 Search API Tests")
struct SearchV2Tests {
    
    @Test("SearchMode enum has correct properties")
    func testSearchModeProperties() {
        #expect(SearchMode.text.rawValue == "text")
        #expect(SearchMode.semantic.rawValue == "semantic")
        #expect(SearchMode.text.rateLimitPerMinute == 100)
        #expect(SearchMode.semantic.rateLimitPerMinute == 5)
    }
    
    @Test("SearchMode display names are user-friendly")
    func testSearchModeDisplayNames() {
        #expect(SearchMode.text.displayName == "Text")
        #expect(SearchMode.semantic.displayName == "AI Search")
        #expect(SearchMode.text.accessibilityLabel.contains("keyword"))
        #expect(SearchMode.semantic.accessibilityLabel.contains("AI"))
    }
    
    @Test("V2 Response DTO decodes correctly")
    func testV2ResponseDecoding() throws {
        let json = """
        {
          "results": [
            {
              "id": "book_abc123",
              "isbn": "9780747532743",
              "title": "Harry Potter",
              "authors": ["J.K. Rowling"],
              "cover_url": "https://example.com/cover.jpg",
              "relevance_score": 0.95,
              "match_type": "semantic"
            }
          ],
          "total": 1,
          "mode": "semantic",
          "query": "wizard books",
          "latency_ms": 120
        }
        """
        
        let data = json.data(using: .utf8)!
        let response = try JSONDecoder().decode(SearchV2Response.self, from: data)
        
        #expect(response.results.count == 1)
        #expect(response.total == 1)
        #expect(response.mode == "semantic")
        #expect(response.query == "wizard books")
        #expect(response.latencyMs == 120)
        
        let result = response.results[0]
        #expect(result.isbn == "9780747532743")
        #expect(result.title == "Harry Potter")
        #expect(result.authors.count == 1)
        #expect(result.authors[0] == "J.K. Rowling")
        #expect(result.relevanceScore == 0.95)
        #expect(result.matchType == "semantic")
    }
    
    @Test("V2 Error response decodes correctly")
    func testV2ErrorDecoding() throws {
        let json = """
        {
          "error": {
            "code": "INVALID_QUERY",
            "message": "Query must be at least 2 characters"
          }
        }
        """
        
        let data = json.data(using: .utf8)!
        let errorResponse = try JSONDecoder().decode(SearchV2ErrorResponse.self, from: data)
        
        #expect(errorResponse.error.code == "INVALID_QUERY")
        #expect(errorResponse.error.message.contains("2 characters"))
    }
}

@Suite("Semantic Search Rate Limiting")
@MainActor
struct SemanticSearchRateLimitTests {
    
    @Test("Rate limit tracking starts with full quota")
    @MainActor
    func testInitialRateLimit() async {
        let modelContext = createTestModelContext()
        let dtoMapper = DTOMapper(modelContext: modelContext)
        let searchModel = SearchModel(modelContext: modelContext, dtoMapper: dtoMapper)
        
        #expect(searchModel.remainingSemanticSearches == 5)
        #expect(searchModel.isSemanticSearchRateLimited == false)
        #expect(searchModel.secondsUntilSemanticSearchAvailable == 0)
    }
    
    @Test("SearchModel starts with text mode by default")
    @MainActor
    func testDefaultSearchMode() async {
        let modelContext = createTestModelContext()
        let dtoMapper = DTOMapper(modelContext: modelContext)
        let searchModel = SearchModel(modelContext: modelContext, dtoMapper: dtoMapper)
        
        #expect(searchModel.searchMode == .text)
    }
}

@MainActor
private func createTestModelContext() -> ModelContext {
    let container = try! ModelContainer(
        for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return container.mainContext
}
