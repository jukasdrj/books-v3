import Foundation

/// V3 API Enrich Request
/// Spec: docs/openapi-v3.json#/components/schemas/EnrichRequest
public struct V3EnrichRequest: Codable, Sendable {
    /// Array of ISBNs to enrich (1-50, supports ISBN-10 and ISBN-13)
    public let isbns: [String]

    /// Generate semantic embeddings for vector search
    public let includeEmbedding: Bool

    // No CodingKeys needed - all properties match the API's camelCase format

    public init(isbns: [String], includeEmbedding: Bool = false) {
        self.isbns = isbns
        self.includeEmbedding = includeEmbedding
    }
}
