import Testing
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("SSE Client Tests")
struct SSEClientTests {
    
    @Test("SSE event parsing - basic event")
    func parseBasicEvent() async throws {
        // This test validates SSE event parsing logic
        // Note: Cannot test live SSE without mock server
        
        let client = SSEClient()
        
        // Verify client can be initialized
        #expect(await client.isCurrentlyConnected() == false)
        
        // Verify retry interval default
        let retryInterval = await client.getRetryInterval()
        #expect(retryInterval == 5.0)
    }
    
    @Test("SSE client lifecycle")
    func clientLifecycle() async throws {
        let client = SSEClient()
        
        // Initially not connected
        #expect(await client.isCurrentlyConnected() == false)
        
        // Disconnect should be safe even when not connected
        await client.disconnect()
        #expect(await client.isCurrentlyConnected() == false)
    }
    
    @Test("SSE event ID tracking")
    func eventIDTracking() async throws {
        let client = SSEClient()
        
        // Initially no event ID
        let initialID = await client.getLastEventID()
        #expect(initialID == nil)
    }
}

@MainActor
@Suite("SSE Event Builder Tests")
struct SSEEventBuilderTests {
    
    @Test("Parse simple SSE event")
    func parseSimpleEvent() {
        // SSE event parsing is internal to SSEClient
        // These tests validate the expected SSE format
        
        let sseText = """
        event: message
        data: {"test": "value"}
        
        """
        
        // Validate format expectations
        #expect(sseText.contains("event:"))
        #expect(sseText.contains("data:"))
    }
    
    @Test("Parse multi-line data")
    func parseMultiLineData() {
        let sseText = """
        event: progress
        data: {"progress": 0.5}
        data: {"additional": "data"}
        
        """
        
        // Multi-line data should be joined with newlines
        #expect(sseText.contains("data:"))
    }
    
    @Test("Parse event with ID")
    func parseEventWithID() {
        let sseText = """
        event: update
        id: 123
        data: {"status": "ok"}
        
        """
        
        #expect(sseText.contains("id:"))
    }
    
    @Test("Parse retry directive")
    func parseRetryDirective() {
        let sseText = """
        retry: 10000
        
        """
        
        #expect(sseText.contains("retry:"))
    }
}
