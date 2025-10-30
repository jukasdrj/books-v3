import Foundation

/// EditionDTO - Physical/digital manifestation of a Work
///
/// Mirrors TypeScript EditionDTO in cloudflare-workers/api-worker/src/types/canonical.ts exactly.
/// Corresponds to SwiftData Edition model.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md
public struct EditionDTO: Codable, Sendable {
    // MARK: - Identifiers

    /// Primary ISBN (ISBN-13 preferred)
    public let isbn: String?

    /// All ISBNs for this edition
    public let isbns: [String]

    // MARK: - Core Metadata

    /// Edition title
    public let title: String?

    /// Publisher name
    public let publisher: String?

    /// Publication date (YYYY-MM-DD or YYYY)
    public let publicationDate: String?

    /// Number of pages
    public let pageCount: Int?

    /// Physical/digital format
    public let format: DTOEditionFormat

    /// Cover image URL
    public let coverImageURL: String?

    /// Edition-specific title (e.g., "First Edition", "Collector's Edition")
    public let editionTitle: String?

    /// Edition-specific description
    /// CRITICAL: Must use 'editionDescription' not 'description'
    /// SwiftData @Model macro reserves 'description' property
    public let editionDescription: String?

    /// Language code (e.g., "en", "es")
    public let language: String?

    // MARK: - Provenance

    /// Primary data provider
    public let primaryProvider: String?

    /// All providers that contributed to this Edition
    public let contributors: [String]?

    // MARK: - External IDs - Legacy

    public let openLibraryID: String?
    public let openLibraryEditionID: String?
    public let isbndbID: String?
    public let googleBooksVolumeID: String?
    public let goodreadsID: String?

    // MARK: - External IDs - Modern

    /// Amazon ASINs
    public let amazonASINs: [String]

    /// Google Books Volume IDs
    public let googleBooksVolumeIDs: [String]

    /// LibraryThing IDs
    public let librarythingIDs: [String]

    // MARK: - Quality Metrics

    /// Last ISBNDB sync timestamp (ISO 8601)
    public let lastISBNDBSync: String?

    /// ISBNDB quality score (0-100)
    public let isbndbQuality: Int
}
