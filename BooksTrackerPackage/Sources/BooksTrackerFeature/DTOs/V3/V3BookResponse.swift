import Foundation

/// V3 API Book Response (single book lookup)
/// Spec: docs/openapi-v3.json#/components/schemas/BookResponse
public struct V3BookResponse: Codable, Sendable {
    /// Success discriminator (always true for successful responses)
    public let success: Bool

    /// Book data
    public let data: V3Book

    /// Response metadata
    public let metadata: V3ResponseMetadata

    /// HATEOAS links for resource discoverability
    public let links: [String: V3Link]?

    enum CodingKeys: String, CodingKey {
        case success, data, metadata
        case links = "_links"
    }
}
