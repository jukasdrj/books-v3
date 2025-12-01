import Foundation

/// V2 Search Results DTO
/// Mirrors the V2 search API response structure
/// Used by: /api/v2/search
public struct SearchResults: Codable, Sendable {
    /// Array of books matching the search query
    public let results: [BookDTO]

    /// Total number of results available (for pagination)
    public let total: Int

    /// Search mode used: text, semantic, or hybrid
    public let mode: SearchMode

    /// Original search query
    public let query: String

    public init(results: [BookDTO], total: Int, mode: SearchMode, query: String) {
        self.results = results
        self.total = total
        self.mode = mode
        self.query = query
    }
}
