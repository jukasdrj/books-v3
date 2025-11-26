import Foundation

/// Response from /v1/search/similar endpoint
/// Returns semantically similar books using vector embeddings
///
/// **Backend Contract:** GET /v1/search/similar?isbn={isbn}&limit={limit}
/// **Rate Limit:** Part of semantic search budget (5 req/min)
/// **Cache:** 24h TTL on backend
///
/// Design: docs/API_CONTRACT.md Section 6.5.3
public struct SimilarBooksResponse: Codable, Sendable {
    /// Array of similar books with similarity scores
    public let results: [SimilarBookItem]
    
    /// The ISBN that was used for similarity search
    public let sourceIsbn: String
    
    /// Total number of similar books found
    public let total: Int
    
    /// Backend processing time in milliseconds
    public let latencyMs: Int?
    
    /// Individual similar book result
    public struct SimilarBookItem: Codable, Sendable, Identifiable {
        public var id: String { isbn }
        
        /// ISBN of the similar book
        public let isbn: String
        
        /// Title of the similar book
        public let title: String
        
        /// Authors of the similar book
        public let authors: [String]
        
        /// Similarity score (0.0 to 1.0, higher is more similar)
        public let similarityScore: Double
        
        /// Cover image URL
        public let coverUrl: String?
        
        private enum CodingKeys: String, CodingKey {
            case isbn
            case title
            case authors
            case similarityScore = "similarity_score"
            case coverUrl = "cover_url"
        }
    }
    
    private enum CodingKeys: String, CodingKey {
        case results
        case sourceIsbn = "source_isbn"
        case total
        case latencyMs = "latency_ms"
    }
}
