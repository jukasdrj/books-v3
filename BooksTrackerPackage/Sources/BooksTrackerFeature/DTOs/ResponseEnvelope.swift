import Foundation

/// API Response Envelopes
///
/// Mirrors TypeScript response types in cloudflare-workers/api-worker/src/types/responses.ts exactly.
/// Universal structure for all API responses.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md

// MARK: - Response Metadata

/// Response metadata included in every response
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
