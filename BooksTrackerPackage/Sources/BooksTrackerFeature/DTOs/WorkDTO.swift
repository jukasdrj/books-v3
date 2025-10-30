import Foundation

/// WorkDTO - Abstract representation of a creative work
///
/// Mirrors TypeScript WorkDTO in cloudflare-workers/api-worker/src/types/canonical.ts exactly.
/// Corresponds to SwiftData Work model.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md
public struct WorkDTO: Codable, Sendable {
    // MARK: - Required Fields

    /// Work title
    public let title: String

    /// Normalized genre/subject tags
    public let subjectTags: [String]

    // MARK: - Optional Metadata

    /// Original language of the work
    public let originalLanguage: String?

    /// First publication year (YYYY)
    public let firstPublicationYear: Int?

    /// Work description/synopsis
    public let description: String?

    // MARK: - Provenance

    /// True if Work was inferred from Edition data (enables deduplication)
    public let synthetic: Bool?

    /// Primary data provider
    public let primaryProvider: String?

    /// All providers that contributed to this Work
    public let contributors: [String]?

    // MARK: - External IDs - Legacy (single values)

    public let openLibraryID: String?
    public let openLibraryWorkID: String?
    public let isbndbID: String?
    public let googleBooksVolumeID: String?
    public let goodreadsID: String?

    // MARK: - External IDs - Modern (arrays)

    /// Goodreads Work IDs
    public let goodreadsWorkIDs: [String]

    /// Amazon ASINs
    public let amazonASINs: [String]

    /// LibraryThing IDs
    public let librarythingIDs: [String]

    /// Google Books Volume IDs (for deduplication)
    public let googleBooksVolumeIDs: [String]

    // MARK: - Quality Metrics

    /// Last ISBNDB sync timestamp (ISO 8601)
    public let lastISBNDBSync: String?

    /// ISBNDB quality score (0-100)
    public let isbndbQuality: Int

    // MARK: - Review Metadata

    /// Review status for AI-detected books
    public let reviewStatus: DTOReviewStatus

    /// Original image path for AI-detected books
    public let originalImagePath: String?

    /// Bounding box for AI-detected books
    public let boundingBox: BoundingBox?

    // MARK: - Nested Types

    public struct BoundingBox: Codable, Sendable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }
}
