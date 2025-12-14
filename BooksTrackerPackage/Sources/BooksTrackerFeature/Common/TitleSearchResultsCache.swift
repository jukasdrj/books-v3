import Foundation

/// Cache for title-based search enrichment results
/// Used to pass enrichment data from EnrichmentAPIClient to EnrichmentQueue
/// when ISBN-based batch enrichment is not available.
///
/// **Lifecycle:**
/// 1. `EnrichmentAPIClient.enrichByTitleSearch()` stores results after searching
/// 2. `EnrichmentQueue` detects `title-search:{jobId}` token and retrieves results
/// 3. Results are removed after retrieval to prevent memory growth
actor TitleSearchResultsCache {
    static let shared = TitleSearchResultsCache()

    private var cache: [String: [EnrichedBookPayload]] = [:]

    private init() {}

    /// Store enrichment results for a job
    /// - Parameters:
    ///   - jobId: Unique job identifier
    ///   - results: Array of enriched book payloads from title search
    func store(jobId: String, results: [EnrichedBookPayload]) {
        cache[jobId] = results
        #if DEBUG
        print("[TitleSearchResultsCache] 📥 Stored \(results.count) results for job: \(jobId)")
        #endif
    }

    /// Retrieve and remove enrichment results for a job
    /// - Parameter jobId: Unique job identifier
    /// - Returns: Array of enriched book payloads, or empty array if not found
    func retrieve(jobId: String) -> [EnrichedBookPayload] {
        guard let results = cache.removeValue(forKey: jobId) else {
            #if DEBUG
            print("[TitleSearchResultsCache] ⚠️ No results found for job: \(jobId)")
            #endif
            return []
        }

        #if DEBUG
        print("[TitleSearchResultsCache] 📤 Retrieved \(results.count) results for job: \(jobId)")
        #endif

        return results
    }

    /// Check if results exist for a job (without removing them)
    /// - Parameter jobId: Unique job identifier
    /// - Returns: True if results are cached
    func hasResults(for jobId: String) -> Bool {
        cache[jobId] != nil
    }

    /// Clear all cached results (for cleanup/reset)
    func clearAll() {
        cache.removeAll()
        #if DEBUG
        print("[TitleSearchResultsCache] 🧹 Cache cleared")
        #endif
    }
}
