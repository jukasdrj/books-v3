import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("WebSocketProgressManager Tests")
struct WebSocketProgressManagerTests {

    @Test("Should initialize with disconnected state")
    @MainActor
    func testInitialState() async throws {
        let manager = WebSocketProgressManager()

        #expect(!manager.isConnected)
        #expect(manager.lastError == nil)
    }

    @Test("Should handle missing URL gracefully")
    @MainActor
    func testInvalidURL() async throws {
        let manager = WebSocketProgressManager()

        // Empty jobId should fail gracefully
        await manager.connect(jobId: "", progressHandler: { _ in })

        #expect(!manager.isConnected)
        #expect(manager.lastError != nil)
    }

    @Test("Should disconnect cleanly")
    @MainActor
    func testDisconnect() async throws {
        let manager = WebSocketProgressManager()

        // Connect then disconnect
        await manager.connect(jobId: "test-job", progressHandler: { _ in })
        manager.disconnect()

        #expect(!manager.isConnected)
    }

    @Test("ProgressData decodes keepAlive field")
    func testProgressDataDecodesKeepAlive() async throws {
        let json = """
        {
            "type": "progress",
            "jobId": "test-job-123",
            "timestamp": 1729728000000,
            "data": {
                "progress": 0.3,
                "processedItems": 1,
                "totalItems": 3,
                "currentStatus": "Processing with AI...",
                "keepAlive": true
            }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebSocketMessage.self, from: data)

        #expect(message.data.keepAlive == true)
        #expect(message.data.currentStatus == "Processing with AI...")
    }

    @Test("ProgressData handles missing keepAlive field")
    func testProgressDataHandlesMissingKeepAlive() async throws {
        let json = """
        {
            "type": "progress",
            "jobId": "test-job-123",
            "timestamp": 1729728000000,
            "data": {
                "progress": 0.5,
                "processedItems": 2,
                "totalItems": 3,
                "currentStatus": "Enriching books..."
            }
        }
        """

        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let message = try decoder.decode(WebSocketMessage.self, from: data)

        #expect(message.data.keepAlive == nil)
    }
}
