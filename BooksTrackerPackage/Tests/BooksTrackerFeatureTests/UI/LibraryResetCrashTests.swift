import Testing
import SwiftData
import SwiftUI
@testable import BooksTrackerFeature

@Suite("Library Reset Crash Tests")
@MainActor
struct LibraryResetCrashTests {

    @Test("readingProgressOverview handles deleted works gracefully")
    func testReadingProgressHandlesDeletedWorks() async throws {
        // Setup: Create in-memory container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, UserLibraryEntry.self, Author.self,
            configurations: config
        )
        let context = container.mainContext

        // Create test data
        let work = Work(title: "Test Book")
        work.openLibraryID = "OL123W"
        context.insert(work)

        let entry = UserLibraryEntry(readingStatus: .reading)
        context.insert(entry)

        // Link entry to work (insert-before-relate)
        entry.work = work
        work.userLibraryEntries = [entry]

        try context.save()

        // Verify data exists
        let descriptor = FetchDescriptor<Work>()
        let works = try context.fetch(descriptor)
        #expect(works.count == 1)
        #expect(works.first?.userLibraryEntries?.count == 1)

        // CRITICAL: Simulate library reset - delete all works
        for work in works {
            context.delete(work)
        }
        try context.save()

        // TEST: Access works array after deletion should not crash
        // This simulates what readingProgressOverview does
        let emptyWorks = try context.fetch(descriptor)
        #expect(emptyWorks.isEmpty)

        // Accessing userLibraryEntries on deleted work should not crash
        // (In real scenario, cachedFilteredWorks might still have stale references)
        let staleWork = works.first // Reference to deleted object

        // This should NOT crash - defensive code should handle it
        let entries = staleWork?.userLibraryEntries ?? []
        #expect(entries.isEmpty)
    }

    @Test("readingProgressOverview filters out nil relationships")
    func testReadingProgressFiltersNilRelationships() async throws {
        // Setup container
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, UserLibraryEntry.self, Author.self,
            configurations: config
        )
        let context = container.mainContext

        // Create mix of valid and deleted works
        var allWorks: [Work] = []

        // Valid work with entry
        let validWork = Work(title: "Valid Book")
        validWork.openLibraryID = "OL456W"
        context.insert(validWork)
        let entry = UserLibraryEntry(readingStatus: .read)
        context.insert(entry)

        // Link entry to work (insert-before-relate)
        entry.work = validWork
        validWork.userLibraryEntries = [entry]

        allWorks.append(validWork)

        // Work to be deleted
        let deletedWork = Work(title: "Deleted Book")
        deletedWork.openLibraryID = "OL789W"
        context.insert(deletedWork)
        let deletedEntry = UserLibraryEntry(readingStatus: .read)
        context.insert(deletedEntry)

        // Link entry to work (insert-before-relate)
        deletedEntry.work = deletedWork
        deletedWork.userLibraryEntries = [deletedEntry]

        allWorks.append(deletedWork)

        try context.save()

        // Delete the second work
        context.delete(deletedWork)
        try context.save()

        // TEST: Safely count entries (simulates readingProgressOverview logic)
        let safeCount = allWorks
            .compactMap { $0.userLibraryEntries } // Filter out nil
            .flatMap { $0 }
            .filter { $0.readingStatus == .read }
            .count

        // Should only count the valid work's entry
        #expect(safeCount == 1)
    }
}
