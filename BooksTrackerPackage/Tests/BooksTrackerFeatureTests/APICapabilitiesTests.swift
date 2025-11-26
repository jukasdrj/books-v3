import Testing
import Foundation
@testable import BooksTrackerFeature

/// Tests for APICapabilities model
@Suite("APICapabilities Tests")
struct APICapabilitiesTests {
    
    // MARK: - Decoding Tests
    
    @Test("Decode full capabilities response from backend")
    func testDecodeFullResponse() throws {
        let json = """
        {
          "features": {
            "semantic_search": true,
            "similar_books": true,
            "weekly_recommendations": true,
            "sse_streaming": true,
            "batch_enrichment": true,
            "csv_import": true
          },
          "limits": {
            "semantic_search_rpm": 5,
            "text_search_rpm": 100,
            "csv_max_rows": 500,
            "batch_max_photos": 5
          },
          "infrastructure": {
            "vectorize_available": true,
            "workers_ai_available": true,
            "d1_available": true
          },
          "version": "2.7.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let capabilities = try decoder.decode(APICapabilities.self, from: data)
        
        // Verify features
        #expect(capabilities.features.semanticSearch == true)
        #expect(capabilities.features.similarBooks == true)
        #expect(capabilities.features.weeklyRecommendations == true)
        #expect(capabilities.features.sseStreaming == true)
        #expect(capabilities.features.batchEnrichment == true)
        #expect(capabilities.features.csvImport == true)
        
        // Verify limits
        #expect(capabilities.limits.semanticSearchRpm == 5)
        #expect(capabilities.limits.textSearchRpm == 100)
        #expect(capabilities.limits.csvMaxRows == 500)
        #expect(capabilities.limits.batchMaxPhotos == 5)
        
        // Verify infrastructure
        #expect(capabilities.infrastructure?.vectorizeAvailable == true)
        #expect(capabilities.infrastructure?.workersAiAvailable == true)
        #expect(capabilities.infrastructure?.d1Available == true)
        
        // Verify version
        #expect(capabilities.version == "2.7.0")
    }
    
    @Test("Decode minimal capabilities response (V1 backend)")
    func testDecodeMinimalResponse() throws {
        let json = """
        {
          "features": {
            "semantic_search": false,
            "similar_books": false,
            "weekly_recommendations": false,
            "sse_streaming": false,
            "batch_enrichment": true,
            "csv_import": true
          },
          "limits": {
            "semantic_search_rpm": 0,
            "text_search_rpm": 100,
            "csv_max_rows": 500,
            "batch_max_photos": 5
          },
          "version": "1.0.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let capabilities = try decoder.decode(APICapabilities.self, from: data)
        
        // Verify V1 capabilities (no AI features)
        #expect(capabilities.features.semanticSearch == false)
        #expect(capabilities.features.similarBooks == false)
        #expect(capabilities.features.weeklyRecommendations == false)
        #expect(capabilities.features.sseStreaming == false)
        #expect(capabilities.features.batchEnrichment == true)
        #expect(capabilities.features.csvImport == true)
        
        // Infrastructure is optional
        #expect(capabilities.infrastructure == nil)
        
        #expect(capabilities.version == "1.0.0")
    }
    
    // MARK: - Feature Availability Tests
    
    @Test("Check feature availability for V2 backend")
    func testFeatureAvailabilityV2() {
        let capabilities = APICapabilities(
            features: APICapabilities.Features(
                semanticSearch: true,
                similarBooks: true,
                weeklyRecommendations: true,
                sseStreaming: true,
                batchEnrichment: true,
                csvImport: true
            ),
            limits: APICapabilities.Limits(
                semanticSearchRpm: 5,
                textSearchRpm: 100,
                csvMaxRows: 500,
                batchMaxPhotos: 5
            ),
            infrastructure: nil,
            version: "2.7.0",
            fetchedAt: Date()
        )
        
        #expect(capabilities.isFeatureAvailable(.semanticSearch) == true)
        #expect(capabilities.isFeatureAvailable(.similarBooks) == true)
        #expect(capabilities.isFeatureAvailable(.weeklyRecommendations) == true)
        #expect(capabilities.isFeatureAvailable(.sseStreaming) == true)
        #expect(capabilities.isFeatureAvailable(.batchEnrichment) == true)
        #expect(capabilities.isFeatureAvailable(.csvImport) == true)
    }
    
    @Test("Check feature availability for V1 backend")
    func testFeatureAvailabilityV1() {
        let capabilities = APICapabilities.defaultV1
        
        // V2 features should be unavailable
        #expect(capabilities.isFeatureAvailable(.semanticSearch) == false)
        #expect(capabilities.isFeatureAvailable(.similarBooks) == false)
        #expect(capabilities.isFeatureAvailable(.weeklyRecommendations) == false)
        #expect(capabilities.isFeatureAvailable(.sseStreaming) == false)
        
        // V1 features should be available
        #expect(capabilities.isFeatureAvailable(.batchEnrichment) == true)
        #expect(capabilities.isFeatureAvailable(.csvImport) == true)
    }
    
    // MARK: - Default Capabilities Tests
    
    @Test("Default V1 capabilities have correct values")
    func testDefaultV1Capabilities() {
        let capabilities = APICapabilities.defaultV1
        
        // Features
        #expect(capabilities.features.semanticSearch == false)
        #expect(capabilities.features.batchEnrichment == true)
        #expect(capabilities.features.csvImport == true)
        
        // Limits
        #expect(capabilities.limits.semanticSearchRpm == 0)
        #expect(capabilities.limits.textSearchRpm == 100)
        #expect(capabilities.limits.csvMaxRows == 500)
        #expect(capabilities.limits.batchMaxPhotos == 5)
        
        // Version
        #expect(capabilities.version == "1.0.0")
        
        // Infrastructure should be nil for V1
        #expect(capabilities.infrastructure == nil)
    }
    
    // MARK: - Encoding Tests
    
    @Test("Encode and decode capabilities")
    func testEncodeDecode() throws {
        let original = APICapabilities(
            features: APICapabilities.Features(
                semanticSearch: true,
                similarBooks: false,
                weeklyRecommendations: true,
                sseStreaming: false,
                batchEnrichment: true,
                csvImport: true
            ),
            limits: APICapabilities.Limits(
                semanticSearchRpm: 10,
                textSearchRpm: 200,
                csvMaxRows: 1000,
                batchMaxPhotos: 10
            ),
            infrastructure: APICapabilities.Infrastructure(
                vectorizeAvailable: true,
                workersAiAvailable: false,
                d1Available: true
            ),
            version: "2.8.0",
            fetchedAt: Date()
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(original)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(APICapabilities.self, from: data)
        
        // Verify roundtrip
        #expect(decoded.features.semanticSearch == original.features.semanticSearch)
        #expect(decoded.limits.csvMaxRows == original.limits.csvMaxRows)
        #expect(decoded.infrastructure?.vectorizeAvailable == original.infrastructure?.vectorizeAvailable)
        #expect(decoded.version == original.version)
    }
    
    // MARK: - Snake Case Mapping Tests
    
    @Test("Verify snake_case to camelCase mapping")
    func testSnakeCaseMapping() throws {
        // Ensure backend's snake_case fields map correctly to Swift's camelCase
        let json = """
        {
          "features": {
            "semantic_search": true,
            "similar_books": false,
            "weekly_recommendations": true,
            "sse_streaming": false,
            "batch_enrichment": true,
            "csv_import": false
          },
          "limits": {
            "semantic_search_rpm": 3,
            "text_search_rpm": 50,
            "csv_max_rows": 250,
            "batch_max_photos": 3
          },
          "version": "2.6.0"
        }
        """
        
        let data = json.data(using: .utf8)!
        let capabilities = try JSONDecoder().decode(APICapabilities.self, from: data)
        
        // Verify all snake_case fields were decoded
        #expect(capabilities.features.semanticSearch == true)
        #expect(capabilities.features.similarBooks == false)
        #expect(capabilities.features.weeklyRecommendations == true)
        #expect(capabilities.features.sseStreaming == false)
        #expect(capabilities.limits.semanticSearchRpm == 3)
        #expect(capabilities.limits.textSearchRpm == 50)
        #expect(capabilities.limits.csvMaxRows == 250)
        #expect(capabilities.limits.batchMaxPhotos == 3)
    }
}
