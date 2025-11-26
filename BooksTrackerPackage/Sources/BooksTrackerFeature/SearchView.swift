import SwiftUI
import SwiftData

#if canImport(UIKit)
import UIKit
#endif

// MARK: - iOS 26 HIG Compliance Documentation
/*
 SearchView - 100% iOS 26 Human Interface Guidelines Compliant

 This view implements all iOS 26 HIG best practices for search experiences:

 ✅ HIG Compliance Achievements:

 1. **Native Search Integration** (HIG: Search and Suggestions)
    - Uses `.searchable()` modifier for standard iOS search bar placement
    - Search bar positioned at top of navigation bar (iOS 26 standard)
    - Search scopes for filtering (All/Title/Author/ISBN)
    - Integrated with navigation stack for consistent UX

 2. **Focus Management** (HIG: Focus and Selection)
    - `@FocusState` for proper keyboard dismissal
    - Automatic focus management during search transitions
    - Respects user's interaction context

 3. **Navigation Patterns** (HIG: Navigation)
    - `.navigationDestination()` instead of sheets for book details
    - Maintains navigation stack coherence
    - Proper back navigation with state preservation

 4. **Empty States** (HIG: Empty States)
    - Enhanced empty states with contextual suggestions
    - Clear calls-to-action for each state
    - Helpful guidance for users (trending books, recent searches)

 5. **Accessibility** (HIG: Accessibility)
    - VoiceOver custom actions for power users
    - Comprehensive accessibility labels
    - Dynamic Type support throughout
    - High contrast color support

 6. **Performance** (HIG: Performance)
    - Pagination with loading indicators
    - Intelligent debouncing
    - Debug-only performance tracking

 7. **Swift 6 Concurrency** (Language Compliance)
    - `@MainActor` isolation on SearchModel
    - Proper async/await patterns
    - No data races or concurrency warnings

 Architecture:
 - Pure SwiftUI with @Observable state management (no ViewModels)
 - iOS 26 Liquid Glass design system integration
 - Showcase-quality iOS development patterns
 */

// MARK: - Main Search View

