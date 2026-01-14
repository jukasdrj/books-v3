import Foundation

/// V3 API Enrich Response
/// Spec: docs/archive/openapi-v3.json#/components/schemas/EnrichResponse
public struct V3EnrichResponse: Codable, Sendable {
    /// Success discriminator (always true for successful responses)
    public let success: Bool

    /// Enrichment result data
    public let data: V3EnrichData

    /// Response metadata
    public let metadata: V3ResponseMetadata

    // No CodingKeys needed - all properties match the API's camelCase format
}

/// Enrichment result data
public struct V3EnrichData: Codable, Sendable {
    /// Enriched books (may be fewer than requested if some not found)
    public let books: [V3EnrichedBook]

    /// Number of ISBNs requested
    public let requested: Int

    /// Number of books found
    public let found: Int

    /// ISBNs that were not found
    public let notFound: [String]?

    // No CodingKeys needed - all properties match the API's camelCase format
}
