import Foundation

/// Observable coordinator for cross-tab navigation to Search view
/// Replaces timing-dependent notification pattern with observable state
@Observable
@MainActor
public final class SearchCoordinator {
    /// Author name awaiting search after tab switch completes
    public private(set) var pendingAuthorSearch: String?

    public init() {}

    /// Set pending author search (called from ContentView when author tapped)
    public func setPendingAuthorSearch(_ authorName: String) {
        pendingAuthorSearch = authorName
    }

    /// Consume and clear pending search (called from SearchView.onAppear)
    /// - Returns: Author name to search for, or nil if no pending search
    public func consumePendingAuthorSearch() -> String? {
        defer { pendingAuthorSearch = nil }
        return pendingAuthorSearch
    }
}
