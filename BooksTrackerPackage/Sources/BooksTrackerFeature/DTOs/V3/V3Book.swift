import Foundation

/// V3 API Author Model (AuthorReference from OpenAPI spec)
/// Author representation from Alexandria API - can be string or enriched object
/// Spec: docs/v3-openapi-baseline.json#/components/schemas/AuthorReference
public struct V3Author: Codable, Sendable {
    public let name: String
    public let key: String?
    public let openlibrary: String?
    public let bio: String?
    public let gender: String?
    public let nationality: String?
    public let birthYear: Int?
    public let deathYear: Int?
    public let wikidataId: String?
    public let image: String?

    enum CodingKeys: String, CodingKey {
        case name
        case key
        case openlibrary
        case bio
        case gender
        case nationality
        case birthYear = "birth_year"
        case deathYear = "death_year"
        case wikidataId = "wikidata_id"
        case image
    }
}

/// V3 API Book Model
/// Unified book representation from Alexandria API
/// Spec: docs/archive/openapi-v3.json#/components/schemas/Book
public struct V3Book: Codable, Sendable {
    public let isbn: String
    public let isbn10: String?
    public let title: String
    public let subtitle: String?
    public let authors: [V3Author]  // Author objects with name, key, etc.
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

    // Computed property for author names as strings
    public var authorNames: [String] {
        authors.map { $0.name }
    }

    // No CodingKeys needed - all properties match the API's camelCase format
}

/// Enriched book with vectorization status
/// Spec: docs/archive/openapi-v3.json#/components/schemas/EnrichedBook
public struct V3EnrichedBook: Codable, Sendable {
    // All Book fields
    public let isbn: String
    public let isbn10: String?
    public let title: String
    public let subtitle: String?
    public let authors: [V3Author]  // Author objects with name, key, etc.
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

    // Computed property for author names as strings
    public var authorNames: [String] {
        authors.map { $0.name }
    }

    // No CodingKeys needed - all properties match the API's camelCase format
}
