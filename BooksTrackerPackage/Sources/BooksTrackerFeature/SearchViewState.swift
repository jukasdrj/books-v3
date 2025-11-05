// BooksTrackerPackage/Sources/BooksTrackerFeature/SearchViewState.swift
import Foundation

/// Comprehensive state enum for search feature
/// Makes impossible states impossible by design
@MainActor
public enum SearchViewState: Equatable, Sendable {
    /// Loading trending books on first launch
    case loadingTrending(recentSearches: [String])

    /// Initial empty state with discovery content
    case initial(trending: [SearchResult], recentSearches: [String])

    /// Actively searching - preserve previous results for smooth UX
    case searching(query: String, scope: SearchScope, previousResults: [SearchResult])

    /// Successful search with results
    case results(
        query: String,
        scope: SearchScope,
        items: [SearchResult],
        hasMorePages: Bool,
        cacheHitRate: Double
    )

    /// No results found
    case noResults(query: String, scope: SearchScope)

    /// Error state with retry context
    case error(
        message: String,
        lastQuery: String,
        lastScope: SearchScope,
        recoverySuggestion: String
    )

    // MARK: - Computed Properties

    /// Extract current results regardless of state
    public var currentResults: [SearchResult] {
        switch self {
        case .results(_, _, let items, _, _):
            return items
        case .searching(_, _, let previousResults):
            return previousResults
        default:
            return []
        }
    }

    /// Check if actively loading
    public var isSearching: Bool {
        if case .searching = self {
            return true
        }
        return false
    }

    /// Get current query if available
    public var currentQuery: String? {
        switch self {
        case .searching(let query, _, _),
             .results(let query, _, _, _, _),
             .noResults(let query, _),
             .error(_, let query, _, _):
            return query
        case .loadingTrending, .initial:
            return nil
        }
    }

    /// Get current scope if available
    public var currentScope: SearchScope? {
        switch self {
        case .searching(_, let scope, _),
             .results(_, let scope, _, _, _),
             .noResults(_, let scope),
             .error(_, _, let scope, _):
            return scope
        case .loadingTrending, .initial:
            return nil
        }
    }
}
