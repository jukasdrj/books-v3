import Foundation

/// HATEOAS Link for resource discoverability
/// Spec: docs/openapi-v3.json#/components/schemas/Link
public struct V3Link: Codable, Sendable {
    /// Link URL
    public let href: String

    /// Link relation type (e.g., "self", "next", "prev")
    public let rel: String

    /// HTTP method for this link
    public let method: String?

    enum CodingKeys: String, CodingKey {
        case href, rel, method
    }
}
