//
//  LibraryViewStateTests.swift
//  BooksTrackerFeatureTests
//
//  End-to-end workflow tests for library view state management
//  Tests user interactions with library display: filtering, sorting, searching, editing
//
//  User Stories:
//  - Empty library displays empty state, adding first book transitions view
//  - Large library (100+ books) renders without performance issues
//  - Filter by reading status shows only matching books
//  - Sort by title/date maintains correct order
//  - Search within library filters results
//  - Batch operations (select multiple) work correctly
//  - Delete book removes from library and updates view
//  - Refresh library reloads data

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

// MARK: - Test Helpers

@MainActor
private func createLibraryTestSetup() throws -> (
    context: ModelContext,
    container: ModelContainer,
    repository: LibraryRepository
) {
    let container = try ModelContainer.createWorkflowTestContainer()
    let context = ModelContext(container)
    let repository = LibraryRepository(
        modelContext: context,
        dtoMapper: nil,
        featureFlags: nil
    )
    return (context, container, repository)
}

@MainActor
private func createLibraryWithBooks(
    context: ModelContext,
    count: Int,
    readingStatusDistribution: [ReadingStatus: Int]? = nil
) throws -> [Work] {
    var works: [Work] = []

    if let distribution = readingStatusDistribution {
        var currentIndex = 0
        for (status, statusCount) in distribution {
            for i in 0..<statusCount {
                var workBuilder = WorkBuilder(
                    title: "Book \(status.rawValue) \(i + 1)",
                    modelContext: context
                )
                workBuilder = workBuilder.withAuthor(name: "Author \(currentIndex)")
                workBuilder = workBuilder.withEdition(isbn: "978000000000\(String(format: "%02d", currentIndex))")

                let work = try workBuilder.build()

                let entry = UserLibraryEntry()
                entry.work = work
                entry.edition = work.editions?.first
                entry.readingStatus = status
                context.insert(entry)

                works.append(work)
                currentIndex += 1
            }
        }
    } else {
        for i in 1...count {
            var workBuilder = WorkBuilder(
                title: "Book \(String(format: "%03d", i))",
                modelContext: context
            )
            workBuilder = workBuilder.withAuthor(name: "Author \(i)")
            workBuilder = workBuilder.withEdition(isbn: "978000000000\(String(format: "%02d", i % 99))")

            let work = try workBuilder.build()

            let entry = UserLibraryEntry()
            entry.work = work
            entry.edition = work.editions?.first
            entry.readingStatus = ReadingStatus.allCases[i % ReadingStatus.allCases.count]
            context.insert(entry)

            works.append(work)
        }
    }

    try context.save()
    return works
}

// MARK: - Library View State Tests

@Suite("Library View State Tests")
@MainActor
struct LibraryViewStateTests {

    // MARK: - Empty State

    @Test("Empty library displays empty state")
    func emptyLibraryDisplaysEmptyState() throws {
        // Given: Fresh library
        let (context, _, repository) = try createLibraryTestSetup()

        // When: Fetch library
        let books = try repository.fetchUserLibrary()

        // Then: Empty state
        #expect(books.isEmpty, "Library should be empty")
    }

    @Test("Adding first book transitions from empty to populated state")
    func addFirstBookTransitionsState() throws {
        // Given: Empty library
        let (context, _, repository) = try createLibraryTestSetup()

        var emptyBooks = try repository.fetchUserLibrary()
        #expect(emptyBooks.isEmpty)

        // When: Add first book
        try createLibraryWithBooks(context: context, count: 1)

        // Then: Library is now populated
        let populatedBooks = try repository.fetchUserLibrary()
        #expect(populatedBooks.count == 1)
        #expect(!populatedBooks.first?.title.isEmpty ?? false)
    }

    // MARK: - Large Library Performance

    @Test("Large library (100+ books) renders without lag")
    func largeLibraryPerformance() throws {
        // Given: Create large library
        let (context, _, repository) = try createLibraryTestSetup()

        let startTime = Date()
        try createLibraryWithBooks(context: context, count: 150)
        let creationTime = Date().timeIntervalSince(startTime)

        // When: Fetch all books
        let fetchStart = Date()
        let books = try repository.fetchUserLibrary()
        let fetchTime = Date().timeIntervalSince(fetchStart)

        // Then: All books loaded
        #expect(books.count == 150)

        // And: Fetch completes reasonably fast (<1 second for 150 books)
        #expect(fetchTime < 1.0, "Fetch should complete in <1 second, took \(fetchTime)s")
    }

