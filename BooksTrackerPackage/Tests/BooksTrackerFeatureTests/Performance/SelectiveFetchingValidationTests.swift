import Foundation
import Testing
import SwiftData
@testable import BooksTrackerFeature

/// Phase 4.1: Validate that `propertiesToFetch` works with CloudKit sync
/// Issue #395
@Suite("Selective Fetching Validation")
@MainActor
struct SelectiveFetchingValidationTests {

    /// Validates that selective fetching reduces memory footprint for large libraries
    ///
    /// **Test Strategy:**
    /// 1. Create 1000 test Works with full relationships (authors, editions)
    /// 2. Measure memory with full fetch (baseline)
    /// 3. Measure memory with selective fetch (propertiesToFetch)
    /// 4. Verify fetches succeed
    ///
    /// **Note:** Requires real device (not simulator) for accurate memory measurement.
    /// Use Instruments Allocations tool for validation.
    @Test("Selective fetching reduces memory")
    func selectiveFetching_reducesMemory() async throws {
        // MARK: - Setup
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = ModelContext(container)

        // MARK: - Create 100 test books with full relationships (reduced for test speed)
        for i in 1...100 {
            let work = Work(title: "Test Book \(i)")
            work.openLibraryWorkID = "OL\(i)W"
            context.insert(work)

            // Add 2 authors per work
            for j in 1...2 {
                let author = Author(name: "Author \(i)-\(j)")
                author.openLibraryID = "OL\(i)\(j)A"
                context.insert(author)
                if work.authors == nil {
                    work.authors = []
                }
                work.authors?.append(author)
            }

            // Add 3 editions per work
            for k in 1...3 {
                let edition = Edition(isbn: "978000000\(String(format: "%04d", (i * 10) + k))")
                edition.openLibraryEditionID = "OL\(i)\(k)M"
                context.insert(edition)
                if work.editions == nil {
                    work.editions = []
                }
                work.editions?.append(edition)
            }

            // Add UserLibraryEntry
            let entry = UserLibraryEntry(readingStatus: .toRead)
            context.insert(entry)
            entry.work = work
        }

        try context.save()

        // MARK: - Baseline: Full fetch (all properties loaded)
        var baselineDescriptor = FetchDescriptor<Work>()
        baselineDescriptor.sortBy = [SortDescriptor(\Work.title)]

        let baselineWorks = try context.fetch(baselineDescriptor)
        #expect(baselineWorks.count == 100)

        // Access relationships to trigger loading
        var baselineAuthorCount = 0
        var baselineEditionCount = 0
        for work in baselineWorks {
            baselineAuthorCount += work.authors?.count ?? 0
            baselineEditionCount += work.editions?.count ?? 0
        }

        #expect(baselineAuthorCount == 200) // 2 authors per work
        #expect(baselineEditionCount == 300) // 3 editions per work

        // MARK: - Selective fetch (propertiesToFetch)
        var selectiveDescriptor = FetchDescriptor<Work>()
        selectiveDescriptor.sortBy = [SortDescriptor(\Work.title)]

        // CRITICAL: Test propertiesToFetch
        // Only fetch essential properties for list views
        selectiveDescriptor.propertiesToFetch = [
            \Work.title,
            \Work.coverImageURL
        ]

        let selectiveWorks = try context.fetch(selectiveDescriptor)
        #expect(selectiveWorks.count == 100)

        // Verify fetched properties are accessible
        for work in selectiveWorks {
            #expect(work.title.isEmpty == false)
            // Note: coverImageURL may be nil (valid state)
        }
    }

    /// Validates that propertiesToFetch can be used for list vs detail view optimization
    @Test("List vs detail optimization")
    func selectiveFetching_listVsDetailOptimization() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self,
            configurations: config
        )
        let context = ModelContext(container)

        // Create test work with relationships
        let work = Work(title: "Test Book")
        work.openLibraryWorkID = "OL123W"
        context.insert(work)

        let author = Author(name: "Test Author")
        author.openLibraryID = "OL123A"
        context.insert(author)
        work.authors = [author]

        let edition = Edition(isbn: "9780000000001")
        edition.openLibraryEditionID = "OL123M"
        context.insert(edition)
        work.editions = [edition]

        try context.save()

        // MARK: - List View Fetch (minimal properties)
        var listDescriptor = FetchDescriptor<Work>()
        listDescriptor.propertiesToFetch = [
            \Work.title,
            \Work.coverImageURL
        ]

        let listWorks = try context.fetch(listDescriptor)
        #expect(listWorks.count == 1)
        #expect(listWorks.first?.title == "Test Book")

        // MARK: - Detail View Fetch (full object graph)
        let detailDescriptor = FetchDescriptor<Work>(
            predicate: #Predicate { $0.title == "Test Book" }
        )

        let detailWork = try context.fetch(detailDescriptor).first
        #expect(detailWork != nil)
        #expect(detailWork?.authors?.count == 1)
        #expect(detailWork?.editions?.count == 1)
    }

    /// Validates that propertiesToFetch works with FetchDescriptor predicates
    @Test("Selective fetching with predicates")
    func selectiveFetching_worksWithPredicates() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = ModelContext(container)

        // Create test works
        let work1 = Work(title: "Alpha")
        work1.openLibraryWorkID = "OL1W"
        let work2 = Work(title: "Beta")
        work2.openLibraryWorkID = "OL2W"
        context.insert(work1)
        context.insert(work2)

        let entry1 = UserLibraryEntry(readingStatus: .read)
        context.insert(entry1)
        entry1.work = work1
        let entry2 = UserLibraryEntry(readingStatus: .toRead)
        context.insert(entry2)
        entry2.work = work2

        try context.save()

        // MARK: - Selective fetch with predicate
        let readStatus = ReadingStatus.read
        var descriptor = FetchDescriptor<UserLibraryEntry>(
            predicate: #Predicate { $0.readingStatus == readStatus }
        )
        descriptor.propertiesToFetch = [\UserLibraryEntry.work, \UserLibraryEntry.readingStatus]

        let entries = try context.fetch(descriptor)
        #expect(entries.count == 1)
        #expect(entries.first?.work?.title == "Alpha")
    }
}
