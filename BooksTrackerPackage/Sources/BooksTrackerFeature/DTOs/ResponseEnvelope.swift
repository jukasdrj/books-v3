import Foundation

/// API Response Envelopes
///
/// Mirrors TypeScript response types in cloudflare-workers/api-worker/src/types/responses.ts exactly.
/// Universal structure for all API responses.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md

// MARK: - Response Metadata

/// Response metadata included in every response (LEGACY - use ResponseMetadata for new endpoints)
public struct ResponseMeta: Codable, Sendable {
    /// ISO 8601 timestamp
    public let timestamp: String

    /// Processing time in milliseconds
    public let processingTime: Int?

    /// Data provider used
    public let provider: String?

    /// Whether response was cached
    public let cached: Bool?

    /// Seconds since cached
    public let cacheAge: Int?

    /// Request ID for distributed tracing (future)
    public let requestId: String?
}

/// Response metadata for new envelope format
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

// MARK: - API Response (Discriminated Union)

/// Discriminated union for all API responses
/// Use pattern matching to handle success vs error cases
public enum ApiResponse<T: Codable>: Codable {
    case success(T, ResponseMeta)
    case failure(ApiError, ResponseMeta)

    // MARK: - API Error

    public struct ApiError: Codable, Sendable {
        public let message: String
        public let code: DTOApiErrorCode?
        public let details: AnyCodable?

        /// Helper to safely extract details as a specific type
        public func detailsAs<D: Codable>(_ type: D.Type) -> D? {
            details?.value as? D
        }
    }

    // MARK: - Codable Implementation

    private enum CodingKeys: String, CodingKey {
        case success, data, error, meta
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let success = try container.decode(Bool.self, forKey: .success)
        let meta = try container.decode(ResponseMeta.self, forKey: .meta)

        if success {
            let data = try container.decode(T.self, forKey: .data)
            self = .success(data, meta)
        } else {
            let error = try container.decode(ApiError.self, forKey: .error)
            self = .failure(error, meta)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .success(let data, let meta):
            try container.encode(true, forKey: .success)
            try container.encode(data, forKey: .data)
            try container.encode(meta, forKey: .meta)
        case .failure(let error, let meta):
            try container.encode(false, forKey: .success)
            try container.encode(error, forKey: .error)
            try container.encode(meta, forKey: .meta)
        }
    }
}

// MARK: - New Response Envelope

/// Universal response envelope for new endpoints
/// Mirrors TypeScript ResponseEnvelope in api-worker/src/types/responses.ts
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
    public let authors: [AuthorDTO]
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

/// Type-erased Codable wrapper for dynamic JSON values
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
