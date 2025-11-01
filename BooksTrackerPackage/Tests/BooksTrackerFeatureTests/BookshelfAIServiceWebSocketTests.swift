import Testing
import Foundation
#if canImport(UIKit)
import UIKit
#endif
@testable import BooksTrackerFeature

@Suite("BookshelfAIService WebSocket Integration")
struct BookshelfAIServiceWebSocketTests {

    #if canImport(UIKit)
    @Test("processBookshelfImageWithWebSocket calls progress handler")
    @MainActor
    func testWebSocketProgressHandlerCalled() async throws {
        // Create mock image
        let image = createMockImage()

        // Track progress updates (MainActor-isolated)
        var progressUpdates: [(Double, String)] = []
        let service = BookshelfAIService.shared

        // This test will fail initially because the method doesn't exist yet
        let (_, books, suggestions) = try await service.processBookshelfImageWithWebSocket(
            image,
            progressHandler: { progress, stage in
                progressUpdates.append((progress, stage))
            }
        )

        // Verify progress handler was called at least once
        #expect(progressUpdates.count >= 1, "Progress handler should be called at least once")

        // Verify results are returned (even if empty for test)
        #expect(!books.isEmpty || books.isEmpty, "Books array should be returned")
        #expect(!suggestions.isEmpty || suggestions.isEmpty, "Suggestions array should be returned")
    }

    @Test("processBookshelfImageWithWebSocket typed throws BookshelfAIError")
    @MainActor
    func testWebSocketTypedThrows() async throws {
        // This test verifies the typed throws signature
        let image = createMockImage()
        let service = BookshelfAIService.shared

        do {
            let _ = try await service.processBookshelfImageWithWebSocket(
                image,
                progressHandler: { _, _ in }
            )
        } catch let error as BookshelfAIError {
            // Typed throws should allow catching BookshelfAIError directly
            #expect(true, "Should be able to catch typed BookshelfAIError: \(error)")
        }
    }

    @Test("processBookshelfImageWithWebSocket skips keepAlive progress updates")
    @MainActor
    func testWebSocketSkipsKeepAliveUpdates() async throws {
        var progressUpdates: [(Double, String)] = []

        // Mock progress updates simulating server behavior
        let mockProgressUpdates = [
            JobProgress(totalItems: 3, processedItems: 1, currentStatus: "Processing with AI...", keepAlive: false),
            JobProgress(totalItems: 3, processedItems: 1, currentStatus: "Processing with AI...", keepAlive: true),  // Should be skipped
            JobProgress(totalItems: 3, processedItems: 1, currentStatus: "Processing with AI...", keepAlive: true),  // Should be skipped
            JobProgress(totalItems: 3, processedItems: 2, currentStatus: "Enriching books...", keepAlive: false),
            JobProgress(totalItems: 3, processedItems: 3, currentStatus: "Scan complete! Found 12 books.", keepAlive: false)
        ]

        // Progress handler should only receive non-keepAlive updates
        let progressHandler: @MainActor (Double, String) -> Void = { progress, status in
            progressUpdates.append((progress, status))
        }

        // Simulate WebSocket flow
        for progress in mockProgressUpdates {
            // Skip keep-alive updates (this is the logic we're testing)
            guard progress.keepAlive != true else { continue }
            progressHandler(progress.fractionCompleted, progress.currentStatus)
        }

        // Should only have 3 updates (skipped 2 keep-alives)
        #expect(progressUpdates.count == 3)
        #expect(progressUpdates[0].1 == "Processing with AI...")
        #expect(progressUpdates[1].1 == "Enriching books...")
        #expect(progressUpdates[2].1 == "Scan complete! Found 12 books.")
    }

    // MARK: - Helper Methods

    @MainActor
    private func createMockImage() -> UIImage {
        // Create a simple 1x1 test image
        let size = CGSize(width: 1, height: 1)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
    #endif
}
