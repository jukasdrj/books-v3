import Foundation

/// Weekly Recommendations Response DTO
///
/// Mirrors the API contract for GET /api/v2/recommendations/weekly
/// See: docs/API_CONTRACT.md Section 6.5.4
///
/// Backend contract:
/// - Generated every Sunday at midnight UTC (cron job)
/// - Cached in KV (1-week TTL)
/// - Non-personalized (global picks)
/// - No auth required
public struct WeeklyRecommendationsDTO: Codable, Sendable, Equatable {
    /// Week identifier (ISO 8601 date format: "YYYY-MM-DD")
    public let week_of: String
    
    /// Array of recommended books
    public let books: [RecommendedBookDTO]
    
    /// Timestamp when recommendations were generated (ISO 8601)
    public let generated_at: String
    
    /// Timestamp when next refresh will occur (ISO 8601)
    public let next_refresh: String
    
    public init(
        week_of: String,
        books: [RecommendedBookDTO],
        generated_at: String,
        next_refresh: String
    ) {
        self.week_of = week_of
        self.books = books
        self.generated_at = generated_at
        self.next_refresh = next_refresh
    }
}

/// Individual recommended book within weekly recommendations
public struct RecommendedBookDTO: Codable, Sendable, Equatable, Identifiable {
    /// ISBN-13 identifier
    public let isbn: String
    
    /// Book title
    public let title: String
    
    /// Author names
    public let authors: [String]
    
    /// Cover image URL
    public let cover_url: String?
    
    /// AI-generated reason why this book was recommended
    public let reason: String
    
    /// Computed ID for SwiftUI Identifiable conformance
    public var id: String { isbn }
    
    public init(
        isbn: String,
        title: String,
        authors: [String],
        cover_url: String?,
        reason: String
    ) {
        self.isbn = isbn
        self.title = title
        self.authors = authors
        self.cover_url = cover_url
        self.reason = reason
    }
}
