import Foundation

/// V3 API Book Model
/// Unified book representation from Alexandria API
/// Spec: docs/openapi-v3.json#/components/schemas/Book
public struct V3Book: Codable, Sendable {
    public let isbn: String
    public let isbn10: String?
    public let title: String
    public let subtitle: String?
    public let authors: [String]  // Simple string array, NOT objects
    public let publisher: String?
    public let publishedDate: String?
    public let description: String?
    public let pageCount: Int?
    public let categories: [String]?
    public let language: String?
    public let coverUrl: String?
    public let thumbnailUrl: String?
    public let workKey: String?
    public let editionKey: String?
    public let provider: String
    public let quality: Double

    // No CodingKeys needed - all properties match the API's camelCase format
}

/// Enriched book with vectorization status
/// Spec: docs/openapi-v3.json#/components/schemas/EnrichedBook
public struct V3EnrichedBook: Codable, Sendable {
    // All Book fields
    public let isbn: String
    public let isbn10: String?
    public let title: String
    public let subtitle: String?
    public let authors: [String]
    public let publisher: String?
    public let publishedDate: String?
    public let description: String?
    public let pageCount: Int?
    public let categories: [String]?
    public let language: String?
    public let coverUrl: String?
    public let thumbnailUrl: String?
    public let workKey: String?
    public let editionKey: String?
    public let provider: String
    public let quality: Double

    // Enrichment-specific field
    public let vectorized: Bool

    // No CodingKeys needed - all properties match the API's camelCase format
}
