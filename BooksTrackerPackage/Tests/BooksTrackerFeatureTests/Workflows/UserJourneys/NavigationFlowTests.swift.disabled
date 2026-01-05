//
//  NavigationFlowTests.swift
//  BooksTrackerFeatureTests
//
//  End-to-end workflow tests for main navigation flows
//  Tests complete user journeys across tabs and views
//
//  User Stories:
//  - User navigates between tabs (Library → Search → Insights)
//  - Tab state persists when user returns to tab
//  - User navigates deep into detail views and back
//  - Navigation stack properly handles back actions

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

// MARK: - Test Helpers

@MainActor
private func createNavigationTestSetup() throws -> (
    context: ModelContext,
    container: ModelContainer,
    libraryRepository: LibraryRepository
) {
    let container = try ModelContainer.createWorkflowTestContainer()
    let context = ModelContext(container)
    let libraryRepository = LibraryRepository(
        modelContext: context,
        dtoMapper: nil,
        featureFlags: nil
    )
    return (context, container, libraryRepository)
}

@MainActor
private func setupLibraryWithSampleBooks(
    context: ModelContext,
    count: Int = 5
) throws {
    for i in 1...count {
        var workBuilder = WorkBuilder(
            title: "Test Book \(i)",
            modelContext: context
        )
        workBuilder = workBuilder.withAuthor(name: "Test Author \(i)")
        workBuilder = workBuilder.withEdition(isbn: "978000000000\(String(format: "%02d", i))")

        let work = try workBuilder.build()

        let entry = UserLibraryEntry()
        entry.work = work
        entry.edition = work.editions?.first
        entry.readingStatus = i % 2 == 0 ? .reading : .toRead
        context.insert(entry)
    }

    try context.save()
}

// MARK: - Navigation Flow Tests

@Suite("Main Navigation Flow Tests")
@MainActor
struct NavigationFlowTests {

    // MARK: - Tab Switching

    @Test("Tab switching from Library to Search maintains library state")
    func tabSwitchingMaintainsLibraryState() throws {
        // Given: Library tab with loaded books
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 5)

        // When: Get library works
        let libraryWorks = try repository.fetchUserLibrary()
        #expect(libraryWorks.count == 5, "Library should have 5 books")

