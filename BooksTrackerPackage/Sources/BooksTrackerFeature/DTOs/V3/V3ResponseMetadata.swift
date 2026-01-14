import Foundation

/// V3 API Response Metadata
/// Spec: docs/archive/openapi-v3.json#/components/schemas/ResponseMetadata
public struct V3ResponseMetadata: Codable, Sendable {
    /// ISO 8601 timestamp (required)
    public let timestamp: String

    /// Request correlation ID (X-Request-ID header)
    public let requestId: String?

    /// Data source provider
    public let source: String?

    /// Whether response was served from cache
    public let cached: Bool?

    /// Processing time in milliseconds
    public let processingTimeMs: Int?

    // No CodingKeys needed - all properties match the API's camelCase format
}
