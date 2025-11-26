import Foundation
import SwiftUI
import SwiftData

// MARK: - Search Scope Enum

public enum SearchScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case title = "Title"
    case author = "Author"
    case isbn = "ISBN"

    public var id: String { rawValue }

    /// HIG: Provide clear, concise scope labels
    public var displayName: String { rawValue }

    /// HIG: Accessibility - descriptive labels for VoiceOver
    public var accessibilityLabel: String {
        switch self {
        case .all: return "Search all fields"
        case .title: return "Search by book title"
        case .author: return "Search by author name"
        case .isbn: return "Search by ISBN number"
        }
    }

}

// MARK: - Search Mode Enum

/// Search mode for V2 Unified Search API
/// Determines the type of search algorithm used by the backend
public enum SearchMode: String, CaseIterable, Identifiable, Sendable {
    /// Text-based search using traditional keyword matching
    /// Rate limit: 100 requests/minute
    case text = "text"
    
    /// AI-powered semantic search using vector embeddings
    /// Rate limit: 5 requests/minute (compute intensive)
    case semantic = "semantic"
    
    public var id: String { rawValue }
    
    /// HIG: Provide clear, concise mode labels
    public var displayName: String {
        switch self {
        case .text: return "Text"
        case .semantic: return "AI Search"
        }
    }
    
    /// HIG: Accessibility - descriptive labels for VoiceOver
    public var accessibilityLabel: String {
        switch self {
        case .text: return "Text-based keyword search"
        case .semantic: return "AI-powered semantic search"
        }
    }
    
    /// User-facing description explaining the search mode
    public var description: String {
        switch self {
        case .text: return "Traditional keyword matching"
        case .semantic: return "AI understands meaning and context"
        }
    }
    
    /// Rate limit in requests per minute
    public var rateLimitPerMinute: Int {
        switch self {
        case .text: return 100
        case .semantic: return 5
        }
    }
}

// MARK: - Search State Management

@Observable
@MainActor
public final class SearchModel {
    // Unified search state
    var searchText: String = ""
    var viewState: SearchViewState = .loadingTrending(recentSearches: [])

    // V2 Search mode state
    var searchMode: SearchMode = .text
    
    // Rate limit tracking for semantic search (5 req/min)
    private var semanticSearchTimestamps: [Date] = []
    private let semanticSearchWindowSeconds: TimeInterval = 60
    
    // Computed property for remaining semantic searches in current window
    var remainingSemanticSearches: Int {
        cleanupOldTimestamps()
        let used = semanticSearchTimestamps.count
        let limit = SearchMode.semantic.rateLimitPerMinute
        return max(0, limit - used)
    }
    
    // Computed property for seconds until semantic search is available again
    var secondsUntilSemanticSearchAvailable: Int {
        cleanupOldTimestamps()
        guard semanticSearchTimestamps.count >= SearchMode.semantic.rateLimitPerMinute else {
            return 0
        }
        // Find the oldest timestamp in the window
        if let oldestTimestamp = semanticSearchTimestamps.first {
            let resetTime = oldestTimestamp.addingTimeInterval(semanticSearchWindowSeconds)
            let secondsRemaining = Int(resetTime.timeIntervalSinceNow)
            return max(0, secondsRemaining)
        }
        return 0
    }

    // Search suggestions (still separate - UI-specific feature)
    var searchSuggestions: [String] = []
    var recentSearches: [String] = []  // Public for SearchView access (TODO: move to viewState in Task 4)
    var popularSearches: [String] = []  // Dynamic from backend API (Issue #20)

    /// Fallback searches when API is unavailable
    private let fallbackPopularSearches = [
        "Andy Weir", "Stephen King", "Agatha Christie", "J.K. Rowling",
        "The Martian", "Dune", "1984", "Pride and Prejudice",
        "science fiction", "mystery", "romance", "fantasy"
    ]

    /// Cache duration for trending searches (24 hours)
    private static let trendingSearchesCacheDuration: TimeInterval = 24 * 60 * 60
    private static let trendingSearchesCacheKey = "TrendingSearchesCache"
    private static let trendingSearchesCacheTimestampKey = "TrendingSearchesCacheTimestamp"

