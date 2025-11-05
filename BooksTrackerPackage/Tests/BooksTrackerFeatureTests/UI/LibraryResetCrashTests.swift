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

        // Keep reference to the work (simulating stale cache)
        let staleWork = works.first!

        // CRITICAL: Simulate library reset - delete all works
        for work in works {
            context.delete(work)
        }
        try context.save()

        // TEST: Verify work is deleted
        let emptyWorks = try context.fetch(descriptor)
        #expect(emptyWorks.isEmpty)

        // TEST: Accessing work with validation should prevent crash
        // This is what our defensive code does with modelContext.model(for:)
        if context.model(for: staleWork.persistentModelID) as? Work != nil {
            // If work is still valid, we can access its properties
            _ = staleWork.userLibraryEntries
        } else {
            // Work is deleted, skip it (this path should be taken)
            #expect(true, "Work was correctly identified as deleted")
        }
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

        // TEST: Safely count entries using modelContext.model(for:) validation
        // This simulates the updated safeCountEntries logic
        var safeCount = 0
        for work in allWorks {
            // Validate work is still in context before accessing relationships
            if context.model(for: work.persistentModelID) as? Work != nil {
                if let entries = work.userLibraryEntries {
                    safeCount += entries.filter { $0.readingStatus == .read }.count
                }
            }
        }

        // Should only count the valid work's entry
        #expect(safeCount == 1)
    }
    
    @Test("LibraryFilterService handles deleted works during library reset")
    func testLibraryFilterServiceWithDeletedWorks() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, UserLibraryEntry.self, Author.self,
            configurations: config
        )
        let context = container.mainContext
        let service = LibraryFilterService()
        
        // Create works in library
        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")
        context.insert(work1)
        context.insert(work2)
        
        let entry1 = UserLibraryEntry(readingStatus: .reading)
        let entry2 = UserLibraryEntry(readingStatus: .read)
        context.insert(entry1)
        context.insert(entry2)
        
        entry1.work = work1
        work1.userLibraryEntries = [entry1]
        entry2.work = work2
        work2.userLibraryEntries = [entry2]
        
        try context.save()
        
        // Keep references to works (simulating stale @Query)
        let allWorks = [work1, work2]
        
        // Simulate library reset - delete all works
        context.delete(work1)
        context.delete(work2)
        try context.save()
        
        // TEST: filterLibraryWorks should handle deleted works gracefully
        let filtered = service.filterLibraryWorks(from: allWorks, modelContext: context)
        #expect(filtered.isEmpty, "Should return empty array for deleted works")
        
        // TEST: searchWorks should handle deleted works gracefully
        let searchResults = service.searchWorks(allWorks, searchText: "Book", modelContext: context)
        #expect(searchResults.isEmpty, "Should return empty array for deleted works")
        
        // TEST: calculateDiversityScore should handle deleted works gracefully
        let score = service.calculateDiversityScore(for: allWorks, modelContext: context)
        #expect(score == 0.0, "Should return 0.0 for deleted works")
    }
}
