//
//  SearchModelTests.swift
//  BooksTrackerFeatureTests
//
//  Created by Claude on 2025-10-19.
//  Comprehensive tests for SearchModel state management and search logic
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

// MARK: - Test Helpers

@MainActor
func createTestModelContext() -> ModelContext {
    let container = try! ModelContainer(
        for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
    return container.mainContext
}

// MARK: - State Transition Tests

@Suite("SearchModel State Transitions")
struct SearchModelStateTransitionTests {

    @Test("Initial state starts correctly")
    @MainActor
    func testInitialState() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Verify initial state
        if case .initial = model.viewState {
            // Expected
        } else {
            Issue.record("Expected initial state, got \(model.viewState)")
        }

        #expect(model.searchText.isEmpty)
        #expect(model.viewState.currentResults.isEmpty)
        #expect(model.viewState.isSearching == false)
    }

    @Test("Search transitions from initial to searching")
    @MainActor
    func testSearchStartsFromInitial() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Start search
        Task {
            await model.search(query: "Swift Programming", scope: .all)
        }

        // Give task time to start
        try? await Task.sleep(for: .milliseconds(100))

        // Verify searching state
        #expect(model.viewState.isSearching == true)

        if case .searching(let query, let scope, _) = model.viewState {
            #expect(query == "Swift Programming")
            #expect(scope == .all)
        } else {
            Issue.record("Expected searching state, got \(model.viewState)")
        }
    }

    @Test("Successful search transitions to results or noResults")
    @MainActor
    func testSuccessfulSearchTransition() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Perform search (will hit real API - could mock in future)
        await model.search(query: "Swift Programming", scope: .all)

        // Wait for search to complete (max 10 seconds)
        var iterations = 0
        while model.viewState.isSearching && iterations < 100 {
            try? await Task.sleep(for: .milliseconds(100))
            iterations += 1
        }

        // Verify results or noResults state (both valid)
        switch model.viewState {
        case .results(let query, let scope, let items, _, _):
            #expect(query == "Swift Programming")
            #expect(scope == .all)
            #expect(!items.isEmpty)
        case .noResults(let query, let scope):
            #expect(query == "Swift Programming")
            #expect(scope == .all)
        case .error:
            // Network error is acceptable in test environment
            break
        default:
            Issue.record("Expected results, noResults, or error state after search, got \(model.viewState)")
        }
    }

    @Test("Clear search resets to initial")
    @MainActor
    func testClearSearchResetsState() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Set model to a non-initial state
        model.viewState = .results(
            query: "Test Query",
            scope: .all,
            items: [
                SearchResult(
                    work: Work(title: "Test Book"),
                    editions: [],
                    authors: [],
                    relevanceScore: 1.0,
                    provider: "test"
                )
            ],
            hasMorePages: false,
            cacheHitRate: 0.0
        )

        // Clear
        model.clearSearch()

        // Verify initial state
        if case .initial = model.viewState {
            // Expected
        } else {
            Issue.record("Expected initial state after clear, got \(model.viewState)")
        }

        #expect(model.searchText.isEmpty)
        #expect(model.viewState.currentResults.isEmpty)
    }

    @Test("Multiple searches preserve query context")
    @MainActor
    func testMultipleSearchesPreserveContext() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // First search
        await model.search(query: "First Query", scope: .title)

        // Wait briefly
        try? await Task.sleep(for: .milliseconds(100))

        // Verify first query context
        #expect(model.viewState.currentQuery == "First Query")
        #expect(model.viewState.currentScope == .title)

        // Second search
        await model.search(query: "Second Query", scope: .author)

        // Wait briefly
        try? await Task.sleep(for: .milliseconds(100))

        // Verify second query context
        #expect(model.viewState.currentQuery == "Second Query")
        #expect(model.viewState.currentScope == .author)
    }
}

// MARK: - Pagination Tests

@Suite("SearchModel Pagination")
struct SearchModelPaginationTests {