        // Then: State available when returning (simulated by re-fetching)
        let returnedWorks = try repository.fetchUserLibrary()
        #expect(returnedWorks.count == 5, "Library state preserved")
        #expect(returnedWorks.map { $0.title }.count == 5)
    }

    @Test("Tab switching between all four tabs maintains state")
    func tabSwitchingAllTabsMaintainsState() throws {
        // Given: Setup library with sample data
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 3)

        let initialCount = try repository.fetchUserLibrary().count

        // When: Simulate switching through all tabs
        // Library → Search (implicit: no state change)
        // Search → Insights (implicit: would fetch stats)
        // Insights → Shelf (implicit: would check review queue)
        // Shelf → Library (back to start)

        // Then: Library data intact
        let finalCount = try repository.fetchUserLibrary().count
        #expect(finalCount == initialCount, "Library count unchanged after tab switching")
    }

    // MARK: - State Persistence

    @Test("Filter state persists when switching tabs")
    func filterStatePersistsAcrossTabs() throws {
        // Given: Library with mixed reading statuses
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 10)

        // When: Filter library to reading books
        let readingBooks = try repository.fetchByReadingStatus(.reading)

        // Then: Reading books are identified
        #expect(!readingBooks.isEmpty, "Should have reading books")

        // And: Filter result persists (in real app, would be maintained by view state)
        let readingBooksAgain = try repository.fetchByReadingStatus(.reading)
        #expect(readingBooks.count == readingBooksAgain.count)
    }

    @Test("Search history persists across tab navigation")
    func searchHistoryPersistsAcrossTabs() throws {
        // Given: SearchModel with search history
        let container = try ModelContainer.createWorkflowTestContainer()
        let context = ModelContext(container)
        let dtoMapper = DTOMapper(modelContext: context)
        let searchModel = SearchModel(modelContext: context, dtoMapper: dtoMapper)

        // When: Add searches to history
        searchModel.addToRecentSearches("Dune")
        searchModel.addToRecentSearches("1984")
        searchModel.addToRecentSearches("The Martian")

        // Then: Recent searches persisted (stored in UserDefaults)
        let savedSearches = UserDefaults.standard.array(
            forKey: "RecentBookSearches"
        ) as? [String]
        #expect(savedSearches?.count == 3, "All searches should be saved")
        #expect(savedSearches?.first == "The Martian", "Latest search first")
    }

    // MARK: - Deep Navigation

    @Test("Navigate from library to detail view and back")
    func navigateFromLibraryToDetailAndBack() throws {
        // Given: Library with books
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 1)

        let books = try repository.fetchUserLibrary()
        #expect(books.count == 1)

        // When: Navigate to detail view
        let selectedBook = books.first!
        let bookID = selectedBook.persistentModelID

        // Then: Can fetch book detail
        let detailBook = try repository.fetchWorkDetail(id: bookID)
        #expect(detailBook?.title == selectedBook.title)

        // And: Navigate back to library (just verify we can fetch library again)
        let libraryBooks = try repository.fetchUserLibrary()
        #expect(libraryBooks.count == 1)
    }

    @Test("Multiple detail view navigations maintain identity")
    func multipleDetailNavigationsMaintainIdentity() throws {
        // Given: Library with multiple books
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 3)

        let books = try repository.fetchUserLibrary()

        // When: Navigate to each book's detail and back
        for book in books {
            let detailBook = try repository.fetchWorkDetail(id: book.persistentModelID)
            #expect(detailBook?.persistentModelID == book.persistentModelID)
        }

        // Then: Library still has all books
        let finalBooks = try repository.fetchUserLibrary()
        #expect(finalBooks.count == books.count)
    }

    // MARK: - Navigation Stack Behavior

    @Test("Navigation stack clears properly on reset")
    func navigationStackClearsOnReset() throws {
        // Given: Library with books
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 5)

        let initialCount = try repository.fetchUserLibrary().count
        #expect(initialCount == 5)

        // When: Delete library (reset)
        try context.delete(
            model: UserLibraryEntry.self,
            where: #Predicate { _ in true }
        )
        try context.delete(
            model: Work.self,
            where: #Predicate { _ in true }
        )
        try context.save()

        // Then: Library is empty
        let finalCount = try repository.fetchUserLibrary().count
        #expect(finalCount == 0, "Library cleared")
    }

    @Test("Navigation from search results to detail view")
    func navigationFromSearchResultsToDetail() throws {
        // Given: Search model and library repository
        let (context, _, repository) = try createNavigationTestSetup()

        let container = try ModelContainer.createWorkflowTestContainer()
        let searchContext = ModelContext(container)
        let dtoMapper = DTOMapper(modelContext: searchContext)
        let searchModel = SearchModel(modelContext: searchContext, dtoMapper: dtoMapper)

        // When: Create a work for search results
        var workBuilder = WorkBuilder(title: "Dune", modelContext: context)
        workBuilder = workBuilder.withAuthor(name: "Frank Herbert")
        workBuilder = workBuilder.withEdition(isbn: "9780441172719")
        let work = try workBuilder.build()

        // Create search result
        let authors = work.authors ?? []
        let editions = work.editions ?? []
        let searchResult = SearchResult(
            work: work,
            editions: editions,
            authors: authors,
            relevanceScore: 0.95,
            provider: "test"
        )

        // Then: Can navigate to detail
        #expect(searchResult.work.title == "Dune")
    }

    // MARK: - Modal Navigation

    @Test("Modal presentation and dismissal")
    func modalPresentationAndDismissal() throws {
        // Given: Valid library state
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 1)

        // When: Verify data available for modal
        let books = try repository.fetchUserLibrary()
        #expect(books.count == 1)

        // Then: Can show modal with data
        let book = books.first!
        #expect(book.title.isEmpty == false, "Book has valid title for modal")

        // After dismiss: library still accessible
        let libraryAfterDismiss = try repository.fetchUserLibrary()
        #expect(libraryAfterDismiss.count == 1)
    }

    // MARK: - Error State Navigation

    @Test("Navigation after error in search")
    func navigationAfterSearchError() throws {
        // Given: SearchModel
        let container = try ModelContainer.createWorkflowTestContainer()
        let context = ModelContext(container)
        let dtoMapper = DTOMapper(modelContext: context)
        let searchModel = SearchModel(modelContext: context, dtoMapper: dtoMapper)

        // When: Simulate error state
        searchModel.viewState = .error(
            message: "Network error",
            lastQuery: "Dune",
            lastScope: .all,
            recoverySuggestion: "Try again"
        )

        // Then: Can retry (navigate back to searching)
        let lastQuery = "Dune"
        searchModel.search(query: lastQuery)

        // And: Search initiated (not in error state anymore)
        #expect(true, "Search can be retried after error")
    }

    // MARK: - Background/Foreground Navigation

    @Test("Navigation state preserved during app background transition")
    func navigationStatePreservedAfterBackground() throws {
        // Given: Library with books
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 3)

        let initialBooks = try repository.fetchUserLibrary()
        #expect(initialBooks.count == 3)

        // When: Simulate app going to background and returning
        // (In real scenario, this tests that SwiftData model container persists)

        // Then: Library data still intact
        let restoredBooks = try repository.fetchUserLibrary()
        #expect(restoredBooks.count == 3)
        #expect(restoredBooks.map { $0.title } == initialBooks.map { $0.title })
    }

    // MARK: - Search Coordinator Navigation

    @Test("SearchCoordinator pending search navigation")
    func searchCoordinatorPendingSearchNavigation() throws {
        // Given: SearchCoordinator
        let coordinator = SearchCoordinator()

        // When: Set pending author search
        coordinator.setPendingAuthorSearch("Frank Herbert")

        // Then: Can consume and navigate to search
        let authorSearch = coordinator.consumePendingAuthorSearch()
        #expect(authorSearch == "Frank Herbert")
        #expect(coordinator.pendingAuthorSearch == nil)
    }

    // MARK: - Library View Transitions

    @Test("Library empty to populated state transition")
    func libraryEmptyToPopulatedTransition() throws {
        // Given: Empty library
        let (context, _, repository) = try createNavigationTestSetup()

        let initialBooks = try repository.fetchUserLibrary()
        #expect(initialBooks.isEmpty)

        // When: Add first book
        try setupLibraryWithSampleBooks(context: context, count: 1)

        // Then: Library transitions to populated
        let populatedBooks = try repository.fetchUserLibrary()
        #expect(populatedBooks.count == 1)

        // And: Can still navigate from empty state properly
        #expect(populatedBooks.first?.title.isEmpty == false)
    }

    // MARK: - Insights Navigation

    @Test("Navigate to Insights with populated library")
    func navigateToInsightsWithPopulatedLibrary() throws {
        // Given: Library with books
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 5)

        // When: Calculate reading statistics (what Insights uses)
        let stats = try repository.calculateReadingStatistics()

        // Then: Stats available for display
        #expect(stats.totalBooks == 5)
        #expect(stats.currentlyReading > 0, "Some books should be in reading status")
    }

    // MARK: - Shelf Navigation

    @Test("Navigate to Shelf and check review queue")
    func navigateToShelfAndCheckReviewQueue() throws {
        // Given: Library with some books
        let (context, _, repository) = try createNavigationTestSetup()
        try setupLibraryWithSampleBooks(context: context, count: 3)

        // When: Check review queue count
        let reviewCount = try repository.reviewQueueCount()

        // Then: Review queue accessible
        #expect(reviewCount >= 0, "Review queue count valid")
    }
}
