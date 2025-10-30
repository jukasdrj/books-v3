import Foundation

/// Canonical DTO Enums
///
/// These mirror TypeScript enums in cloudflare-workers/api-worker/src/types/enums.ts exactly.
/// DO NOT modify without updating TypeScript definitions.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md

// MARK: - Edition Format

public enum DTOEditionFormat: String, Codable, Sendable {
    case hardcover = "Hardcover"
    case paperback = "Paperback"
    case ebook = "E-book"
    case audiobook = "Audiobook"
    case massMarket = "Mass Market"
}

// MARK: - Author Gender

public enum DTOAuthorGender: String, Codable, Sendable {
    case female = "Female"
    case male = "Male"
    case nonBinary = "Non-binary"
    case other = "Other"
    case unknown = "Unknown"
}

// MARK: - Cultural Region

public enum DTOCulturalRegion: String, Codable, Sendable {
    case africa = "Africa"
    case asia = "Asia"
    case europe = "Europe"
    case northAmerica = "North America"
    case southAmerica = "South America"
    case oceania = "Oceania"
    case middleEast = "Middle East"
    case caribbean = "Caribbean"
    case centralAsia = "Central Asia"
    case indigenous = "Indigenous"
    case international = "International"
}

// MARK: - Review Status

public enum DTOReviewStatus: String, Codable, Sendable {
    case verified = "verified"
    case needsReview = "needsReview"
    case userEdited = "userEdited"
}

// MARK: - Data Provider

public enum DTODataProvider: String, Codable, Sendable {
    case googleBooks = "google-books"
    case openlibrary = "openlibrary"
    case isbndb = "isbndb"
    case gemini = "gemini"
}

// MARK: - API Error Code

public enum DTOApiErrorCode: String, Codable, Sendable {
    case invalidISBN = "INVALID_ISBN"
    case invalidQuery = "INVALID_QUERY"
    case providerTimeout = "PROVIDER_TIMEOUT"
    case providerError = "PROVIDER_ERROR"
    case notFound = "NOT_FOUND"
    case rateLimitExceeded = "RATE_LIMIT_EXCEEDED"
    case internalError = "INTERNAL_ERROR"
}