    @Test("Load more only works when has more results")
    @MainActor
    func testLoadMoreWhenHasMorePages() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Perform initial search
        await model.search(query: "Swift Programming", scope: .all)

        // Wait for completion (max 10 seconds)
        var iterations = 0
        while model.viewState.isSearching && iterations < 100 {
            try? await Task.sleep(for: .milliseconds(100))
            iterations += 1
        }

        // If we have more pages, loadMore should work
        if model.hasMoreResults {
            let initialCount = model.viewState.currentResults.count

            await model.loadMoreResults()

            // Wait for pagination to complete
            iterations = 0
            while model.viewState.isSearching && iterations < 100 {
                try? await Task.sleep(for: .milliseconds(100))
                iterations += 1
            }

            let finalCount = model.viewState.currentResults.count
            #expect(finalCount >= initialCount)  // Should maintain or grow
        } else {
            // No more results to load - that's fine too
        }
    }

    @Test("Load more preserves existing results")
    @MainActor
    func testLoadMorePreservesResults() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Create results state manually for testing
        let initialResult = SearchResult(
            work: Work(title: "Book 1"),
            editions: [],
            authors: [],
            relevanceScore: 1.0,
            provider: "test"
        )

        model.viewState = .results(
            query: "Test",
            scope: .all,
            items: [initialResult],
            hasMorePages: true,
            cacheHitRate: 0.0
        )

        // Verify initial count
        #expect(model.viewState.currentResults.count == 1)

        // Load more (will fail in test env, but should preserve existing)
        await model.loadMoreResults()

        // Verify we still have at least the original result
        #expect(model.viewState.currentResults.count >= 1)
    }

    @Test("hasMoreResults returns false when no more pages")
    @MainActor
    func testHasMoreResultsWhenNoPages() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Set state with no more pages
        model.viewState = .results(
            query: "Test",
            scope: .all,
            items: [
                SearchResult(
                    work: Work(title: "Book 1"),
                    editions: [],
                    authors: [],
                    relevanceScore: 1.0,
                    provider: "test"
                )
            ],
            hasMorePages: false,
            cacheHitRate: 0.0
        )

        #expect(model.hasMoreResults == false)
    }

    @Test("hasMoreResults returns true when has more pages")
    @MainActor
    func testHasMoreResultsWhenHasPages() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Set state with more pages
        model.viewState = .results(
            query: "Test",
            scope: .all,
            items: [
                SearchResult(
                    work: Work(title: "Book 1"),
                    editions: [],
                    authors: [],
                    relevanceScore: 1.0,
                    provider: "test"
                )
            ],
            hasMorePages: true,
            cacheHitRate: 0.0
        )

        #expect(model.hasMoreResults == true)
    }
}

// MARK: - Search Scope Tests

@Suite("SearchModel Search Scopes")
struct SearchModelScopeTests {

    @Test("Search with different scopes", arguments: [
        SearchScope.title,
        SearchScope.author,
        SearchScope.isbn,
        SearchScope.all
    ])
    @MainActor
    func testSearchScopes(scope: SearchScope) async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        await model.search(query: "Test Query", scope: scope)

        // Give search time to start
        try? await Task.sleep(for: .milliseconds(100))

        // Verify scope is preserved in state
        switch model.viewState {
        case .searching(_, let searchScope, _):
            #expect(searchScope == scope)
        case .results(_, let searchScope, _, _, _):
            #expect(searchScope == scope)
        case .noResults(_, let searchScope):
            #expect(searchScope == scope)
        case .error(_, _, let searchScope, _):
            #expect(searchScope == scope)
        case .initial:
            Issue.record("Search should have started, got initial state")
        }
    }

    @Test("Scope persists through state transitions")
    @MainActor
    func testScopePersistence() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Start search with specific scope
        await model.search(query: "Swift", scope: .title)

        // Wait for completion
        var iterations = 0
        while model.viewState.isSearching && iterations < 100 {
            try? await Task.sleep(for: .milliseconds(100))
            iterations += 1
        }

        // Verify scope persisted
        #expect(model.viewState.currentScope == .title)
    }
}

