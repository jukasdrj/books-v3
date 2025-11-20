import Foundation

/// API Response Envelopes
///
/// Mirrors TypeScript response types in cloudflare-workers/api-worker/src/types/responses.ts exactly.
/// Universal structure for all API responses.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md

// MARK: - Response Metadata

/// Response metadata for API responses (Section 4.2)
/// Mirrors TypeScript ResponseMetadata in api-worker/src/types/responses.ts
public struct ResponseMetadata: Codable, Sendable {
    /// ISO 8601 timestamp
    public let timestamp: String

    /// Request tracing ID for distributed systems
    public let traceId: String?

    /// Processing time in milliseconds
    public let processingTime: Int?

    /// Data provider used
    public let provider: String?

    /// Whether response was cached
    public let cached: Bool?
}

// MARK: - Response Envelope

/// Universal response envelope for all API endpoints (Section 4.2)
/// Mirrors TypeScript ResponseEnvelope in api-worker/src/types/responses.ts exactly
public struct ResponseEnvelope<T: Codable>: Codable {
    /// Response payload (null on error)
    public let data: T?

    /// Response metadata (always present)
    public let metadata: ResponseMetadata

    /// Error information (present on failure)
    public let error: ApiErrorInfo?

    public struct ApiErrorInfo: Codable, Sendable {
        public let message: String
        public let code: String?
        public let details: AnyCodable?
    }
}

// MARK: - Domain-Specific Response Types

/// Book search response
/// Used by: /v1/search/title, /v1/search/isbn, /v1/search/advanced
public struct BookSearchResponse: Codable, Sendable {
    public let works: [WorkDTO]
    public let editions: [EditionDTO]
    public let authors: [AuthorDTO]

    /// Number of books found (0 for no results, N for N books)
    /// Disambiguates "no results found" (0) from errors (v2.4 - Issue #169)
    public let resultCount: Int

    /// ISO 8601 timestamp when results expire from KV cache
    /// 24 hours after job completion (v2.4 - Issue #169)
    public let expiresAt: String?

    /// Reserved for future pagination support
    public let totalResults: Int?
}

/// Enrichment job response
/// Used by: /v1/api/enrichment/start
public struct EnrichmentJobResponse: Codable, Sendable {
    public let jobId: String
    public let queuedCount: Int
    public let estimatedDuration: Int?
    public let websocketUrl: String
}

/// Bookshelf scan response
/// Used by: /v1/api/scan-bookshelf, /v1/api/scan-bookshelf/batch
public struct BookshelfScanResponse: Codable, Sendable {
    public let jobId: String
    public let detectedBooks: [DetectedBook]
    public let websocketUrl: String

    public struct DetectedBook: Codable, Sendable {
        public let work: WorkDTO
        public let edition: EditionDTO
        public let confidence: Double
    }
}

// MARK: - ResponseEnvelope Contract Documentation

/// # ResponseEnvelope Contract
///
/// The ResponseEnvelope provides a standardized wrapper for all API responses, enabling
/// consistent error handling and type-safe response parsing across the entire application.
///
/// ## Type Safety Contract
///
/// When decoding a ResponseEnvelope<T>, the following guarantees apply:
///
/// ### Success Case (.success)
/// - `data` is guaranteed to be non-nil and of type T
/// - `error` is guaranteed to be nil
/// - `meta` contains response metadata (timestamp, processing time, etc.)
///
/// ### Failure Case (.failure)
/// - `data` is guaranteed to be nil
/// - `error` is guaranteed to be non-nil with a message and optional code
/// - `meta` contains response metadata
///
/// ## Usage Pattern
///
/// ```swift
/// let response = try decoder.decode(ApiResponse<BookSearchResponse>.self, from: data)
///
/// switch response {
/// case .success(let searchData, let meta):
///     // searchData is BookSearchResponse, guaranteed non-nil
///     print("Found \(searchData.works.count) works")
///
/// case .failure(let error, let meta):
///     // error contains message and optional code
///     print("Error: \(error.message), Code: \(error.code ?? "none")")
/// }
/// ```
///
/// ## Error Handling
///
/// All errors from the API include:
/// - `message`: Human-readable error description
/// - `code`: Optional DTOApiErrorCode for programmatic handling
/// - `details`: Optional additional context (use `detailsAs(_:)` for type-safe extraction)
///
/// ## Backend Contract
///
/// The TypeScript backend must ensure:
/// 1. Success responses have non-null `data` field
/// 2. Error responses have null `data` field and non-null `error` field
/// 3. Both cases include `meta` with at minimum a timestamp
///
/// This contract is enforced by the discriminated union pattern in both TypeScript
/// and Swift, preventing invalid response states at compile time.

// MARK: - AnyCodable Helper

// Note: AnyCodable is defined in WebSocketMessages.swift (unified schema)
// Import that type instead of duplicating here
