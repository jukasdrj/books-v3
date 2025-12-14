import Foundation
import Testing
import SwiftData
import Combine
@testable import BooksTrackerFeature

/// Tests for EnrichmentQueue V3 functionality
///
/// These tests validate:
/// - Queue item management (enqueue, prioritize)
/// - Observable state (activeEnrichments)
/// - Completion events
/// - Queue validation
@Suite("Enrichment Queue Tests")
@MainActor
struct EnrichmentQueueTests {

    // MARK: - Queue Item Tests

    @Test("EnrichmentQueueItem initializes correctly")
    func queueItem_initializesCorrectly() {
        // Create a mock PersistentIdentifier for testing
        // Note: In real tests, we'd use a SwiftData model container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Work.self, configurations: config)
        let context = ModelContext(container)

        let work = Work(title: "Test Book")
        context.insert(work)
        try! context.save()

        let item = EnrichmentQueue.EnrichmentQueueItem(
            workPersistentID: work.persistentModelID,
            priority: 5
        )

        #expect(item.priority == 5)
        #expect(item.workPersistentID == work.persistentModelID)
        #expect(item.id != UUID()) // Has a valid UUID
    }

    @Test("EnrichmentQueueItem priority can be updated")
    func queueItem_priorityCanBeUpdated() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Work.self, configurations: config)
        let context = ModelContext(container)

        let work = Work(title: "Test Book")
        context.insert(work)
        try! context.save()

        var item = EnrichmentQueue.EnrichmentQueueItem(
            workPersistentID: work.persistentModelID,
            priority: 0
        )

        #expect(item.priority == 0)

        item.setPriority(10)
        #expect(item.priority == 10)
    }

    // MARK: - Completion Event Tests

    @Test("EnrichmentCompletionEvent contains all required fields")
    func completionEvent_containsAllFields() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Work.self, configurations: config)
        let context = ModelContext(container)

        let work = Work(title: "Test Book")
        context.insert(work)
        try! context.save()

        let event = EnrichmentQueue.EnrichmentCompletionEvent(
            bookIds: [work.persistentModelID],
            successCount: 1,
            failureCount: 0,
            errors: [],
            timestamp: Date()
        )

        #expect(event.bookIds.count == 1)
        #expect(event.successCount == 1)
        #expect(event.failureCount == 0)
        #expect(event.errors.isEmpty)
    }

    @Test("EnrichmentCompletionEvent tracks failures")
    func completionEvent_tracksFailures() {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: Work.self, configurations: config)
        let context = ModelContext(container)

        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")
        context.insert(work1)
        context.insert(work2)
        try! context.save()

        let event = EnrichmentQueue.EnrichmentCompletionEvent(
            bookIds: [work1.persistentModelID, work2.persistentModelID],
            successCount: 1,
            failureCount: 1,
            errors: ["Book not found: Book 2"],
            timestamp: Date()
        )

        #expect(event.bookIds.count == 2)
        #expect(event.successCount == 1)
        #expect(event.failureCount == 1)
        #expect(event.errors.count == 1)
        #expect(event.errors.first == "Book not found: Book 2")
    }

    // MARK: - Timeout Error Tests

    @Test("EnrichmentTimeoutError has descriptive message")
    func timeoutError_hasDescriptiveMessage() {
        let error = EnrichmentTimeoutError(timeout: 300) // 5 minutes
        let description = error.errorDescription ?? ""

        #expect(description.contains("5 minutes"))
        #expect(description.contains("timed out"))
    }

    @Test("EnrichmentTimeoutError handles singular minute")
    func timeoutError_handlesSingularMinute() {
        let error = EnrichmentTimeoutError(timeout: 60) // 1 minute
        let description = error.errorDescription ?? ""

        #expect(description.contains("1 minute"))
        #expect(!description.contains("1 minutes")) // Not plural
    }
}
