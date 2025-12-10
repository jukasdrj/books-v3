import Foundation

/// V3 API Search Response
/// Spec: docs/openapi-v3.json#/components/schemas/SearchResponse
public struct V3SearchResponse: Codable, Sendable {
    /// Success discriminator (always true for successful responses)
    public let success: Bool

    /// Search result data
    public let data: V3SearchData

    /// Response metadata
    public let metadata: V3ResponseMetadata

    /// HATEOAS links for resource discoverability
    public let links: [String: V3Link]?

    enum CodingKeys: String, CodingKey {
        case success, data, metadata
        case links = "_links"
    }
}

/// Search result data
public struct V3SearchData: Codable, Sendable {
    /// Array of book results
    public let books: [V3Book]

    /// Total number of results
    public let total: Int

    /// Original search query
    public let query: V3SearchQuery

    /// Pagination information
    public let pagination: V3Pagination

    // No CodingKeys needed - all properties match the API's camelCase format
}

/// Search query parameters
public struct V3SearchQuery: Codable, Sendable {
    /// Original search query
    public let q: String

    /// Search mode (currently only "text" supported)
    public let mode: String

    // No CodingKeys needed - all properties match the API's camelCase format
}

/// Pagination information
public struct V3Pagination: Codable, Sendable {
    /// Pagination type (currently "offset", cursor-based coming soon)
    public let type: String

    /// Current page number
    public let page: Int

    /// Results per page
    public let limit: Int

    /// Total number of pages
    public let totalPages: Int

    /// Whether there are more pages
    public let hasNext: Bool

    /// Whether there are previous pages
    public let hasPrev: Bool

    // No CodingKeys needed - all properties match the API's camelCase format
}
