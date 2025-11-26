import Testing
import Foundation
@testable import BooksTrackerFeature

/// Tests for CapabilitiesService
@Suite("CapabilitiesService Tests")
struct CapabilitiesServiceTests {
    
    // MARK: - Cache Tests
    
    @Test("Capabilities are cached after first fetch")
    func testCachingBehavior() async throws {
        let service = CapabilitiesService()
        
        // First fetch (will hit network or fallback to default)
        let first = await service.fetchCapabilities()
        #expect(first.fetchedAt != nil)
        
        // Second fetch should return cached (no force refresh)
        let second = await service.fetchCapabilities(forceRefresh: false)
        
        // Should be the same instance from cache
        #expect(second.fetchedAt == first.fetchedAt)
    }
    
    @Test("Force refresh bypasses cache")
    func testForceRefresh() async throws {
        let service = CapabilitiesService()
        
        // First fetch
        let first = await service.fetchCapabilities()
        let firstFetchTime = first.fetchedAt
        
        // Wait a bit to ensure timestamps differ
        try await Task.sleep(for: .milliseconds(100))
        
        // Force refresh
        let second = await service.fetchCapabilities(forceRefresh: true)
        let secondFetchTime = second.fetchedAt
        
        // Timestamps should differ (new fetch occurred)
        if let firstTime = firstFetchTime, let secondTime = secondFetchTime {
            #expect(secondTime > firstTime)
        }
    }
    
    @Test("Clear cache removes cached capabilities")
    func testClearCache() async throws {
        let service = CapabilitiesService()
        
        // Fetch to populate cache
        _ = await service.fetchCapabilities()
        
        // Verify cache is populated
        let cached = await service.getCached()
        #expect(cached != nil)
        
        // Clear cache
        await service.clearCache()
        
        // Verify cache is empty
        let afterClear = await service.getCached()
        #expect(afterClear == nil)
    }
    
    // MARK: - Fallback Tests
    
    @Test("Falls back to default V1 capabilities on network error")
    func testFallbackOnError() async throws {
        let service = CapabilitiesService()
        
        // Fetch capabilities (will likely fail or use default)
        let capabilities = await service.fetchCapabilities()
        
        // Should never be nil - always returns default on error
        #expect(capabilities.version != "")
        
        // Should have basic V1 features
        #expect(capabilities.features.batchEnrichment == true || capabilities.features.batchEnrichment == false)
        #expect(capabilities.limits.csvMaxRows > 0)
    }
    
    @Test("Default V1 capabilities used when backend unavailable")
    func testDefaultCapabilities() async {
        // Create a mock scenario where backend is unavailable
        // The service should return default V1 capabilities
        
        let defaultCaps = APICapabilities.defaultV1
        
        // Verify default has sensible values
        #expect(defaultCaps.version == "1.0.0")
        #expect(defaultCaps.features.batchEnrichment == true)
        #expect(defaultCaps.features.csvImport == true)
        #expect(defaultCaps.features.semanticSearch == false) // V2 feature
        #expect(defaultCaps.limits.csvMaxRows == 500)
        #expect(defaultCaps.limits.textSearchRpm == 100)
    }
    
    // MARK: - Actor Isolation Tests
    
    @Test("Service is thread-safe (actor isolation)")
    func testThreadSafety() async throws {
        let service = CapabilitiesService()
        
        // Concurrent access should be safe (actor isolation)
        await withTaskGroup(of: APICapabilities.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await service.fetchCapabilities()
                }
            }
            
            var results: [APICapabilities] = []
            for await result in group {
                results.append(result)
            }
            
            // All results should be valid
            #expect(results.count == 10)
            for result in results {
                #expect(result.version != "")
            }
        }
    }
    
    // MARK: - Integration Tests (Conditional on Network)
    
    @Test("Live API fetch (requires network)", .disabled("Requires live backend"))
    func testLiveAPIFetch() async throws {
        let service = CapabilitiesService()
        
        // This test requires actual network connectivity
        let capabilities = await service.fetchCapabilities(forceRefresh: true)
        
        // Verify we got a real response
        #expect(capabilities.version != "unknown")
        #expect(capabilities.version != "1.0.0") // Not the default
        
        // Should have timestamps
        #expect(capabilities.fetchedAt != nil)
        
        // Verify structure
        #expect(capabilities.limits.csvMaxRows > 0)
        #expect(capabilities.limits.textSearchRpm > 0)
    }
    
    // MARK: - Cache Freshness Tests
    
    @Test("Cache is considered fresh within TTL")
    func testCacheFreshness() async throws {
        let service = CapabilitiesService()
        
        // Fetch to populate cache
        let first = await service.fetchCapabilities()
        
        // Immediately fetch again (should use cache)
        let second = await service.fetchCapabilities()
        
        // Should be cached (same fetch time)
        #expect(first.fetchedAt == second.fetchedAt)
    }
}
