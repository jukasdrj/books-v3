import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

@MainActor
@Suite("ReadingStats Tests")
struct ReadingStatsTests {

    @Test("Calculate pages read in time period")
    func testPagesReadInTimePeriod() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, configurations: config)
        let context = container.mainContext

        // Create test data
        let work = Work(title: "Test Book")
        let edition = Edition(pageCount: 300)

        context.insert(work)
        context.insert(edition)

        // Link edition to work (insert-before-relate)
        edition.work = work

        let entry1 = UserLibraryEntry.createOwnedEntry(for: work, edition: edition, status: .read, context: context)
        entry1.dateCompleted = Date() // Today (within "Last 30 Days")
        entry1.currentPage = 300

        // Note: Factory already inserted entry - no manual insert needed
        try context.save()

        // Calculate stats for "Last 30 Days"
        let stats = try ReadingStats.calculate(from: context, period: .last30Days)

        #expect(stats.pagesRead == 300)
        #expect(stats.booksCompleted == 1)
    }

    @Test("Calculate reading pace")
    func testReadingPace() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Work.self, Edition.self, UserLibraryEntry.self, configurations: config)
        let context = container.mainContext

        let work = Work(title: "Reading Now")
        let edition = Edition(pageCount: 400)

        context.insert(work)
        context.insert(edition)

        // Link edition to work (insert-before-relate)
        edition.work = work

        let entry = UserLibraryEntry.createOwnedEntry(for: work, edition: edition, status: .reading, context: context)
        entry.dateStarted = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        entry.currentPage = 200

        // Note: Factory already inserted entry - no manual insert needed
        try context.save()

        let stats = try ReadingStats.calculate(from: context, period: .allTime)

        // 200 pages over 10 days = 20 pages/day
        #expect(stats.averageReadingPace == 20.0)
    }

    @Test("Calculate diversity score")
    func testDiversityScore() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Work.self, Author.self, Edition.self, UserLibraryEntry.self,
            configurations: config
        )
        let context = container.mainContext

        // Create diverse library: 3 regions, 2 genders, 2 languages
        let africanAuthor = Author(name: "Author 1", gender: .female, culturalRegion: .africa)
        let asianAuthor = Author(name: "Author 2", gender: .male, culturalRegion: .asia)
        let europeanAuthor = Author(name: "Author 3", gender: .female, culturalRegion: .europe)

        context.insert(africanAuthor)
        context.insert(asianAuthor)
        context.insert(europeanAuthor)

        let work1 = Work(title: "Book 1", originalLanguage: "Swahili")
        work1.addAuthor(africanAuthor)

        let work2 = Work(title: "Book 2", originalLanguage: "Japanese")
        work2.addAuthor(asianAuthor)

        let work3 = Work(title: "Book 3", originalLanguage: "English")
        work3.addAuthor(europeanAuthor)

        context.insert(work1)
        context.insert(work2)
        context.insert(work3)

        // Add to library
        let edition1 = Edition()
        let edition2 = Edition()
        let edition3 = Edition()

        context.insert(edition1)
        context.insert(edition2)
        context.insert(edition3)

        // Link editions to works (insert-before-relate)
        edition1.work = work1
        edition2.work = work2
        edition3.work = work3

        _ = UserLibraryEntry.createOwnedEntry(for: work1, edition: edition1, status: .read, context: context)
        _ = UserLibraryEntry.createOwnedEntry(for: work2, edition: edition2, status: .read, context: context)
        _ = UserLibraryEntry.createOwnedEntry(for: work3, edition: edition3, status: .read, context: context)

        // Note: Factory already inserted entries - no manual insert needed
        try context.save()

        let stats = try ReadingStats.calculate(from: context, period: .allTime)

        // Should have high diversity score (3 regions, 2 genders, 3 languages, 66% marginalized)
        #expect(stats.diversityScore > 7.0)
    }
}
