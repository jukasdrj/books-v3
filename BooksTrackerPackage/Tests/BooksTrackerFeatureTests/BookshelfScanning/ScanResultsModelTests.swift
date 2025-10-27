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

    @Test("Full bookshelf scan workflow completes without crash")
    func testFullBookshelfScanWorkflow() async throws {
        // Arrange: Create mock scan result
        let detectedBooks = [
            DetectedBook(
                isbn: "9780062073488",
                title: "Murder on the Orient Express",
                author: "Agatha Christie",
                confidence: 0.95,
                boundingBox: CGRect(x: 0, y: 0, width: 0.1, height: 0.3),
                rawText: "Murder on the Orient Express",
                status: .confirmed
            ),
            DetectedBook(
                isbn: "9780141439518",
                title: "Pride and Prejudice",
                author: "Jane Austen",
                confidence: 0.88,
                boundingBox: CGRect(x: 0.1, y: 0, width: 0.1, height: 0.3),
                rawText: "Pride and Prejudice",
                status: .confirmed
            )
        ]

        let scanResult = ScanResult(
            detectedBooks: detectedBooks,
            totalProcessingTime: 2.5
        )

        // Act: Create model and add books to library
        let resultsModel = ScanResultsModel(scanResult: scanResult)
        await resultsModel.addAllToLibrary(modelContext: modelContext)

        // Assert: Works should be saved
        let descriptor = FetchDescriptor<Work>()
        let works = try modelContext.fetch(descriptor)

        #expect(works.count == 2)
        #expect(works.contains { $0.title == "Murder on the Orient Express" })
        #expect(works.contains { $0.title == "Pride and Prejudice" })

        // Assert: Should not crash when enrichment queue processes IDs
        let queuedIDs = EnrichmentQueue.shared.getAllPending()
        #expect(queuedIDs.count == 2)

        // Verify IDs are valid (can be fetched)
        for workID in queuedIDs {
            let fetchedWork = modelContext.model(for: workID) as? Work
            #expect(fetchedWork != nil)
        }
    }
}
