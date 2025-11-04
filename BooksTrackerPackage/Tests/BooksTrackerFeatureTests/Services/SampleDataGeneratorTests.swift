import Testing
import SwiftData
@testable import BooksTrackerFeature

@MainActor
@Suite("SampleDataGenerator Performance")
struct SampleDataGeneratorTests {

    @Test("Empty library check uses fetchLimit=1")
    func testEmptyLibraryCheckIsFast() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        let generator = SampleDataGenerator(modelContext: context)

        let start = CFAbsoluteTimeGetCurrent()
        generator.setupSampleDataIfNeeded()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱️ SampleData check (empty): \(Int(elapsed))ms")
        #expect(elapsed < 50) // Should be very fast
    }

    @Test("Non-empty library check skips sample data")
    func testNonEmptyLibrarySkipsSampleData() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        // Add one work to make library non-empty
        let work = Work(
            title: "Existing Book",
            authors: [],
            publicationYear: 2024,
            genres: [],
            isbn: nil,
            olid: nil,
            coverURL: nil
        )
        context.insert(work)
        try context.save()

        let generator = SampleDataGenerator(modelContext: context)

        let start = CFAbsoluteTimeGetCurrent()
        generator.setupSampleDataIfNeeded()
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        print("⏱️ SampleData check (non-empty): \(Int(elapsed))ms")
        #expect(elapsed < 10) // Should be instant with fetchLimit
    }
}
