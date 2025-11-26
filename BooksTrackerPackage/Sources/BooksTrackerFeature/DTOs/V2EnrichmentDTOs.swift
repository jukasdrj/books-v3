import Foundation

// MARK: - V2 Enrichment Request

/// Request payload for V2 synchronous book enrichment
/// POST /api/v2/books/enrich
struct V2EnrichmentRequest: Codable, Sendable {
    /// ISBN-10 or ISBN-13 barcode
    let barcode: String
    
    /// Provider preference: "google", "openlibrary", or "auto" (optional)
    let preferProvider: String?
    
    /// Idempotency key for safe retries (optional)
    let idempotencyKey: String?
    
    enum CodingKeys: String, CodingKey {
        case barcode
        case preferProvider = "prefer_provider"
        case idempotencyKey = "idempotency_key"
    }
}

// MARK: - V2 Enrichment Response

/// Success response from V2 book enrichment endpoint
struct V2EnrichmentResponse: Codable, Sendable {
    let isbn: String
    let title: String
    let authors: [String]
    let publisher: String?
    let publishedDate: String?
    let pageCount: Int?
    let coverUrl: String?
    let description: String?
    let categories: [String]?
    let language: String?
    let provider: String
    let enrichedAt: String
    
    enum CodingKeys: String, CodingKey {
        case isbn
        case title
        case authors
        case publisher
        case publishedDate = "published_date"
        case pageCount = "page_count"
        case coverUrl = "cover_url"
        case description
        case categories
        case language
        case provider
        case enrichedAt = "enriched_at"
    }
}

// MARK: - V2 Enrichment Error Response

/// Error response from V2 book enrichment endpoint
struct V2EnrichmentErrorResponse: Codable, Sendable {
    /// Error code (e.g., "BOOK_NOT_FOUND", "RATE_LIMIT_EXCEEDED")
    let code: String
    
    /// Human-readable error message
    let message: String
    
    /// Providers that were checked (for BOOK_NOT_FOUND errors)
    let providersChecked: [String]?
    
    enum CodingKeys: String, CodingKey {
        case code = "error"
        case message
        case providersChecked = "providers_checked"
    }
}

// MARK: - Rate Limit Error Response

/// Rate limit error response (429 Too Many Requests)
struct V2RateLimitErrorResponse: Codable, Sendable {
    let code: String
    let message: String
    let retryAfter: Int?
    let limit: Int?
    let remaining: Int?
    let resetAt: String?
    
    enum CodingKeys: String, CodingKey {
        case code = "error"
        case message
        case retryAfter = "retry_after"
        case limit
        case remaining
        case resetAt = "reset_at"
    }
}
