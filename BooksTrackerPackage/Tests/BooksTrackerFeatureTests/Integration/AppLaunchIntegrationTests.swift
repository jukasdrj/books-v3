import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("App Launch Integration Tests")
struct AppLaunchIntegrationTests {

    @Test("Complete launch sequence completes in target time")
    func testCompleteLaunchSequence() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        let startTime = CFAbsoluteTimeGetCurrent()

        // Simulate app launch sequence
        LaunchMetrics.shared.recordMilestone("Integration test start")

        // 1. Lazy properties accessed
        let dtoMapper = DTOMapper(modelContext: context)
        LaunchMetrics.shared.recordMilestone("DTOMapper created")

        let libraryRepo = LibraryRepository(modelContext: context)
        LaunchMetrics.shared.recordMilestone("LibraryRepository created")

        // 2. Background tasks scheduled (not blocking)
        BackgroundTaskScheduler.shared.schedule {
            EnrichmentQueue.shared.validateQueue(in: context)
        }

        BackgroundTaskScheduler.shared.schedule {
            await ImageCleanupService.shared.cleanupReviewedImages(in: context)
        }

        BackgroundTaskScheduler.shared.schedule {
            SampleDataGenerator(modelContext: context).setupSampleDataIfNeeded()
        }

        LaunchMetrics.shared.recordMilestone("Background tasks scheduled")

        // Calculate time to interactive (before background tasks run)
        let timeToInteractive = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        print("⏱️ Time to interactive: \(Int(timeToInteractive))ms")

        // Validate target: <1200ms to interactive
        #expect(timeToInteractive < 1200)

        // Wait for background tasks to complete
        await BackgroundTaskScheduler.shared.waitForCompletion()

        let totalTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        print("⏱️ Total with background: \(Int(totalTime))ms")

        _ = dtoMapper
        _ = libraryRepo
    }

    @Test("Launch with existing library (no sample data)")
    func testLaunchWithExistingLibrary() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        // Add existing work
        let work = Work(title: "Existing Book")
        context.insert(work)
        try context.save()

        let startTime = CFAbsoluteTimeGetCurrent()

        // Sample data should skip
        let generator = SampleDataGenerator(modelContext: context)
        generator.setupSampleDataIfNeeded()

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        print("⏱️ SampleData check with existing library: \(Int(elapsed))ms")
        #expect(elapsed < 10) // Should be instant
    }

    @Test("Launch with empty enrichment queue")
    func testLaunchWithEmptyQueue() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        EnrichmentQueue.shared.clear()

        let startTime = CFAbsoluteTimeGetCurrent()

        // Validation should exit early
        EnrichmentQueue.shared.validateQueue(in: context)

        let elapsed = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        print("⏱️ EnrichmentQueue validation (empty): \(Int(elapsed))ms")
        #expect(elapsed < 10) // Should be instant
    }
}
