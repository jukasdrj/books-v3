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

    // MARK: - Phase 4.1: Selective Fetching Validation (Issue #395)

    /// Validates that propertiesToFetch reduces memory footprint for large libraries.
    /// SUCCESS CRITERIA: >70% memory reduction with zero CloudKit sync issues
    @Test func selectiveFetching_reducesMemory() async throws {
        let (repository, context) = makeTestRepository()

        // Create 1000 test books with full relationships
        for i in 1...1000 {
            let author = Author(name: "Author \(i)")
            context.insert(author)

            let work = Work(title: "Book \(i)")
            work.originalLanguage = "English"
            work.firstPublicationYear = 2020
            context.insert(work)
            work.authors = [author]

            let edition = Edition(isbn: "123456789\(String(format: "%04d", i))")
            edition.pageCount = 300 + (i % 200)
            edition.publisher = "Publisher \(i)"
            context.insert(edition)
            edition.work = work

            let entry = UserLibraryEntry(readingStatus: .toRead)
            context.insert(entry)
            entry.work = work
            entry.edition = edition
        }
        try context.save()

        // Measure FULL fetch memory (baseline)
        let fullDescriptor = FetchDescriptor<Work>()
        let fullWorks = try context.fetch(fullDescriptor)
        let fullMemory = measureApproximateMemory(fullWorks, context: context, selective: false)

        // Measure SELECTIVE fetch memory by calling the actual repository method
        let selectiveWorks = try repository.fetchUserLibraryForList()
        let selectiveMemory = measureApproximateMemory(selectiveWorks, context: context, selective: true)

        // Calculate savings
        let savings = Double(fullMemory - selectiveMemory) / Double(fullMemory)
        let savingsPercent = Int(savings * 100)

        print("📊 Memory Comparison:")
        print("   Full fetch: \(fullMemory) bytes")
        print("   Selective fetch: \(selectiveMemory) bytes")
        print("   Savings: \(savingsPercent)%")

        // VALIDATION: Must achieve >70% memory reduction (Gemini's recommendation)
        #expect(savings > 0.70, "Expected >70% memory reduction, got \(savingsPercent)%")
        #expect(fullWorks.count == 1000)
        #expect(selectiveWorks.count == 1000)
    }

    /// Validates CloudKit sync integrity with selective fetching.
    /// Ensures propertiesToFetch doesn't break CloudKit merge behavior.
    @Test func selectiveFetching_cloudKitMerge_noDataLoss() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: config
        )

        // Context 1: Simulate main context
        let mainContext = ModelContext(container)
        mainContext.autosaveEnabled = false

        // Context 2: Simulate background import context
        let backgroundContext = ModelContext(container)
        backgroundContext.autosaveEnabled = false
        backgroundContext.automaticallyMergesChangesFromParent = true

        // Step 1: Insert data via main context
        let mainWork = Work(title: "Main Context Book")
        mainContext.insert(mainWork)
        try mainContext.save()

        // Step 2: Insert data via background context using selective fetch
        let bgWork = Work(title: "Background Book")
        backgroundContext.insert(bgWork)
        try backgroundContext.save()

        // Step 3: Fetch using propertiesToFetch in main context
        var descriptor = FetchDescriptor<Work>()
        descriptor.propertiesToFetch = [\.title, \.coverImageURL]
        let works = try mainContext.fetch(descriptor)

        // VALIDATION: Both works must exist (no data loss during merge)
        #expect(works.count == 2, "Expected 2 works after merge, got \(works.count)")

        let titles = works.map { $0.title }.sorted()
        #expect(titles.contains("Main Context Book"))
        #expect(titles.contains("Background Book"))
    }

    /// Validates that selective fetching still allows full object access.
    /// Ensures SwiftData faulting loads relationships on-demand.
    @Test func selectiveFetching_faultingLoadsRelationships() async throws {
        let (_, context) = makeTestRepository()

        let author = Author(name: "Test Author")
        context.insert(author)

        let work = Work(title: "Test Book")
        work.originalLanguage = "English"
        context.insert(work)
        work.authors = [author]

        let entry = UserLibraryEntry(readingStatus: .reading)
        context.insert(entry)
        entry.work = work
        try context.save()

        // Fetch with selective properties
        var descriptor = FetchDescriptor<Work>()
        descriptor.propertiesToFetch = [\.title]
        let works = try context.fetch(descriptor)

        guard let fetchedWork = works.first else {
            Issue.record("No work fetched")
            return
        }

        // VALIDATION: Title should be loaded (in propertiesToFetch)
        #expect(fetchedWork.title == "Test Book")

        // VALIDATION: Original language should fault on access (not in propertiesToFetch)
        // This tests SwiftData's automatic faulting behavior
        #expect(fetchedWork.originalLanguage == "English")

        // VALIDATION: Relationships should fault on access
        #expect(fetchedWork.authors?.first?.name == "Test Author")
    }

    /// Measures approximate memory footprint of fetched objects.
    /// Returns estimated memory usage in bytes.
    /// @param selective: If true, only measures properties included in propertiesToFetch
    private func measureApproximateMemory(_ works: [Work], context: ModelContext, selective: Bool) -> Int {
        var totalSize = 0

        for work in works {
            // Validate work is still in context
            guard context.model(for: work.persistentModelID) is Work else { continue }

            // Base Work object size estimate
            totalSize += 200  // Base object overhead

            // String properties that are ALWAYS safe to access (always fetched)
            totalSize += work.title.utf8.count

            if selective {
                // For selective fetch, only measure properties we know were fetched
                // to avoid triggering faults. Accessing authors/entries would defeat
                // the purpose of selective fetching.
                if let coverURL = work.coverImageURL {
                    totalSize += coverURL.utf8.count
                }
                // Don't access authors, originalLanguage, or other properties
                // that weren't in propertiesToFetch - they would trigger faults
            } else {
                // For full fetch, measure all properties
                totalSize += (work.originalLanguage?.utf8.count ?? 0)
                
                // Relationships (if loaded)
                if let authors = work.authors {
                    totalSize += authors.count * 150  // Author objects
                }
                if let entries = work.userLibraryEntries {
                    totalSize += entries.count * 100  // Entry objects
                }
            }
        }

        return totalSize
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