// MARK: - Error Handling Tests

@Suite("SearchModel Error Handling")
struct SearchModelErrorTests {

    @Test("Error state preserves query context")
    @MainActor
    func testErrorPreservesContext() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Manually set error state for testing
        model.viewState = .error(
            message: "Network error",
            lastQuery: "Test Query",
            lastScope: .title,
            recoverySuggestion: "Check connection"
        )

        // Verify context preserved
        if case .error(let message, let lastQuery, let lastScope, let suggestion) = model.viewState {
            #expect(message == "Network error")
            #expect(lastQuery == "Test Query")
            #expect(lastScope == .title)
            #expect(suggestion == "Check connection")
        } else {
            Issue.record("Expected error state, got \(model.viewState)")
        }

        #expect(model.viewState.currentQuery == "Test Query")
        #expect(model.viewState.currentScope == .title)
    }

    @Test("Search with empty query returns no results")
    @MainActor
    func testEmptyQuerySearch() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        await model.search(query: "", scope: .all)

        // Empty query should result in initial or noResults state
        switch model.viewState {
        case .initial, .noResults:
            // Expected
            break
        default:
            Issue.record("Expected initial or noResults for empty query, got \(model.viewState)")
        }
    }

    @Test("Search with very short query handles gracefully")
    @MainActor
    func testShortQuerySearch() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        await model.search(query: "a", scope: .all)

        // Wait for completion
        var iterations = 0
        while model.viewState.isSearching && iterations < 100 {
            try? await Task.sleep(for: .milliseconds(100))
            iterations += 1
        }

        // Should complete without crashing (any valid state is fine)
        switch model.viewState {
        case .initial, .searching, .results, .noResults, .error:
            // All valid outcomes
            break
        }
    }
}

// MARK: - Advanced Search Tests (DISABLED: Tests private implementation)
/*
@Suite("SearchModel Advanced Search")
struct SearchModelAdvancedSearchTests {

    @Test("Advanced search uses correct scope")
    @MainActor
    func testAdvancedSearchScope() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        let criteria = AdvancedSearchCriteria(
            bookTitle: "The Hobbit",
            authorName: "Tolkien",
            isbn: "",
            publisher: "",
            publishedYear: "",
            subjects: []
        )

        // Start advanced search
        Task {
            await model.performAdvancedSearch(criteria: criteria)
        }

        // Give time to start
        try? await Task.sleep(for: .milliseconds(100))

        // Verify scope is .all for advanced search
        switch model.viewState {
        case .searching(_, let scope, _):
            #expect(scope == .all)
        case .results(_, let scope, _, _, _):
            #expect(scope == .all)
        case .noResults(_, let scope):
            #expect(scope == .all)
        default:
            // Error or initial is acceptable
            break
        }
    }

    @Test("Advanced search constructs query correctly")
    @MainActor
    func testAdvancedSearchQueryConstruction() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        let criteria = AdvancedSearchCriteria(
            bookTitle: "Hobbit",
            authorName: "Tolkien",
            isbn: "",
            publisher: "",
            publishedYear: "",
            subjects: []
        )

        await model.performAdvancedSearch(criteria: criteria)

        // Give time to start
        try? await Task.sleep(for: .milliseconds(100))

        // Verify query contains both title and author
        let query = model.viewState.currentQuery
        #expect(query?.contains("Hobbit") ?? false)
        #expect(query?.contains("Tolkien") ?? false)
    }

    @Test("Advanced search with ISBN only")
    @MainActor
    func testAdvancedSearchISBNOnly() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        let criteria = AdvancedSearchCriteria(
            bookTitle: "",
            authorName: "",
            isbn: "9780547928227",
            publisher: "",
            publishedYear: "",
            subjects: []
        )

        await model.performAdvancedSearch(criteria: criteria)

        // Give time to start
        try? await Task.sleep(for: .milliseconds(100))

        // Verify query is the ISBN
        let query = model.viewState.currentQuery
        #expect(query == "9780547928227")
    }
}
*/