    // Performance tracking
    var lastSearchTime: TimeInterval = 0
    var cacheHitRate: Double = 0.0

    // Trending books cache (loaded once per session)
    private var cachedTrendingBooks: [SearchResult]?

    // Dependencies
    private let apiService: BookSearchAPIService
    private let modelContext: ModelContext
    private var searchTask: Task<Void, Never>?

    // Pagination state
    private var currentPage: Int = 1

    public init(modelContext: ModelContext, dtoMapper: DTOMapper) {
        self.apiService = BookSearchAPIService(modelContext: modelContext, dtoMapper: dtoMapper)
        self.modelContext = modelContext

        // Load recent searches from UserDefaults
        if let savedSearches = UserDefaults.standard.array(forKey: "RecentBookSearches") as? [String] {
            self.recentSearches = savedSearches
            self.viewState = .loadingTrending(recentSearches: savedSearches)
        }

        // Load cached trending searches immediately (Issue #20)
        self.popularSearches = loadCachedTrendingSearches() ?? fallbackPopularSearches

        Task {
            await loadTrendingSearches()  // Refresh from API if cache expired
            await loadTrendingBooks()
            generateSearchSuggestions(for: "")
        }
    }

    // MARK: - Public Methods

    /// Computed property for pagination support
    var hasMoreResults: Bool {
        if case .results(_, _, _, let hasMore, _) = viewState {
            return hasMore
        }
        return false
    }

    // MARK: - Search Options Configuration

    private struct SearchOptions {
        var titleFilter: String?
        var authorFilter: String?
        var isbnFilter: String?
        var isAdvanced: Bool = false
    }

    // MARK: - Advanced Search

    func advancedSearch(criteria: AdvancedSearchCriteria) {
        // Cancel previous search
        searchTask?.cancel()

        searchTask = Task {
            await performAdvancedSearch(criteria: criteria)
        }
    }

    private func performAdvancedSearch(criteria: AdvancedSearchCriteria) async {
        // Update search text for display (combined query)
        if let query = criteria.buildSearchQuery() {
            searchText = query
        }

        // Configure advanced search options
        let options = SearchOptions(
            titleFilter: criteria.bookTitle.isEmpty ? nil : criteria.bookTitle,
            authorFilter: criteria.authorName.isEmpty ? nil : criteria.authorName,
            isbnFilter: criteria.isbn.isEmpty ? nil : criteria.isbn,
            isAdvanced: true
        )

        // Execute unified search
        do {
            try await executeSearch(query: searchText, scope: .all, options: options)
        } catch {
            handleSearchError(error, query: searchText, scope: .all)
        }
    }

    func search(query: String, scope: SearchScope = .all) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedQuery.isEmpty else {
            resetToInitialState()
            return
        }

        // Cancel previous search
        searchTask?.cancel()

        // DO NOT update searchText here. The view's @State is the source of truth.
        // This was causing a feedback loop that broke the spacebar.

        // Determine debounce delay based on query length and type
        let debounceDelay = calculateDebounceDelay(for: trimmedQuery)

        // Update suggestions immediately
        generateSearchSuggestions(for: trimmedQuery)

