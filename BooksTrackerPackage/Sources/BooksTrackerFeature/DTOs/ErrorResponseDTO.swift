import Foundation

// MARK: - Error Response DTO (API v3.1)

/// Standard error response structure from API v3.1
/// Matches API contract section 3.2 - Error Response
/// Reference: docs/API_CONTRACT.md, docs/openapi.yaml
public struct ErrorResponseDTO: Codable, Sendable {
    public let success: Bool
    public let error: ErrorDetail

    /// Detailed error information from circuit breaker, rate limiter, etc.
    public struct ErrorDetail: Codable, Sendable {
        /// Machine-readable error code
        /// Examples: "NOT_FOUND", "CIRCUIT_OPEN", "RATE_LIMIT_EXCEEDED", "API_ERROR"
        public let code: String

        /// Human-readable error message
        public let message: String

        /// Additional error context (optional)
        public let details: AnyCodable?

        /// Whether the operation can be retried
        public let retryable: Bool?

        /// Milliseconds until retry is allowed (for rate limiting and circuit breaker)
        public let retryAfterMs: Int?

        /// Provider that triggered the error (for circuit breaker)
        public let provider: String?

        enum CodingKeys: String, CodingKey {
            case code
            case message
            case details
            case retryable
            case retryAfterMs
            case provider
        }
    }
}

// MARK: - AnyCodable Reference

// Note: AnyCodable is defined in DTOs/WebSocketMessages.swift
// Already available throughout the codebase
