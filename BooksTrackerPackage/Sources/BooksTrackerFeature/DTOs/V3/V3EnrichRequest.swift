import Foundation

/// V3 API Enrich Request
/// Spec: docs/openapi-v3.json#/components/schemas/EnrichRequest
public struct V3EnrichRequest: Codable, Sendable {
    /// Array of ISBNs to enrich (supports ISBN-10 and ISBN-13)
    /// - Sync mode (async=false): 1-50 ISBNs
    /// - Async mode (async=true): 1-500 ISBNs
    public let isbns: [String]

    /// Generate semantic embeddings for vector search
    public let includeEmbedding: Bool

    /// Use async mode for batches >50 ISBNs (up to 500)
    /// Async mode returns a jobId for SSE progress tracking
    public let async: Bool?

    private enum CodingKeys: String, CodingKey {
        case isbns, includeEmbedding
        case async
    }

    public init(isbns: [String], includeEmbedding: Bool = false, async: Bool? = nil) {
        self.isbns = isbns
        self.includeEmbedding = includeEmbedding
        self.async = async
    }
}
