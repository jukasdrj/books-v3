import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("App Launch Performance")
struct AppLaunchPerformanceTests {

    @Test("Launch metrics tracking")
    func testLaunchMetricsTracking() async throws {
        let metrics = LaunchMetrics.shared

        metrics.recordMilestone("Test milestone 1")
        try await Task.sleep(for: .milliseconds(10))
        metrics.recordMilestone("Test milestone 2")

        let total = metrics.totalLaunchTime()
        #expect(total != nil)
        #expect(total! >= 10) // At least 10ms elapsed
    }

    @Test("ModelContainer creation is fast")
    func testModelContainerCreation() async throws {
        let start = CFAbsoluteTimeGetCurrent()

        let schema = Schema([Work.self, Edition.self, Author.self, UserLibraryEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱️ ModelContainer creation: \(Int(elapsed))ms")
        #expect(elapsed < 200) // Should be < 200ms

        _ = container // Use to avoid warning
    }

    @Test("Lazy ModelContainer initialization")
    func testLazyContainerInit() async throws {
        // Test that container creation can be deferred
        var container: ModelContainer?

        let start = CFAbsoluteTimeGetCurrent()

        // Simulate lazy init
        let schema = Schema([Work.self, Edition.self, Author.self, UserLibraryEntry.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)

        // Container not created yet
        #expect(container == nil)

        // Create on first access
        container = try ModelContainer(for: schema, configurations: [config])

        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        #expect(container != nil)
        print("⏱️ Lazy container init: \(Int(elapsed))ms")
    }

    @MainActor
    @Test("Background task scheduling defers execution")
    func testBackgroundTaskScheduling() async throws {
        var taskExecuted = false

        BackgroundTaskScheduler.shared.schedule {
            taskExecuted = true
        }

        // Task should not execute immediately
        #expect(taskExecuted == false)

        // Wait for deferred execution
        await BackgroundTaskScheduler.shared.waitForCompletion()

        // Now task should be complete
        #expect(taskExecuted == true)
    }

    @Test("Background tasks can be cancelled")
    func testBackgroundTaskCancellation() async throws {
        var taskExecuted = false

        BackgroundTaskScheduler.shared.schedule {
            taskExecuted = true
        }

        // Cancel before execution
        BackgroundTaskScheduler.shared.cancelAll()

        // Wait a bit to ensure task doesn't run
        try await Task.sleep(for: .milliseconds(100))

        #expect(taskExecuted == false)
    }
}