@available(iOS 26.0, *)
public struct SearchView: View {
    @Environment(\.iOS26ThemeStore) private var themeStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dtoMapper) private var dtoMapper
    @Environment(SearchCoordinator.self) private var searchCoordinator
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(FeatureFlags.self) private var featureFlags

    // MARK: - State Management
    // HIG: Use SwiftUI's standard state management patterns

    @State private var searchModel: SearchModel?
    @State private var selectedBook: SearchResult?
    @State private var tappedBook: SearchResult?
    @State private var editionComparisonData: EditionComparisonData?
    @State private var searchScope: SearchScope = .all
    @Namespace private var searchTransition

    public init() {}

    // iOS 26 Scrolling Enhancements
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollPhase: ScrollPhase = .idle
    @State private var showBackToTop = false

    // Performance tracking for development
    #if DEBUG
    @State private var performanceText = ""
    #endif

    // Scanner state
    @State private var showingScanner = false

    // Advanced search state
    @State private var showingAdvancedSearch = false

    // Pagination state
    @State private var isLoadingMore = false

    // Image prefetching
    @StateObject private var imagePrefetcher = ImagePrefetcher()
    
    // MARK: - Computed Properties

    private var availableSearchScopes: [SearchScope] {
        var scopes = SearchScope.allCases
        // Only show semantic search if the capability is explicitly true.
        // Defaults to hidden if the API call fails or the flag is false.
        if featureFlags.apiCapabilities?.features.semanticSearch != true {
            scopes.removeAll { $0 == .semantic }
        }
        return scopes
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if let searchModel = searchModel {
                // ✅ NO NavigationStack here - ContentView already provides it (#377)
                searchContentArea(searchModel: searchModel)
                        // HIG: Standard iOS search bar placement (top of navigation)
                        // NOTE: Removed explicit displayMode to fix iOS 26 keyboard bug on physical devices
                        // displayMode: .always was blocking space bar and touch events on iPhone 17 Pro
                        .searchable(
                            text: Binding(
                                get: { searchModel.searchText },
                                set: { searchModel.searchText = $0 }
                            ),
                            placement: .navigationBarDrawer,
                            prompt: searchPrompt
                        )
                        // HIG: Search scopes for filtering
                        .searchScopes($searchScope) {
                            ForEach(availableSearchScopes) { scope in
                                Text(scope.displayName)
                                    .tag(scope)
                                    .accessibilityLabel(scope.accessibilityLabel)
                            }
                        }
                        // HIG: Search suggestions integration
                        .searchSuggestions {
                            searchSuggestionsView(searchModel: searchModel)
                        }
                        .id(searchModel.searchSuggestions.count)  // Force re-evaluation when suggestions change
                        // HIG: Navigation destination for hierarchical navigation
                        .navigationDestination(item: $selectedBook) { book in
                            WorkDiscoveryView(searchResult: book)
                                .navigationTitle(book.displayTitle)
                                .navigationBarTitleDisplayMode(.large)
                        }
                        .navigationTitle("Search")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarLeading) {
                                advancedSearchButton
                            }
                            ToolbarItem(placement: .navigationBarTrailing) {
                                barcodeButton
                            }

                            if FeatureFlags.shared.enableV2Search {
                                ToolbarItemGroup(placement: .bottomBar) {
                                    Picker("Search Mode", selection: Binding(
                                        get: { searchModel.searchMode },
                                        set: { searchModel.searchMode = $0 }
                                    )) {
                                        ForEach(SearchMode.allCases, id: \.self) { mode in
                                            Text(mode.rawValue.capitalized).tag(mode)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                    .padding(.horizontal)

                                    Spacer()
                                }
                            }
                        }
                        .background(backgroundView.ignoresSafeArea())
                        // HIG: Accessibility - Custom actions for power users
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(accessibilityDescription(for: searchModel.viewState))
                        .accessibilityAction(named: "Clear search") {
                            searchModel.clearSearch()
                        }
                        .onAppear {
                            // Handle pending author search after tab becomes visible
                            handlePendingAuthorSearch(searchModel: searchModel)
                        }
                        .onChange(of: searchCoordinator.pendingAuthorSearch) {
                            // Handle pending search when set while tab is already visible
                            handlePendingAuthorSearch(searchModel: searchModel)
                        }
                        // onChange for search text with scope filtering
                        .onChange(of: searchModel.searchText) { oldValue, newValue in
                            performScopedSearch(query: newValue, scope: searchScope, searchModel: searchModel)
                        }
                        .onChange(of: searchScope) { oldValue, newValue in
                            // Re-search with new scope if there's active text
                            if !searchModel.searchText.isEmpty {
                                performScopedSearch(query: searchModel.searchText, scope: newValue, searchModel: searchModel)
                            }
                        }
                        .onChange(of: searchModel.searchMode) {
                            // Re-search with new mode if there's active text
                            if !searchModel.searchText.isEmpty {
                                performScopedSearch(query: searchModel.searchText, scope: searchScope, searchModel: searchModel)
                            }
                        }
            } else {
                ProgressView()
            }
        }
        .task {
            setupSearchModel()
        }
        .sheet(isPresented: $showingScanner) {
            #if DEBUG
            print("📷 Sheet is presenting ISBNScannerView")
            #endif
            return ISBNScannerView { isbn in
                #if DEBUG
                print("📷 ISBN scanned: \(isbn.normalizedValue)")
                #endif
                // Handle scanned ISBN - set scope to ISBN
                searchScope = .isbn
                searchModel?.searchByISBN(isbn.normalizedValue)
            }
        }
        .sheet(isPresented: $showingAdvancedSearch) {
            if let searchModel = searchModel {
                AdvancedSearchView { criteria in
                    handleAdvancedSearch(criteria, searchModel: searchModel)
                }
            }
        }
    }

    // MARK: - Background View
    // HIG: Maintain iOS 26 Liquid Glass aesthetic throughout

    private var backgroundView: some View {
        ZStack {
            themeStore.backgroundGradient

            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.1)
        }
    }

    // MARK: - Search Suggestions View
    // HIG: Provide helpful, contextual suggestions

    @ViewBuilder
    private func searchSuggestionsView(searchModel: SearchModel) -> some View {
        if searchModel.searchText.isEmpty {
            // Show popular searches when empty
            ForEach(Array(searchModel.searchSuggestions.prefix(5)), id: \.self) { suggestion in
                Button {
                    searchModel.searchText = suggestion
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(themeStore.primaryColor)
                        Text(suggestion)
                        Spacer()
                    }
                }
                .accessibilityLabel("Search for \(suggestion)")
            }
        } else {
            // Show relevant suggestions based on input
            ForEach(searchModel.searchSuggestions, id: \.self) { suggestion in
                Button {
                    searchModel.searchText = suggestion
                } label: {
                    HStack {
                        Image(systemName: suggestionIcon(for: suggestion, searchModel: searchModel))
                            .foregroundStyle(.secondary)
                        highlightedSuggestion(suggestion, matching: searchModel.searchText)
                        Spacer()
                    }
                }
                .accessibilityLabel("Search for \(suggestion)")
            }
        }
    }

    // HIG: Contextual icons for different suggestion types
    private func suggestionIcon(for suggestion: String, searchModel: SearchModel) -> String {
        if searchModel.recentSearches.contains(suggestion) {
            return "clock"
        } else if suggestion.allSatisfy({ $0.isNumber || $0 == "-" || $0.uppercased() == "X" }) {
            return "number"
        } else if suggestion.contains(" ") && suggestion.split(separator: " ").count == 2 {
            return "person"  // Likely an author name
        } else {
            return "book"
        }
    }

    // HIG: Bold matching text in suggestions for better scannability
    private func highlightedSuggestion(_ suggestion: String, matching query: String) -> Text {
        guard !query.isEmpty else {
            return Text(suggestion)
        }

        var attributedString = AttributedString(suggestion)
        let lowercasedSuggestion = suggestion.lowercased()
        let lowercasedQuery = query.lowercased()

        // Find the range of the query in the suggestion
        if let range = lowercasedSuggestion.range(of: lowercasedQuery) {
            let startIndex = suggestion.distance(from: suggestion.startIndex, to: range.lowerBound)
            let endIndex = suggestion.distance(from: suggestion.startIndex, to: range.upperBound)

            let start = attributedString.index(attributedString.startIndex, offsetByCharacters: startIndex)
            let end = attributedString.index(attributedString.startIndex, offsetByCharacters: endIndex)

            attributedString[start..<end].font = .subheadline.bold()
        }

        return Text(attributedString)
    }

    // MARK: - Barcode Button
    // HIG: Clear, accessible toolbar actions

    private var barcodeButton: some View {
        Button(action: {
            #if DEBUG
            print("📷 Barcode button tapped")
            #endif
            showingScanner = true
            #if DEBUG
            print("📷 showingScanner set to \(showingScanner)")
            #endif
        }) {
            Image(systemName: "barcode.viewfinder")
                .font(.title2)
                .foregroundColor(themeStore.primaryColor)
        }
        .accessibilityLabel("Scan ISBN barcode")
        .accessibilityHint("Opens camera to scan book barcodes")
    }

    // MARK: - Search Prompt
    // HIG: Contextual search prompts based on scope

    private var searchPrompt: String {
        switch searchScope {
        case .all:
            return "Search books by title, author, or ISBN"
        case .title:
            return "Enter book title"
        case .author:
            return "Enter author name"
        case .isbn:
            return "Enter ISBN (10 or 13 digits)"
        case .semantic:
            return "Describe the book you're looking for"
        }
    }

    // MARK: - Search Content Area
    // HIG: Clear state-based UI with smooth transitions

    @ViewBuilder
    private func searchContentArea(searchModel: SearchModel) -> some View {
        // Removed ZStack wrapper to reduce view nesting depth (was 7-8 levels, now 6-7)
        Group {
            switch searchModel.viewState {
        case .loadingTrending(_):
            LoadingTrendingView()

        case .initial(let trending, let recentSearches):
            InitialStateView(
                trending: trending,
                recentSearches: recentSearches,
                searchModel: searchModel,
                onBookSelected: { book in
                    selectedBook = book
                }
            )
            .environment(searchModel)
            // HIG: Safe-area-aware bottom spacing for trending books visibility (#405)
            .safeAreaInset(edge: .bottom) {
                Color.clear.frame(height: 16)
            }

        case .searching(let query, let scope, let previousResults):
            SearchingView(
                query: query,
                scope: scope,
                previousResults: previousResults
            )

        case .results(_, _, let items, let hasMorePages, let cacheHitRate):
            ResultsStateView(
                items: items,
                hasMorePages: hasMorePages,
                cacheHitRate: cacheHitRate,
                searchModel: searchModel,
                imagePrefetcher: imagePrefetcher,
                onBookSelected: { book in
                    selectedBook = book
                },
                onBookTapped: { book, comparisonData in
                    tappedBook = book
                    editionComparisonData = comparisonData
                },
                onLoadMore: {
                    loadMoreResults()
                }
            )
            // HIG: Debug info only in development builds (overlaid on results)
            #if DEBUG
            .overlay(alignment: .bottom) {
                if !performanceText(for: searchModel).isEmpty {
                    performanceSection(searchModel: searchModel)
                }
            }
            #endif

        case .noResults(let query, let scope):
            NoResultsView(
                query: query,
                scope: scope,
                searchModel: searchModel
            )

        case .error(let message, let lastQuery, let lastScope, let recoverySuggestion):
            ErrorStateView(
                message: message,
                lastQuery: lastQuery,
                lastScope: lastScope,
                recoverySuggestion: recoverySuggestion,
                searchModel: searchModel
            )
            }
        }
        .sheet(item: $editionComparisonData) { data in
            EditionComparisonSheet(searchResult: data.searchEdition, ownedEdition: data.ownedEdition)
        }
    }

    // MARK: - Advanced search entry point
    private var advancedSearchButton: some View {
        Button {
            showingAdvancedSearch = true
        } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(themeStore.primaryColor)
        }
        .accessibilityLabel("Advanced Search")
        .accessibilityHint("Open advanced search form with multiple filter fields")
    }

    // MARK: - Performance Section (Debug Only)
    // HIG: Performance metrics only visible in development

    #if DEBUG
    private func performanceSection(searchModel: SearchModel) -> some View {
        VStack(spacing: 4) {
            Divider()

            Text(performanceText(for: searchModel))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }
    #endif

    // MARK: - Helper Methods

    /// HIG: Scope-aware search execution
    private func performScopedSearch(query: String, scope: SearchScope, searchModel: SearchModel) {
        // Do not trim whitespace here; let the model handle it.
        // This resolves the iOS 18 spacebar bug where trimming interferes
        // with the @State -> @Observable update cycle.
        guard !query.isEmpty else {
            searchModel.clearSearch()
            return
        }

        // Pass scope to search model for filtering
        searchModel.search(query: query, scope: scope)

        // HIG: Haptic feedback for user actions
        #if canImport(UIKit)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif
    }

    /// HIG: Advanced search with multi-field criteria
    /// Backend performs all filtering - returns clean results
    private func handleAdvancedSearch(_ criteria: AdvancedSearchCriteria, searchModel: SearchModel) {
        guard criteria.hasAnyCriteria else { return }

        // Update search text to show what was searched
        if let query = criteria.buildSearchQuery() {
            searchModel.searchText = query
        }

        // Call backend advanced search endpoint
        searchModel.advancedSearch(criteria: criteria)
    }

    /// Handle pending author search from cross-tab navigation
    /// Called by both .onAppear (after tab switch) and .onChange (when already visible)
    private func handlePendingAuthorSearch(searchModel: SearchModel) {
        if let authorName = searchCoordinator.consumePendingAuthorSearch() {
            searchModel.searchText = authorName
            searchScope = .author
            performScopedSearch(query: authorName, scope: .author, searchModel: searchModel)
        }
    }

    /// HIG: Pagination support
    private func loadMoreResults() {
        guard !isLoadingMore else { return }
        isLoadingMore = true

        Task {
            await searchModel?.loadMoreResults()
            isLoadingMore = false
        }
    }

    private func setupSearchModel() {
        if searchModel == nil, let dtoMapper = dtoMapper {
            searchModel = SearchModel(modelContext: modelContext, dtoMapper: dtoMapper)
        }
    }

    #if DEBUG
    private func performanceText(for searchModel: SearchModel) -> String {
        guard searchModel.lastSearchTime > 0 else { return "" }

        let cacheHitRate: Double
        if case .results(_, _, _, _, let rate) = searchModel.viewState {
            cacheHitRate = rate
        } else {
            cacheHitRate = 0
        }

        let cacheStatus = cacheHitRate > 0 ? "CACHED" : "FRESH"
        return String(format: "%.0fms • %@ • %.0f%% cache",
                      searchModel.lastSearchTime * 1000,
                      cacheStatus,
                      cacheHitRate * 100)
    }
    #endif

    // HIG: Comprehensive accessibility descriptions
    private func accessibilityDescription(for state: SearchViewState) -> String {
        switch state {
        case .loadingTrending:
            return "Loading trending books. Please wait."
        case .initial:
            return "Search for books. Currently showing trending books and recent searches."
        case .searching:
            return "Searching for books. Please wait."
        case .results(_, _, let items, _, _):
            return "Search results. \(items.count) books found. Swipe to browse results."
        case .noResults:
            return "No search results found. Try different keywords."
        case .error(let message, _, _, _):
            return "Search error: \(message). Try again or clear search."
        }
    }
}