        // Start search with intelligent debouncing
        searchTask = Task {
            // Intelligent debounce delay
            try? await Task.sleep(nanoseconds: UInt64(debounceDelay * 1_000_000_000))

            // Check if task was cancelled
            guard !Task.isCancelled else { return }

            do {
                try await executeSearch(query: trimmedQuery, scope: scope)
            } catch {
                handleSearchError(error, query: trimmedQuery, scope: scope)
            }
        }
    }

    /// Load more results for pagination
    func loadMoreResults() async {
        guard hasMoreResults, !viewState.isSearching else { return }

        // Extract query and scope from current state
        guard let query = viewState.currentQuery,
              let scope = viewState.currentScope else { return }

        currentPage += 1

        do {
            try await executeSearch(
                query: query,
                scope: scope,
                page: currentPage,
                appendResults: true
            )
        } catch {
            handleSearchError(error, query: query, scope: scope)
        }
    }

    // MARK: - Smart Debouncing Logic

    private func calculateDebounceDelay(for query: String) -> Double {
        // ISBN patterns get immediate search (no debounce)
        if isISBNPattern(query) {
            return 0.1
        }

        // Short queries (1-3 chars) - optimized for mobile responsiveness (was 0.8s)
        if query.count <= 3 {
            return 0.3
        }

        // Medium queries (4-6 chars) - fast response (was 0.5s)
        if query.count <= 6 {
            return 0.2
        }

        // Longer queries - immediate response (was 0.3s)
        return 0.15
    }

    private func isISBNPattern(_ query: String) -> Bool {
        let cleanQuery = query.replacingOccurrences(of: "[^0-9X]", with: "", options: .regularExpression)
        return cleanQuery.count == 10 || cleanQuery.count == 13
    }

    func clearSearch() {
        searchTask?.cancel()
        searchText = ""
        resetToInitialState()
    }

    func retryLastSearch() {
        guard !searchText.isEmpty else { return }
        search(query: searchText)
    }

    /// Search for a specific ISBN from barcode scanning
    func searchByISBN(_ isbn: String) {
        // Set search text and immediately perform search without debouncing
        searchText = isbn

        // Cancel any previous search
        searchTask?.cancel()

        // Start immediate search for ISBN
        searchTask = Task {
            do {
                try await executeSearch(query: isbn)
            } catch {
                handleSearchError(error, query: isbn, scope: .all)
            }
        }
    }

    // MARK: - Search Suggestions & History

    func generateSearchSuggestions(for query: String) {
        let lowercaseQuery = query.lowercased()

        if query.isEmpty {
            // Show recent searches and popular searches when empty
            // ✅ FIXED: Deduplicate to prevent duplicate IDs in ForEach
            var combined = Array(recentSearches.prefix(3))
            let popular = popularSearches.filter { !combined.contains($0) }
            combined.append(contentsOf: Array(popular.prefix(5)))
            searchSuggestions = combined
            return
        }

        var suggestions: [String] = []

        // Add matching recent searches
        let matchingRecent = recentSearches.filter {
            $0.lowercased().contains(lowercaseQuery)
        }.prefix(2)
        suggestions.append(contentsOf: matchingRecent)

        // Add matching popular searches
        let matchingPopular = popularSearches.filter {
            $0.lowercased().contains(lowercaseQuery) && !suggestions.contains($0)
        }.prefix(3)
        suggestions.append(contentsOf: matchingPopular)

        // Add query completion suggestions
        let completions = generateQueryCompletions(for: query)
        suggestions.append(contentsOf: completions.filter { !suggestions.contains($0) })

        searchSuggestions = Array(suggestions.prefix(6)) // Limit to 6 suggestions
    }

    func addToRecentSearches(_ query: String) {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return }

        // Remove if already exists
        recentSearches.removeAll { $0.lowercased() == trimmedQuery.lowercased() }

        // Add to beginning
        recentSearches.insert(trimmedQuery, at: 0)

        // Keep only last 10 searches
        if recentSearches.count > 10 {
            recentSearches = Array(recentSearches.prefix(10))
        }

        // Persist to UserDefaults (simple persistence)
        UserDefaults.standard.set(recentSearches, forKey: "RecentBookSearches")
    }

    func clearRecentSearches() {
        recentSearches.removeAll()
        UserDefaults.standard.removeObject(forKey: "RecentBookSearches")
    }

    private func generateQueryCompletions(for query: String) -> [String] {
        let lowercaseQuery = query.lowercased()

        // Smart completions based on query patterns
        var completions: [String] = []

        // Author name patterns
        if lowercaseQuery.contains("king") {
            completions.append("Stephen King")
        }
        if lowercaseQuery.contains("weir") {
            completions.append("Andy Weir")
        }
        if lowercaseQuery.contains("christie") {
            completions.append("Agatha Christie")
        }

        // Book title patterns
        if lowercaseQuery.contains("martian") {
            completions.append("The Martian")
        }
        if lowercaseQuery.contains("dune") {
            completions.append("Dune")
        }

        // Genre patterns
        if lowercaseQuery.contains("sci") {
            completions.append("science fiction")
        }
        if lowercaseQuery.contains("fant") {
            completions.append("fantasy")
        }
        if lowercaseQuery.contains("myst") {
            completions.append("mystery")
        }

        return completions
    }

    // MARK: - Private Methods

    // MARK: - Unified Search Execution

    /// Unified search method that handles both basic and advanced searches
    private func executeSearch(
        query: String,
        scope: SearchScope = .all,
        page: Int = 1,
        appendResults: Bool = false,
        options: SearchOptions = SearchOptions(),
        retryCount: Int = 0
    ) async throws {
        // Set searching state with previous results for smooth UX
        if !appendResults {
            viewState = .searching(
                query: query,
                scope: scope,
                previousResults: viewState.currentResults
            )
            currentPage = 1
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            // Call appropriate API based on search type and feature flags
            let response: SearchResponse
            
            // Check if V2 search is enabled via feature flag
            let useV2Search = FeatureFlags.shared.enableV2Search
            
            if useV2Search && !options.isAdvanced {
                // Use V2 unified search API
                logger.debug("🔍 Using V2 search API (mode: \(searchMode.rawValue))")
                
                // Check rate limit for semantic mode
                if searchMode == .semantic {
                    guard !isSemanticSearchRateLimited else {
                        throw SearchError.rateLimitExceeded(retryAfter: secondsUntilSemanticSearchAvailable)
                    }
                }
                
                response = try await apiService.searchV2(query: query, mode: searchMode, limit: 20)
                
                // Record semantic search for rate limit tracking
                if searchMode == .semantic {
                    recordSemanticSearch()
                }
            } else if options.isAdvanced, let authorName = options.authorFilter, options.titleFilter == nil, options.isbnFilter == nil {
                // This is an author-only advanced search, use the dedicated endpoint
                response = try await apiService.advancedSearch(
                    author: authorName,
                    title: nil,
                    isbn: nil
                )
            } else if options.isAdvanced {
                response = try await apiService.advancedSearch(
                    author: options.authorFilter,
                    title: options.titleFilter,
                    isbn: options.isbnFilter
                )
            } else {
                response = try await apiService.search(query: query, maxResults: 20, scope: scope)
            }

            // Check if task was cancelled
            guard !Task.isCancelled else { throw CancellationError() }

            // Enrich search results with library status
            let enrichedResults = await enrichResultsWithLibraryStatus(response.results)

            guard !Task.isCancelled else { throw CancellationError() }

            // Update performance metrics
            lastSearchTime = CFAbsoluteTimeGetCurrent() - startTime
            cacheHitRate = response.cacheHitRate

            // Calculate final results (append or replace)
            let finalResults: [SearchResult]
            if appendResults {
                finalResults = viewState.currentResults + enrichedResults
            } else {
                finalResults = enrichedResults
            }

            let hasMore = (finalResults.count) < (response.totalItems ?? 0)

            // Update UI state based on results
            if finalResults.isEmpty {
                viewState = .noResults(query: query, scope: scope)
            } else {
                viewState = .results(
                    query: query,
                    scope: scope,
                    items: finalResults,
                    hasMorePages: hasMore,
                    cacheHitRate: response.cacheHitRate
                )
                // Add successful search to recent searches
                if !appendResults {
                    addToRecentSearches(query)

                    // Track search activity for trending calculations
                    for result in enrichedResults.prefix(5) {  // Track top 5 results
                        if let isbn = result.primaryEdition?.isbn ?? result.primaryEdition?.isbns.first {
                            apiService.trackActivity(isbn: isbn, title: result.displayTitle, type: .search)
                        }
                    }
                }
            }

        } catch {
            guard !Task.isCancelled else { throw CancellationError() }

            // Implement intelligent retry logic
            if shouldRetry(error: error, attempt: retryCount) {
                let retryDelay = calculateRetryDelay(attempt: retryCount)
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))

                guard !Task.isCancelled else { throw CancellationError() }

                try await executeSearch(
                    query: query,
                    scope: scope,
                    page: page,
                    appendResults: appendResults,
                    options: options,
                    retryCount: retryCount + 1
                )
                return
            }

            // Re-throw error for caller to handle
            throw error
        }
    }

    /// Handle search errors consistently across all search methods
    private func handleSearchError(_ error: Error, query: String, scope: SearchScope) {
        guard !Task.isCancelled else { return }

        let errorMsg = formatUserFriendlyError(error)
        viewState = .error(
            message: errorMsg,
            lastQuery: query,
            lastScope: scope,
            recoverySuggestion: "Check your connection and try again"
        )
    }



    // MARK: - Retry Logic

    private func shouldRetry(error: Error, attempt: Int) -> Bool {
        guard attempt < 2 else { return false } // Max 2 retries

        // Retry on network errors but not on client errors
        if let searchError = error as? SearchError {
            switch searchError {
            case .httpError(let code):
                return code >= 500 // Retry on server errors
            case .networkError, .invalidResponse:
                return true
            case .invalidQuery, .invalidURL, .decodingError, .apiError, .rateLimitExceeded, .corsBlocked:
                return false // Don't retry client errors, rate limits, or CORS issues
            }
        }

        return false // Don't retry unknown errors
    }

    private func calculateRetryDelay(attempt: Int) -> Double {
        // Exponential backoff: 1s, 2s, 4s
        return pow(2.0, Double(attempt))
    }

    private func formatUserFriendlyError(_ error: Error) -> String {
        if let searchError = error as? SearchError {
            switch searchError {
            case .httpError(let code) where code >= 500:
                return "Server temporarily unavailable. Please try again."
            case .networkError, .invalidResponse:
                return "Network connection issue. Check your internet connection."
            case .invalidQuery:
                return "Please enter a valid search term."
            case .rateLimitExceeded:
                return "Too many requests. Please wait before trying again."
            case .corsBlocked:
                return "Network access blocked. Check your connection or VPN."
            default:
                return searchError.localizedDescription
            }
        }

        return "Search failed. Please try again."
    }

    private func resetToInitialState() {
        // Get current trending and recent searches from viewState if available
        let trending: [SearchResult]
        if case .initial(let existingTrending, _) = viewState {
            trending = existingTrending
        } else {
            trending = []
        }

        viewState = .initial(trending: trending, recentSearches: recentSearches)
        currentPage = 1
    }

    private func loadTrendingBooks() async {
        // Check cache first - only load once per session
        if let cached = cachedTrendingBooks {
            #if DEBUG
            print("✅ SearchModel: Using cached trending books (\(cached.count) items)")
            #endif
            viewState = .initial(trending: cached, recentSearches: recentSearches)
            return
        }

        // Load curated trending books from API (first time only)
        #if DEBUG
        print("🔄 SearchModel: Loading curated trending books...")
        #endif
        do {
            let response = try await apiService.getTrendingBooks()
            #if DEBUG
            print("✅ SearchModel: Loaded \(response.results.count) curated trending books")
            #endif

            // Cache the results for the session
            cachedTrendingBooks = response.results

            // Update viewState with loaded trending books
            viewState = .initial(trending: response.results, recentSearches: recentSearches)
            #if DEBUG
            print("✅ SearchModel: Updated viewState to .initial with \(response.results.count) trending books")
            #endif
        } catch {
            // Silently fail for trending books - not critical
            #if DEBUG
            print("❌ SearchModel: Failed to load trending books: \(error)")
            #endif
            // Show initial state without trending books
            viewState = .initial(trending: [], recentSearches: recentSearches)
        }
    }

    // MARK: - Trending Searches (Issue #20)

    /// Load trending searches from backend API with caching
    /// - Uses 24-hour cache to reduce API calls
    /// - Falls back to hardcoded list if API unavailable
    private func loadTrendingSearches() async {
        // Check if cache is still valid
        if let cached = loadCachedTrendingSearches(), isTrendingSearchesCacheValid() {
            #if DEBUG
            print("✅ SearchModel: Using cached trending searches (\(cached.count) items)")
            #endif
            popularSearches = cached
            return
        }

        // Fetch from API
        #if DEBUG
        print("🔄 SearchModel: Fetching trending searches from API...")
        #endif

        do {
            let searches = try await apiService.getTrendingSearches(limit: 12)
            popularSearches = searches
            saveTrendingSearchesToCache(searches)
            #if DEBUG
            print("✅ SearchModel: Loaded \(searches.count) trending searches from API")
            #endif
        } catch {
            // Use fallback - API not available or failed
            #if DEBUG
            print("⚠️ SearchModel: Trending searches API unavailable, using fallback: \(error)")
            #endif
            popularSearches = loadCachedTrendingSearches() ?? fallbackPopularSearches
        }
    }

    /// Load cached trending searches from UserDefaults
    private func loadCachedTrendingSearches() -> [String]? {
        UserDefaults.standard.array(forKey: Self.trendingSearchesCacheKey) as? [String]
    }

    /// Check if trending searches cache is still valid (within 24 hours)
    private func isTrendingSearchesCacheValid() -> Bool {
        guard let timestamp = UserDefaults.standard.object(forKey: Self.trendingSearchesCacheTimestampKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(timestamp) < Self.trendingSearchesCacheDuration
    }

    /// Save trending searches to cache with timestamp
    private func saveTrendingSearchesToCache(_ searches: [String]) {
        UserDefaults.standard.set(searches, forKey: Self.trendingSearchesCacheKey)
        UserDefaults.standard.set(Date(), forKey: Self.trendingSearchesCacheTimestampKey)
    }

    // MARK: - Rate Limit Tracking
    
    /// Clean up timestamps older than the rate limit window (60 seconds)
    private func cleanupOldTimestamps() {
        let cutoffTime = Date().addingTimeInterval(-semanticSearchWindowSeconds)
        semanticSearchTimestamps.removeAll { $0 < cutoffTime }
    }
    
    /// Record a semantic search request for rate limit tracking
    private func recordSemanticSearch() {
        cleanupOldTimestamps()
        semanticSearchTimestamps.append(Date())
    }
    
    /// Check if semantic search is rate limited
    var isSemanticSearchRateLimited: Bool {
        return remainingSemanticSearches <= 0
    }

    private func enrichResultsWithLibraryStatus(_ results: [SearchResult]) async -> [SearchResult] {
        var enrichedResults: [SearchResult] = []

        for result in results {
            if let entry = DuplicateDetectionService.findExistingEntry(for: result.work, in: modelContext) {
                result.work.userLibraryEntries = [entry]
            }
            enrichedResults.append(result)
        }

        return enrichedResults
    }
}

