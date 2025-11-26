import Foundation
import SwiftData

/// Cache for similar books API responses (24h TTL)
/// Stores results from /v1/search/similar to reduce API calls
///
/// **Cache Strategy:**
/// - 24 hour TTL (aligns with backend cache)
/// - Keyed by source ISBN
/// - Automatically cleaned up when expired
@Model
public final class SimilarBooksCache {
    /// Source ISBN used for similarity search
    @Attribute(.unique) var sourceIsbn: String
    
    /// Cached similar book ISBNs (ordered by similarity score)
    var similarIsbns: [String]
    
    /// Cached book titles (same order as ISBNs)
    var titles: [String]
    
    /// Cached author lists (same order as ISBNs)
    var authorLists: [[String]]
    
    /// Similarity scores (same order as ISBNs)
    var similarityScores: [Double]
    
    /// Cover URLs (same order as ISBNs, optional)
    var coverUrls: [String?]
    
    /// When this cache entry was created
    var createdAt: Date
    
    /// When this cache entry expires (createdAt + 24h)
    var expiresAt: Date
    
    public init(sourceIsbn: String, response: SimilarBooksResponse) {
        self.sourceIsbn = sourceIsbn
        self.similarIsbns = response.results.map { $0.isbn }
        self.titles = response.results.map { $0.title }
        self.authorLists = response.results.map { $0.authors }
        self.similarityScores = response.results.map { $0.similarityScore }
        self.coverUrls = response.results.map { $0.coverUrl }
        self.createdAt = Date()
        self.expiresAt = Date().addingTimeInterval(24 * 60 * 60) // 24 hours
    }
    
    /// Check if this cache entry is still valid
    var isValid: Bool {
        Date() < expiresAt
    }
    
    /// Convert cached data back to SimilarBooksResponse format
    func toResponse() -> SimilarBooksResponse {
        let items = zip(similarIsbns, zip(titles, zip(authorLists, zip(similarityScores, coverUrls)))).map { isbn, rest in
            let (title, rest2) = rest
            let (authors, rest3) = rest2
            let (score, coverUrl) = rest3
            
            return SimilarBooksResponse.SimilarBookItem(
                isbn: isbn,
                title: title,
                authors: authors,
                similarityScore: score,
                coverUrl: coverUrl
            )
        }
        
        return SimilarBooksResponse(
            results: items,
            sourceIsbn: sourceIsbn,
            total: items.count,
            latencyMs: nil // Cache hits don't have latency
        )
    }
}