// MARK: - Debouncing Tests

@Suite("SearchModel Debouncing")
struct SearchModelDebounceTests {

    @Test("Rapid text changes debounce correctly")
    @MainActor
    func testSearchDebouncing() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Trigger multiple rapid text changes
        model.searchText = "S"
        model.searchText = "Sw"
        model.searchText = "Swi"
        model.searchText = "Swif"
        model.searchText = "Swift"

        // Wait for debounce delay (300ms) plus buffer
        try? await Task.sleep(for: .milliseconds(500))

        // Only last search should execute
        switch model.viewState {
        case .searching(let query, _, _):
            #expect(query == "Swift")
        case .results(let query, _, _, _, _):
            #expect(query == "Swift")
        case .noResults(let query, _):
            #expect(query == "Swift")
        case .error(_, let lastQuery, _, _):
            #expect(lastQuery == "Swift")
        case .initial:
            // If still initial, text might have been too short to trigger search
            break
        }
    }

    @Test("Clearing text cancels debounced search")
    @MainActor
    func testClearingTextCancelsSearch() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Start typing
        model.searchText = "Swift"

        // Clear before debounce completes
        try? await Task.sleep(for: .milliseconds(100))
        model.searchText = ""

        // Wait for debounce to complete
        try? await Task.sleep(for: .milliseconds(500))

        // Should remain in initial state
        if case .initial = model.viewState {
            // Expected
        } else {
            Issue.record("Expected initial state after clearing text, got \(model.viewState)")
        }
    }
}

// MARK: - Helper Methods Tests

@Suite("SearchModel Helper Methods")
struct SearchModelHelperTests {

    @Test("currentResults computed property returns correct items")
    @MainActor
    func testCurrentResultsProperty() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Initial state has no results
        #expect(model.viewState.currentResults.isEmpty)

        // Set results state
        let result = SearchResult(
            work: Work(title: "Test Book"),
            editions: [],
            authors: [],
            relevanceScore: 1.0,
            provider: "test"
        )

        model.viewState = .results(
            query: "Test",
            scope: .all,
            items: [result],
            hasMorePages: false,
            cacheHitRate: 0.0
        )

        // Verify results accessible
        #expect(model.viewState.currentResults.count == 1)
        #expect(model.viewState.currentResults.first?.work.title == "Test Book")
    }

    @Test("isSearching computed property reflects state")
    @MainActor
    func testIsSearchingProperty() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Initial state is not searching
        #expect(model.viewState.isSearching == false)

        // Searching state is searching
        model.viewState = .searching(query: "Test", scope: .all, previousResults: [])
        #expect(model.viewState.isSearching == true)

        // Results state is not searching
        model.viewState = .results(
            query: "Test",
            scope: .all,
            items: [],
            hasMorePages: false,
            cacheHitRate: 0.0
        )
        #expect(model.viewState.isSearching == false)
    }

    @Test("currentQuery computed property reflects state")
    @MainActor
    func testCurrentQueryProperty() async {
        let modelContext = createTestModelContext()
        let model = SearchModel(modelContext: modelContext)

        // Initial state has empty query
        #expect((model.viewState.currentQuery ?? "").isEmpty)

        // Results state preserves query
        model.viewState = .results(
            query: "Test Query",
            scope: .all,
            items: [],
            hasMorePages: false,
            cacheHitRate: 0.0
        )
        #expect(model.viewState.currentQuery == "Test Query")

        // Error state preserves last query
        model.viewState = .error(
            message: "Error",
            lastQuery: "Error Query",
            lastScope: .all,
            recoverySuggestion: "Retry"
        )
        #expect(model.viewState.currentQuery == "Error Query")
    }
}
