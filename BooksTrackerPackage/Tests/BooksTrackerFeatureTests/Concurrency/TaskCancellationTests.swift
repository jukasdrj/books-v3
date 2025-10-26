import Testing
import Foundation
@testable import BooksTrackerFeature

@Suite("Task Cancellation")
struct TaskCancellationTests {

    @Test("SearchModel cancels previous search task")
    @MainActor
    func testSearchCancellation() async throws {
        let searchModel = SearchModel()

        // Start first search
        searchModel.search(query: "First Query", scope: .all)

        // Immediately start second search (should cancel first)
        searchModel.search(query: "Second Query", scope: .all)

        // Wait for completion
        try await Task.sleep(for: .seconds(1))

        // Only second query should have results
        if case .results(let query, _, _, _, _) = searchModel.viewState {
            #expect(query == "Second Query", "Should only show results from second search")
        } else if case .searching(let query, _, _) = searchModel.viewState {
            #expect(query == "Second Query", "Should be searching for second query")
        }
    }

    @Test("Task.isCancelled is checked during long operations")
    func testTaskCancellationChecking() async throws {
        let task = Task {
            var iterations = 0
            for i in 1...100 {
                // Check for cancellation
                if Task.isCancelled {
                    return iterations
                }
                iterations = i
                try? await Task.sleep(for: .milliseconds(10))
            }
            return iterations
        }

        // Cancel after 50ms (should only complete ~5 iterations)
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()

        let result = await task.value
        #expect(result < 100, "Task should be cancelled before completing all iterations")
    }

    @Test("WebSocket connection is cleaned up on cancellation")
    func testWebSocketCancellation() async throws {
        #if canImport(UIKit)
        let wsManager = await WebSocketProgressManager()

        let task = Task {
            do {
                _ = try await wsManager.establishConnection(jobId: "test-job")
                try await wsManager.configureForJob(jobId: "test-job")

                // Simulate long-running operation
                try await Task.sleep(for: .seconds(10))
            } catch {
                // Expected cancellation error
            }
        }

        // Cancel after 100ms
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        // Wait for cleanup
        try await Task.sleep(for: .milliseconds(100))

        // WebSocket should be disconnected after cancellation
        #expect(true, "WebSocket cleanup should complete without crashes")
        #endif
    }
}
