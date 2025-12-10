import Foundation

/// V3 API Error Response (RFC 9457 Problem Details)
/// Spec: docs/openapi-v3.json#/components/schemas/ErrorResponse
public struct V3ErrorResponse: Codable, Sendable {
    /// Success discriminator (always false for error responses)
    public let success: Bool

    /// URI reference identifying the problem type (RFC 9457)
    public let type: String

    /// Short, human-readable summary of the problem type
    public let title: String

    /// HTTP status code
    public let status: Int

    /// Human-readable explanation specific to this occurrence
    public let detail: String?

    /// URI reference identifying this specific occurrence
    public let instance: String?

    /// Machine-readable error code (BooksTrack-specific)
    public let code: V3ErrorCode

    /// Whether the request can be retried
    public let retryable: Bool?

    /// Milliseconds to wait before retry
    public let retryAfterMs: Int?

    /// Field-level validation errors
    public let errors: [V3FieldError]?

    /// Error metadata
    public let metadata: V3ErrorMetadata

    // No CodingKeys needed - all properties match the API's camelCase format
}

/// Machine-readable error codes
/// Spec: docs/openapi-v3.json#/components/schemas/ErrorResponse/properties/code
public enum V3ErrorCode: String, Codable, Sendable {
    case missingParameter = "MISSING_PARAMETER"
    case invalidRequest = "INVALID_REQUEST"
    case invalidIsbn = "INVALID_ISBN"
    case invalidQuery = "INVALID_QUERY"
    case invalidFile = "INVALID_FILE"
    case fileTooLarge = "FILE_TOO_LARGE"
    case batchTooLarge = "BATCH_TOO_LARGE"
    case emptyBatch = "EMPTY_BATCH"
    case notFound = "NOT_FOUND"
    case unauthorized = "UNAUTHORIZED"
    case forbidden = "FORBIDDEN"
    case clientDisconnected = "CLIENT_DISCONNECTED"
    case rateLimitExceeded = "RATE_LIMIT_EXCEEDED"
    case circuitOpen = "CIRCUIT_OPEN"
    case providerError = "PROVIDER_ERROR"
    case providerTimeout = "PROVIDER_TIMEOUT"
    case cacheError = "CACHE_ERROR"
    case internalError = "INTERNAL_ERROR"
    case apiError = "API_ERROR"
    case networkError = "NETWORK_ERROR"
    case timeout = "TIMEOUT"
    case featureNotAvailable = "FEATURE_NOT_AVAILABLE"
}

/// Field-level validation error
/// Spec: docs/openapi-v3.json#/components/schemas/FieldError
public struct V3FieldError: Codable, Sendable {
    /// Field path (e.g., "isbns[0]")
    public let field: String

    /// Validation error message
    public let message: String

    /// Validation error code
    public let code: String?

    // No CodingKeys needed - all properties match the API's camelCase format
}

/// Error metadata
public struct V3ErrorMetadata: Codable, Sendable {
    /// ISO 8601 timestamp
    public let timestamp: String

    /// Request correlation ID
    public let requestId: String?

    // No CodingKeys needed - all properties match the API's camelCase format
}