// MARK: - Search Result Model

// SAFETY: @unchecked Sendable because SwiftData models (Work, Edition, Author) are not
// explicitly Sendable-conforming, but all SearchResult creation and usage happens on
// @MainActor (via BookSearchAPIService and SearchModel), ensuring thread safety.
public struct SearchResult: Identifiable, Hashable, @unchecked Sendable {
    public let id = UUID()
    public let work: Work
    public let editions: [Edition]
    public let authors: [Author]
    public let relevanceScore: Double
    public let provider: String // "isbndb", "cache", etc.

    // Computed properties for display
    public var primaryEdition: Edition? {
        editions.first
    }

    public var displayTitle: String {
        work.title
    }

    public var displayAuthors: String {
        // Use the authors array from SearchResult instead of work.authorNames
        // because SwiftData relationships don't work for non-persisted objects
        let names = authors.map { $0.name }
        switch names.count {
        case 0: return "Unknown Author"
        case 1: return names[0]
        case 2: return names.joined(separator: " and ")
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }

    public var coverImageURL: URL? {
        // Try to get cover from primary edition
        primaryEdition?.coverURL
    }

    public var isInLibrary: Bool {
        work.isInLibrary
    }

    public var culturalRegion: CulturalRegion? {
        work.culturalRegion
    }

    // MARK: - Equatable & Hashable Conformance

    public static func == (lhs: SearchResult, rhs: SearchResult) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}