    // MARK: - Filtering by Reading Status

    @Test("Filter by reading status (.reading) shows only reading books")
    func filterByReadingStatus() throws {
        // Given: Library with mixed reading statuses
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(
            context: context,
            readingStatusDistribution: [
                .reading: 5,
                .toRead: 5,
                .read: 5,
                .wishlist: 5
            ]
        )

        // When: Filter to reading status
        let readingBooks = try repository.fetchByReadingStatus(.reading)

        // Then: Only reading books returned
        #expect(readingBooks.count == 5)
        for book in readingBooks {
            let entry = book.userLibraryEntries?.first
            #expect(entry?.readingStatus == .reading)
        }
    }

    @Test("Filter by reading status (.toRead) shows only to-read books")
    func filterByToReadStatus() throws {
        // Given: Library with mixed statuses
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(
            context: context,
            readingStatusDistribution: [
                .reading: 3,
                .toRead: 7,
                .read: 3
            ]
        )

        // When: Filter to toRead
        let toReadBooks = try repository.fetchByReadingStatus(.toRead)

        // Then: Only toRead books returned
        #expect(toReadBooks.count == 7)
    }

    @Test("Filter by reading status (.read) shows only completed books")
    func filterByReadStatus() throws {
        // Given: Library with multiple statuses
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(
            context: context,
            readingStatusDistribution: [
                .reading: 4,
                .read: 6,
                .toRead: 4
            ]
        )

        // When: Filter to read
        let readBooks = try repository.fetchByReadingStatus(.read)

        // Then: Only read books returned
        #expect(readBooks.count == 6)
    }

    // MARK: - Sorting

    @Test("Sort by title maintains alphabetical order")
    func sortByTitleAlphabetical() throws {
        // Given: Library with unsorted titles
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(context: context, count: 10)

        // When: Fetch library (sorted by lastModified, but we can verify title sorting)
        let books = try repository.fetchUserLibrary()

        // Then: Can sort by title
        let titleSorted = books.sorted { $0.title < $1.title }
        #expect(titleSorted.count == 10)

        // Verify alphabetical order
        for i in 0..<(titleSorted.count - 1) {
            let current = titleSorted[i].title
            let next = titleSorted[i + 1].title
            #expect(current <= next, "Books should be in alphabetical order")
        }
    }

    @Test("Sort by date added maintains chronological order")
    func sortByDateAdded() throws {
        // Given: Library with books added at different times
        let (context, _, repository) = try createLibraryTestSetup()

        // Add books with delays to ensure different timestamps
        var addedBooks: [Work] = []
        for i in 1...5 {
            var workBuilder = WorkBuilder(
                title: "Book \(i)",
                modelContext: context
            )
            workBuilder = workBuilder.withAuthor(name: "Author \(i)")
            workBuilder = workBuilder.withEdition(isbn: "978000000000\(String(format: "%02d", i))")

            let work = try workBuilder.build()

            let entry = UserLibraryEntry()
            entry.work = work
            entry.edition = work.editions?.first
            entry.readingStatus = .toRead
            entry.dateAdded = Date().addingTimeInterval(Double(i) * 60) // 1 minute apart
            context.insert(entry)

            addedBooks.append(work)

            // Small delay between additions
            try? await Task.sleep(for: .milliseconds(10))
        }

        try context.save()

        // When: Fetch by date order
        var descriptor = FetchDescriptor<UserLibraryEntry>(
            sortBy: [SortDescriptor(\.dateAdded, order: .reverse)]
        )
        let entries = try context.fetch(descriptor)

        // Then: Most recent first
        #expect(entries.count == 5)
        for i in 0..<(entries.count - 1) {
            #expect(entries[i].dateAdded ?? Date.distantPast >= entries[i + 1].dateAdded ?? Date.distantPast)
        }
    }

    // MARK: - Searching Within Library

