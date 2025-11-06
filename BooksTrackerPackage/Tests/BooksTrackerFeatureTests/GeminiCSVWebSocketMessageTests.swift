import Testing
import Foundation
@testable import BooksTrackerFeature

// MARK: - WebSocket Message Decoding Tests

@MainActor
@Suite("Gemini CSV WebSocket Message Tests")
struct GeminiCSVWebSocketMessageTests {
    
    @Test("Decode progress message without books field")
    func decodeProgressMessage() throws {
        // Arrange - This is the actual JSON sent by backend for progress updates
        let json = """
        {
            "type": "progress",
            "jobId": "61df274b-8c8c-4388-9069-2a6e5a8916ab",
            "timestamp": 1762383329601,
            "data": {
                "progress": 0.02,
                "status": "Validating CSV file...",
                "keepAlive": false
            }
        }
        """
        
        let jsonData = json.data(using: .utf8)!
        
        // Act - Decode the message
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebSocketMessage.self, from: jsonData)
        
        // Assert
        #expect(message.type == "progress")
        #expect(message.jobId == "61df274b-8c8c-4388-9069-2a6e5a8916ab")
        #expect(message.data?.progress == 0.02)
        #expect(message.data?.status == "Validating CSV file...")
        #expect(message.data?.keepAlive == false)
        // books field should be nil in progress messages
        #expect(message.data?.books == nil)
    }
    
    @Test("Decode complete message with books field")
    func decodeCompleteMessage() throws {
        // Arrange - This is the actual JSON sent by backend for completion
        let json = """
        {
            "type": "complete",
            "jobId": "61df274b-8c8c-4388-9069-2a6e5a8916ab",
            "timestamp": 1762383329602,
            "data": {
                "books": [
                    {
                        "title": "Test Book",
                        "author": "Test Author",
                        "isbn": "1234567890"
                    }
                ],
                "errors": [],
                "successRate": "1/1",
                "progress": 1.0
            }
        }
        """
        
        let jsonData = json.data(using: .utf8)!
        
        // Act
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebSocketMessage.self, from: jsonData)
        
        // Assert
        #expect(message.type == "complete")
        #expect(message.jobId == "61df274b-8c8c-4388-9069-2a6e5a8916ab")
        #expect(message.data?.books != nil)
        #expect(message.data?.books?.count == 1)
        #expect(message.data?.books?[0].title == "Test Book")
        #expect(message.data?.books?[0].author == "Test Author")
        #expect(message.data?.errors != nil)
        #expect(message.data?.successRate == "1/1")
    }
    
    @Test("Decode error message")
    func decodeErrorMessage() throws {
        // Arrange
        let json = """
        {
            "type": "error",
            "jobId": "61df274b-8c8c-4388-9069-2a6e5a8916ab",
            "timestamp": 1762383329603,
            "data": {
                "error": "Invalid CSV format",
                "fallbackAvailable": true,
                "suggestion": "Try manual CSV import instead"
            }
        }
        """
        
        let jsonData = json.data(using: .utf8)!
        
        // Act
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebSocketMessage.self, from: jsonData)
        
        // Assert
        #expect(message.type == "error")
        #expect(message.data?.error == "Invalid CSV format")
        #expect(message.data?.fallbackAvailable == true)
        #expect(message.data?.suggestion == "Try manual CSV import instead")
    }
    
    @Test("Decode ready_ack message")
    func decodeReadyAckMessage() throws {
        // Arrange
        let json = """
        {
            "type": "ready_ack",
            "timestamp": 1762383329600
        }
        """
        
        let jsonData = json.data(using: .utf8)!
        
        // Act
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebSocketMessage.self, from: jsonData)
        
        // Assert
        #expect(message.type == "ready_ack")
        #expect(message.timestamp == 1762383329600)
        // ready_ack messages have no 'data' field
        #expect(message.data == nil)
    }
}
