import Foundation

// MARK: - V2 Search API Response DTOs

/// Response from GET /api/v2/search endpoint
/// Supports both text and semantic search modes
public struct SearchV2Response: Codable, Sendable {
    public let results: [SearchV2Result]
    public let total: Int
    public let mode: String
    public let query: String
    public let latencyMs: Int?
    
    enum CodingKeys: String, CodingKey {
        case results
        case total
        case mode
        case query
        case latencyMs = "latency_ms"
    }
}

/// Individual search result from V2 API
public struct SearchV2Result: Codable, Sendable {
    public let id: String?
    public let isbn: String
    public let title: String
    public let authors: [String]
    public let coverUrl: String?
    public let relevanceScore: Double
    public let matchType: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case isbn
        case title
        case authors
        case coverUrl = "cover_url"
        case relevanceScore = "relevance_score"
        case matchType = "match_type"
    }
}

/// Error response from V2 API
public struct SearchV2ErrorResponse: Codable, Sendable {
    public let error: SearchV2Error
}

public struct SearchV2Error: Codable, Sendable {
    public let code: String
    public let message: String
}