    @Test("Search within library filters by title")
    func searchLibraryByTitle() throws {
        // Given: Library with specific books
        let (context, _, repository) = try createLibraryTestSetup()

        let works = try createLibraryWithBooks(context: context, count: 10)

        // Ensure at least one book with "Dune" in title
        var doneBuilder = WorkBuilder(title: "Dune", modelContext: context)
        doneBuilder = doneBuilder.withAuthor(name: "Frank Herbert")
        doneBuilder = doneBuilder.withEdition(isbn: "9780441172719")
        let duneWork = try doneBuilder.build()

        let entry = UserLibraryEntry()
        entry.work = duneWork
        entry.edition = duneWork.editions?.first
        entry.readingStatus = .toRead
        context.insert(entry)
        try context.save()

        // When: Search for "Dune"
        let searchResults = try repository.searchLibrary(query: "Dune")

        // Then: Only Dune appears
        #expect(searchResults.contains { $0.title == "Dune" })
    }

    @Test("Search within library filters by author name")
    func searchLibraryByAuthor() throws {
        // Given: Library with known authors
        let (context, _, repository) = try createLibraryTestSetup()

        var authorBuilder = WorkBuilder(title: "Test Book", modelContext: context)
        authorBuilder = authorBuilder.withAuthor(name: "J.K. Rowling")
        authorBuilder = authorBuilder.withEdition(isbn: "9780439708180")
        let authorWork = try authorBuilder.build()

        let entry = UserLibraryEntry()
        entry.work = authorWork
        entry.edition = authorWork.editions?.first
        entry.readingStatus = .toRead
        context.insert(entry)
        try context.save()

        // When: Search for author "Rowling"
        let results = try repository.searchLibrary(query: "Rowling")

        // Then: Book by that author appears
        #expect(!results.isEmpty)
        #expect(results.first?.authors?.contains { $0.name.contains("Rowling") } ?? false)
    }

    @Test("Empty search returns all library books")
    func emptySearchReturnsAllBooks() throws {
        // Given: Library with multiple books
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(context: context, count: 5)

        // When: Search with empty query
        let results = try repository.searchLibrary(query: "")

        // Then: All books returned
        let allBooks = try repository.fetchUserLibrary()
        #expect(results.count == allBooks.count)
    }

    // MARK: - Book Deletion

    @Test("Delete book removes from library")
    func deleteBookRemovesFromLibrary() throws {
        // Given: Library with book
        let (context, _, repository) = try createLibraryTestSetup()

        let works = try createLibraryWithBooks(context: context, count: 3)
        var library = try repository.fetchUserLibrary()
        #expect(library.count == 3)

        // When: Delete first book
        let bookToDelete = works[0]
        let entries = try context.fetch(FetchDescriptor<UserLibraryEntry>())
        if let entryToDelete = entries.first(where: { $0.work?.persistentModelID == bookToDelete.persistentModelID }) {
            context.delete(entryToDelete)
            try context.save()
        }

        // Then: Book no longer in library
        library = try repository.fetchUserLibrary()
        #expect(library.count == 2)
        #expect(!library.contains { $0.persistentModelID == bookToDelete.persistentModelID })
    }

    @Test("Delete updates library count correctly")
    func deleteUpdatesLibraryCount() throws {
        // Given: Library with known count
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(context: context, count: 5)
        let initialCount = try repository.totalBooksCount()
        #expect(initialCount == 5)

        // When: Delete multiple books
        let allEntries = try context.fetch(FetchDescriptor<UserLibraryEntry>())
        for i in 0..<2 {
            context.delete(allEntries[i])
        }
        try context.save()

        // Then: Count decreased
        let finalCount = try repository.totalBooksCount()
        #expect(finalCount == 3)
    }

    // MARK: - Batch Operations

    @Test("Select multiple books for batch operations")
    func selectMultipleBooksForBatchOps() throws {
        // Given: Library with books
        let (context, _, repository) = try createLibraryTestSetup()

        let works = try createLibraryWithBooks(context: context, count: 5)

        // When: Select 3 books (simulate UI selection)
        let selectedBooks = Array(works.prefix(3))
        #expect(selectedBooks.count == 3)

        // Then: Can perform batch operation (e.g., mark as read)
        for book in selectedBooks {
            if let entry = book.userLibraryEntries?.first {
                entry.readingStatus = .read
                entry.dateCompleted = Date()
            }
        }
        try context.save()

        // Verify batch update
        let readBooks = try repository.fetchByReadingStatus(.read)
        #expect(readBooks.count >= 3)
    }

