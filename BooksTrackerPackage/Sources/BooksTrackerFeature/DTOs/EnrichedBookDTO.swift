import Foundation

/// Response DTO for V2 synchronous book enrichment.
/// Contains enriched metadata from external book data providers.
/// Mirrors backend EnrichResponse from bendv3/src/handlers/v2/enrich.ts
public struct EnrichedBookDTO: Codable, Sendable {
    public let isbn: String
    public let title: String
    public let authors: [String]
    public let publisher: String?
    public let publishedDate: String?
    public let description: String?
    public let pageCount: Int?
    public let categories: [String]?      // Added: Subject categories/genres from Alexandria
    public let coverUrl: String?
    public let provider: String?
    public let enrichedAt: String?
    public let vectorized: Bool?          // Added: Whether semantic embedding was generated
}

/// Error response DTO for V2 enrichment failures.
/// NOTE: This struct is rarely used directly - errors are now wrapped in ResponseEnvelope
public struct EnrichmentErrorDTO: Codable, Sendable {
    public let error: ErrorDetails
}

/// Details about an enrichment error including provider information.
/// NOTE: This is legacy - modern errors use ResponseEnvelope.ApiErrorInfo
public struct ErrorDetails: Codable, Sendable {
    public let code: String
    public let message: String
    public let providersChecked: [String]
}

/// Request payload for V2 synchronous book enrichment.
/// Sent to POST /api/v2/books/enrich
struct EnrichBookV2Request: Codable, Sendable {
    let barcode: String          // ISBN-10 or ISBN-13
    let preferProvider: String    // Provider preference hint (default: "auto")
    let idempotencyKey: String   // Stable key for retry safety
}
