import SwiftUI
import SwiftData

// MARK: - Optimized Library Data Source

/// Performance-optimized library data source with intelligent caching
/// Caches filtered results for 5 seconds to avoid redundant computations
@MainActor
@Observable
class OptimizedLibraryDataSource {
    private var cachedWorks: [Work] = []
    private var lastCacheUpdate: Date = .distantPast
    private let cacheValidityDuration: TimeInterval = 5.0
    
    func getFilteredWorks(
        from works: [Work], 
        searchText: String,
        forceRefresh: Bool = false
    ) -> [Work] {
        let now = Date()
        
        // Use cache if valid and not forced refresh
        if !forceRefresh && 
           now.timeIntervalSince(lastCacheUpdate) < cacheValidityDuration &&
           !cachedWorks.isEmpty {
            return filterWorks(cachedWorks, searchText: searchText)
        }
        
        // Update cache
        cachedWorks = works
        lastCacheUpdate = now
        
        return filterWorks(cachedWorks, searchText: searchText)
    }
    
    private func filterWorks(_ works: [Work], searchText: String) -> [Work] {
        guard !searchText.isEmpty else { return works }
        
        return works.filter { work in
            work.title.localizedCaseInsensitiveContains(searchText) ||
            work.authorNames.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    func invalidateCache() {
        lastCacheUpdate = .distantPast
    }
}