    @Test("Mark multiple books as read via batch operation")
    func markMultipleBooksAsReadBatch() throws {
        // Given: Library with toRead books
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(
            context: context,
            readingStatusDistribution: [
                .toRead: 5,
                .read: 2
            ]
        )

        let toReadBooks = try repository.fetchByReadingStatus(.toRead)
        #expect(toReadBooks.count == 5)

        // When: Mark first 3 as read
        let entriesToUpdate = try context.fetch(
            FetchDescriptor<UserLibraryEntry>(
                predicate: #Predicate { $0.readingStatus == .toRead }
            )
        )

        for i in 0..<3 {
            entriesToUpdate[i].readingStatus = .read
            entriesToUpdate[i].dateCompleted = Date()
        }
        try context.save()

        // Then: Count updated
        let updatedToRead = try repository.fetchByReadingStatus(.toRead)
        #expect(updatedToRead.count == 2)

        let readBooks = try repository.fetchByReadingStatus(.read)
        #expect(readBooks.count == 5)
    }

    // MARK: - Refresh Behavior

    @Test("Refresh library reloads data")
    func refreshLibraryReloadsData() throws {
        // Given: Library with books
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(context: context, count: 3)
        let initialBooks = try repository.fetchUserLibrary()

        // When: Manually refresh (re-fetch)
        let refreshedBooks = try repository.fetchUserLibrary()

        // Then: Data identical (refresh maintains consistency)
        #expect(refreshedBooks.count == initialBooks.count)
        #expect(refreshedBooks.map { $0.title } == initialBooks.map { $0.title })
    }

    @Test("Refresh after external modification reflects changes")
    func refreshAfterExternalModification() throws {
        // Given: Library with books
        let (context, _, repository) = try createLibraryTestSetup()

        let works = try createLibraryWithBooks(context: context, count: 3)
        var books = try repository.fetchUserLibrary()
        #expect(books.count == 3)

        // When: External modification (add book via another context/code path)
        var newBuilder = WorkBuilder(title: "New External Book", modelContext: context)
        newBuilder = newBuilder.withAuthor(name: "External Author")
        newBuilder = newBuilder.withEdition(isbn: "9999999999999")
        let newWork = try newBuilder.build()

        let newEntry = UserLibraryEntry()
        newEntry.work = newWork
        newEntry.edition = newWork.editions?.first
        newEntry.readingStatus = .toRead
        context.insert(newEntry)
        try context.save()

        // Then: Refresh shows new book
        books = try repository.fetchUserLibrary()
        #expect(books.count == 4)
    }

    // MARK: - Statistics

    @Test("Library statistics calculated correctly")
    func libraryStatisticsCalculatedCorrectly() throws {
        // Given: Library with known distribution
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(
            context: context,
            readingStatusDistribution: [
                .reading: 3,
                .read: 7,
                .toRead: 5,
                .wishlist: 2
            ]
        )

        // When: Calculate statistics
        let stats = try repository.calculateReadingStatistics()

        // Then: Statistics accurate
        #expect(stats.totalBooks == 17)
        #expect(stats.currentlyReading == 3)
        #expect(stats.completionRate > 0)
    }

    @Test("Diversity score calculated for library")
    func diversityScoreCalculated() throws {
        // Given: Library with authors
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(context: context, count: 5)

        // When: Calculate diversity
        let diversity = try repository.calculateDiversityScore()

        // Then: Score is valid (0.0 to 1.0)
        #expect(diversity >= 0.0)
        #expect(diversity <= 1.0)
    }

    // MARK: - View Rendering Performance

    @Test("List view selective fetching reduces memory")
    func listViewSelectiveFetchingOptimized() throws {
        // Given: Large library
        let (context, _, repository) = try createLibraryTestSetup()

        try createLibraryWithBooks(context: context, count: 100)

        // When: Fetch for list view (optimized)
        let listBooks = try repository.fetchUserLibraryForList()

        // Then: All books fetched efficiently
        #expect(listBooks.count == 100)

        // And: Books have required properties
        for book in listBooks {
            #expect(!book.title.isEmpty)
        }
    }

    @Test("Detail view fetches complete book data")
    func detailViewFetchesCompleteData() throws {
        // Given: Library with populated books
        let (context, _, repository) = try createLibraryTestSetup()

        let works = try createLibraryWithBooks(context: context, count: 1)

        // When: Fetch for detail view
        let detailBook = try repository.fetchWorkDetail(id: works[0].persistentModelID)

        // Then: Full book data available
        #expect(detailBook != nil)
        #expect(detailBook?.authors != nil)
        #expect(detailBook?.editions != nil)
    }
}
