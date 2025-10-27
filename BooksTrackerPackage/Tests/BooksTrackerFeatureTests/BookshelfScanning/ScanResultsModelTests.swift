import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@Suite("ScanResultsModel Tests - SwiftData ID Lifecycle")
@MainActor
struct ScanResultsModelTests {

    // Test infrastructure
    private var container: ModelContainer!
    private var modelContext: ModelContext!

    init() throws {
        // Create in-memory container for testing
        let schema = Schema([Work.self, Edition.self, UserLibraryEntry.self, Author.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: schema, configurations: [config])
        self.modelContext = ModelContext(container)
    }

    @Test("Persistent IDs remain valid after save")
    func testPersistentIDsValidAfterSave() async throws {
        // Arrange: Create a work
        let author = Author(name: "Test Author")
        let work = Work(
            title: "Test Book",
            authors: [author],
            originalLanguage: "English",
            firstPublicationYear: nil
        )

        modelContext.insert(work)

        // Act: Capture ID BEFORE save (current buggy behavior)
        let temporaryID = work.persistentModelID

        // Save to make ID permanent
        try modelContext.save()

        // Try to fetch using the captured ID
        // This should NOT crash - the ID should remain valid
        let fetchedWork = modelContext.model(for: temporaryID) as? Work

        // Assert: Work should be fetchable
        #expect(fetchedWork != nil)
        #expect(fetchedWork?.title == "Test Book")
    }

    @Test("Background task can resolve IDs captured after save")
    func testBackgroundTaskResolvesIDsAfterSave() async throws {
        // Arrange: Create works
        let works = (1...3).map { index in
            let author = Author(name: "Author \(index)")
            let work = Work(
                title: "Book \(index)",
                authors: [author],
                originalLanguage: "English",
                firstPublicationYear: nil
            )
            modelContext.insert(work)
            return work
        }

        // Save first
        try modelContext.save()

        // Act: Capture IDs AFTER save (correct approach)
        let workIDs = works.map { $0.persistentModelID }

        // Simulate background enrichment task
        let backgroundContext = ModelContext(container)

        for workID in workIDs {
            // This simulates what EnrichmentQueue does
            let fetchedWork = backgroundContext.model(for: workID) as? Work

            // Assert: Should not crash, should fetch successfully
            #expect(fetchedWork != nil)
        }
    }
}
