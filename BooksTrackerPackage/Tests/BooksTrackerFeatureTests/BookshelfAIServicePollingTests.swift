import Testing
import UIKit
@testable import BooksTrackerFeature

@Test("processViaPolling returns detected books on success", .disabled("Requires live backend"))
func testProcessViaPollingSuccess() async throws {
    let mockImage = UIImage(systemName: "book")!
    let jobId = UUID().uuidString

    let service = BookshelfAIService.shared

    let result = try await service.processViaPolling(
        image: mockImage,
        jobId: jobId,
        provider: .geminiFlash,
        progressHandler: { progress, status in
            print("Polling progress: \(Int(progress * 100))% - \(status)")
        }
    )

    #expect(result.0.count > 0)
    #expect(result.1.count >= 0)
}

@Test("processViaPolling polls every 2 seconds", .disabled("Requires live backend"))
func testProcessViaPollingInterval() async throws {
    let mockImage = UIImage(systemName: "book")!
    let jobId = UUID().uuidString

    let service = BookshelfAIService.shared

    var pollCount = 0
    let startTime = Date()

    _ = try await service.processViaPolling(
        image: mockImage,
        jobId: jobId,
        provider: .geminiFlash,
        progressHandler: { progress, status in
            pollCount += 1
            print("Poll #\(pollCount) at \(Date().timeIntervalSince(startTime))s")
        }
    )

    // Expect at least 10 polls for typical 25-40s processing
    #expect(pollCount >= 10)
}
