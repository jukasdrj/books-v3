import Testing
import SwiftData
@testable import BooksTrackerFeature

@MainActor
@Suite("EnrichmentQueue Validation")
struct EnrichmentQueueValidationTests {

    @Test("Validation removes invalid persistent IDs")
    func testValidationRemovesInvalidIDs() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        // Create a valid work
        let work = Work(
            title: "Test Book",
            authors: [],
            publicationYear: 2024,
            genres: [],
            isbn: nil,
            olid: nil,
            coverURL: nil
        )
        context.insert(work)
        try context.save()

        let queue = EnrichmentQueue.shared
        queue.clear()

        // Add valid work to queue
        queue.enqueue(workID: work.persistentModelID)
        #expect(queue.count() == 1)

        // Delete the work (simulates invalid ID)
        context.delete(work)
        try context.save()

        // Validate should remove the invalid ID
        queue.validateQueue(in: context)

        #expect(queue.count() == 0)
    }

    @Test("Validation skips on empty queue")
    func testValidationSkipsEmptyQueue() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        let queue = EnrichmentQueue.shared
        queue.clear()

        #expect(queue.count() == 0)

        // Should not crash or throw
        queue.validateQueue(in: context)

        #expect(queue.count() == 0)
    }
}
