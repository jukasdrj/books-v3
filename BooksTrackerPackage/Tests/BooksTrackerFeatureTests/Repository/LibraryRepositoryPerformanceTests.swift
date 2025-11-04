import Testing
import SwiftData
@testable import BooksTrackerFeature

@MainActor
struct LibraryRepositoryPerformanceTests {

    @Test func totalBooksCount_performance_1000books() async throws {
        let (repository, context) = makeTestRepository()

        // Create 1000 test books
        // CRITICAL: SwiftData requires insert-before-relate pattern
        // See CLAUDE.md "Insert-Before-Relate Lifecycle" section
        for i in 1...1000 {
            let work = Work(title: "Book \(i)")
            context.insert(work)
            let entry = UserLibraryEntry(readingStatus: .toRead)
            context.insert(entry)
            entry.work = work
        }

        // Measure performance
        let startTime = ContinuousClock.now
        let count = try repository.totalBooksCount()
        let elapsed = ContinuousClock.now - startTime

        #expect(count == 1000)
        #expect(elapsed < .milliseconds(10))  // Must be <10ms for 1000 books
    }

    @Test func reviewQueueCount_performance() async throws {
        let (repository, context) = makeTestRepository()

        // Create 500 books, 100 need review
        for i in 1...500 {
            let work = Work(title: "Book \(i)")
            work.reviewStatus = (i <= 100) ? .needsReview : .verified
            context.insert(work)
        }

        let startTime = ContinuousClock.now
        let count = try repository.reviewQueueCount()
        let elapsed = ContinuousClock.now - startTime

        #expect(count == 100)
        #expect(elapsed < .milliseconds(20))  // Must be <20ms for in-memory filtering
    }

    @Test func fetchByReadingStatus_performance() async throws {
        let (repository, context) = makeTestRepository()

        // Create 1000 books with mixed statuses
        for i in 1...1000 {
            let work = Work(title: "Book \(i)")
            context.insert(work)
            let status: ReadingStatus = (i % 4 == 0) ? .reading : .toRead
            let entry = UserLibraryEntry(readingStatus: status)
            context.insert(entry)
            entry.work = work
        }

        let startTime = ContinuousClock.now
        let reading = try repository.fetchByReadingStatus(.reading)
        let elapsed = ContinuousClock.now - startTime

        #expect(reading.count == 250)
        #expect(elapsed < .milliseconds(20))  // Must be <20ms
    }

    private func makeTestRepository() -> (LibraryRepository, ModelContext) {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = ModelContext(container)
        let repository = LibraryRepository(modelContext: context)
        return (repository, context)
    }
}
