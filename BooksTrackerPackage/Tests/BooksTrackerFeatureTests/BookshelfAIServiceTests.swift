import Testing
import UIKit
@testable import BooksTrackerFeature

// Note: These tests require a running backend. They will be skipped in CI until mock infrastructure is added.

@Test("processViaWebSocket returns detected books on success", .disabled("Requires live backend"))
func testProcessViaWebSocketSuccess() async throws {
    let mockImage = UIImage(systemName: "book")!
    let jobId = UUID().uuidString

    let service = BookshelfAIService.shared

    // Mock successful WebSocket flow
    let result = try await service.processViaWebSocket(
        image: mockImage,
        jobId: jobId,
        provider: .geminiFlash,
        progressHandler: { progress, status in
            print("Progress: \(Int(progress * 100))% - \(status)")
        }
    )

    #expect(result.0.count > 0)  // Has detected books
    #expect(result.1.count >= 0)  // Has suggestions (or empty)
}

@Test("processViaWebSocket throws on WebSocket connection failure", .disabled("Requires live backend"))
func testProcessViaWebSocketConnectionFailure() async {
    let mockImage = UIImage(systemName: "book")!
    let invalidJobId = "invalid-job-id"

    let service = BookshelfAIService.shared

    await #expect(throws: BookshelfAIError.self) {
        try await service.processViaWebSocket(
            image: mockImage,
            jobId: invalidJobId,
            provider: .geminiFlash,
            progressHandler: { _, _ in }
        )
    }
}

@Test("processBookshelfImageWithWebSocket falls back to polling on WebSocket failure", .disabled("Requires live backend with WebSocket disabled"))
func testWebSocketFallbackToPolling() async throws {
    let mockImage = UIImage(systemName: "book")!

    let service = BookshelfAIService.shared

    var strategies: [ProgressStrategy] = []
    var progressUpdates: [(Double, String)] = []

    let result = try await service.processBookshelfImageWithWebSocket(mockImage) { progress, status in
        progressUpdates.append((progress, status))

        // Detect strategy from status message
        if status.contains("WebSocket") || status.contains("real-time") {
            strategies.append(.webSocket)
        } else if status.contains("Polling") || status.contains("fallback") {
            strategies.append(.polling)
        }
    }

    // Should have fallen back to polling
    #expect(strategies.contains(.polling))
    #expect(result.0.count > 0)
}

@Test("processBookshelfImageWithWebSocket uses WebSocket when available", .disabled("Requires live backend"))
func testWebSocketPreferred() async throws {
    let mockImage = UIImage(systemName: "book")!

    let service = BookshelfAIService.shared

    var usedWebSocket = false

    let result = try await service.processBookshelfImageWithWebSocket(mockImage) { progress, status in
        if progress < 1.0 && !status.contains("fallback") {
            usedWebSocket = true
        }
    }

    // WebSocket should be preferred
    #expect(usedWebSocket == true)
    #expect(result.0.count > 0)
}