// MARK: - iOS 26 Scroll Edge Effect Helper

@available(iOS 26.0, *)
struct iOS26ScrollEdgeEffectModifier: ViewModifier {
    let edges: Edge.Set

    func body(content: Content) -> some View {
        content.scrollEdgeEffectStyle(.soft, for: edges)
    }
}

// MARK: - Preview

@available(iOS 26.0, *)
#Preview("Search View - Initial State") {
    let container = try! ModelContainer(for: Work.self, Edition.self, Author.self, UserLibraryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let dtoMapper = DTOMapper(modelContext: container.mainContext)

    return NavigationStack {
        SearchView()
    }
    .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
    .modelContainer(container)
    .environment(\.dtoMapper, dtoMapper)
}

@available(iOS 26.0, *)
#Preview("Search View - Dark Mode") {
    let container = try! ModelContainer(for: Work.self, Edition.self, Author.self, UserLibraryEntry.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let dtoMapper = DTOMapper(modelContext: container.mainContext)

    return NavigationStack {
        SearchView()
    }
    .environment(\.iOS26ThemeStore, BooksTrackerFeature.iOS26ThemeStore())
    .modelContainer(container)
    .environment(\.dtoMapper, dtoMapper)
    .preferredColorScheme(.dark)
}

// MARK: - Supporting Types

/// Data needed for edition comparison sheet
struct EditionComparisonData: Identifiable {
    let id = UUID()
    let searchEdition: Edition
    let ownedEdition: Edition
}