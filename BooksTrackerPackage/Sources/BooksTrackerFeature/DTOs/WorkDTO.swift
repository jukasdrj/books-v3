import Foundation

/// WorkDTO - Abstract representation of a creative work
///
/// Mirrors TypeScript WorkDTO in cloudflare-workers/api-worker/src/types/canonical.ts exactly.
/// Corresponds to SwiftData Work model.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md
///
/// **DEFENSIVE DECODING:** Backend sometimes violates contract by omitting required fields.
/// Custom `init(from decoder:)` provides defaults to prevent decoding failures.
public struct WorkDTO: Codable, Sendable, Equatable {
    // MARK: - Required Fields

    /// Work title
    public let title: String

    /// Normalized genre/subject tags (defaults to [] if backend omits)
    public let subjectTags: [String]

    // MARK: - Optional Metadata

    /// Original language of the work
    public let originalLanguage: String?

    /// First publication year (YYYY)
    public let firstPublicationYear: Int?

    /// Work description/synopsis
    public let description: String?

    /// Cover image URL (copied from EditionDTO for enrichment)
    public let coverImageURL: String?

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

    /// ISBNDB quality score 0-100 (defaults to 0 if backend omits)
    public let isbndbQuality: Int

    // MARK: - Review Metadata

    /// Review status for AI-detected books (defaults to .verified if backend omits)
    public let reviewStatus: DTOReviewStatus

    /// Original image path for AI-detected books
    public let originalImagePath: String?

    /// Bounding box for AI-detected books
    public let boundingBox: BoundingBox?

    // MARK: - Nested Types

    public struct BoundingBox: Codable, Sendable, Equatable {
        public let x: Double
        public let y: Double
        public let width: Double
        public let height: Double
    }

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case title, subjectTags, originalLanguage, firstPublicationYear, description, coverImageURL
        case synthetic, primaryProvider, contributors
        case openLibraryID, openLibraryWorkID, isbndbID, googleBooksVolumeID, goodreadsID
        case goodreadsWorkIDs, amazonASINs, librarythingIDs, googleBooksVolumeIDs
        case lastISBNDBSync, isbndbQuality
        case reviewStatus, originalImagePath, boundingBox
    }

    // MARK: - Public Initializer

    /// Public memberwise initializer for tests and manual construction
    public init(
        title: String,
        subjectTags: [String],
        originalLanguage: String? = nil,
        firstPublicationYear: Int? = nil,
        description: String? = nil,
        coverImageURL: String? = nil,
        synthetic: Bool? = nil,
        primaryProvider: String? = nil,
        contributors: [String]? = nil,
        openLibraryID: String? = nil,
        openLibraryWorkID: String? = nil,
        isbndbID: String? = nil,
        googleBooksVolumeID: String? = nil,
        goodreadsID: String? = nil,
        goodreadsWorkIDs: [String],
        amazonASINs: [String],
        librarythingIDs: [String],
        googleBooksVolumeIDs: [String],
        lastISBNDBSync: String? = nil,
        isbndbQuality: Int,
        reviewStatus: DTOReviewStatus,
        originalImagePath: String? = nil,
        boundingBox: BoundingBox? = nil
    ) {
        self.title = title
        self.subjectTags = subjectTags
        self.originalLanguage = originalLanguage
        self.firstPublicationYear = firstPublicationYear
        self.description = description
        self.coverImageURL = coverImageURL
        self.synthetic = synthetic
        self.primaryProvider = primaryProvider
        self.contributors = contributors
        self.openLibraryID = openLibraryID
        self.openLibraryWorkID = openLibraryWorkID
        self.isbndbID = isbndbID
        self.googleBooksVolumeID = googleBooksVolumeID
        self.goodreadsID = goodreadsID
        self.goodreadsWorkIDs = goodreadsWorkIDs
        self.amazonASINs = amazonASINs
        self.librarythingIDs = librarythingIDs
        self.googleBooksVolumeIDs = googleBooksVolumeIDs
        self.lastISBNDBSync = lastISBNDBSync
        self.isbndbQuality = isbndbQuality
        self.reviewStatus = reviewStatus
        self.originalImagePath = originalImagePath
        self.boundingBox = boundingBox
    }

    // MARK: - Custom Decoding with Defaults

    /// Custom decoder to handle backend contract violations
    /// Provides sensible defaults for required fields that backend sometimes omits
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields
        title = try container.decode(String.self, forKey: .title)

        // Required fields with defensive defaults (backend sometimes omits)
        subjectTags = try container.decodeIfPresent([String].self, forKey: .subjectTags) ?? []
        isbndbQuality = try container.decodeIfPresent(Int.self, forKey: .isbndbQuality) ?? 0
        reviewStatus = try container.decodeIfPresent(DTOReviewStatus.self, forKey: .reviewStatus) ?? .verified

        // Optional metadata
        originalLanguage = try container.decodeIfPresent(String.self, forKey: .originalLanguage)
        firstPublicationYear = try container.decodeIfPresent(Int.self, forKey: .firstPublicationYear)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        coverImageURL = try container.decodeIfPresent(String.self, forKey: .coverImageURL)

        // Provenance
        synthetic = try container.decodeIfPresent(Bool.self, forKey: .synthetic)
        primaryProvider = try container.decodeIfPresent(String.self, forKey: .primaryProvider)
        contributors = try container.decodeIfPresent([String].self, forKey: .contributors)

        // External IDs - Legacy
        openLibraryID = try container.decodeIfPresent(String.self, forKey: .openLibraryID)
        openLibraryWorkID = try container.decodeIfPresent(String.self, forKey: .openLibraryWorkID)
        isbndbID = try container.decodeIfPresent(String.self, forKey: .isbndbID)
        googleBooksVolumeID = try container.decodeIfPresent(String.self, forKey: .googleBooksVolumeID)
        goodreadsID = try container.decodeIfPresent(String.self, forKey: .goodreadsID)

        // External IDs - Modern (arrays default to empty)
        goodreadsWorkIDs = try container.decodeIfPresent([String].self, forKey: .goodreadsWorkIDs) ?? []
        amazonASINs = try container.decodeIfPresent([String].self, forKey: .amazonASINs) ?? []
        librarythingIDs = try container.decodeIfPresent([String].self, forKey: .librarythingIDs) ?? []
        googleBooksVolumeIDs = try container.decodeIfPresent([String].self, forKey: .googleBooksVolumeIDs) ?? []

        // Quality metrics
        lastISBNDBSync = try container.decodeIfPresent(String.self, forKey: .lastISBNDBSync)

        // Review metadata
        originalImagePath = try container.decodeIfPresent(String.self, forKey: .originalImagePath)
        boundingBox = try container.decodeIfPresent(BoundingBox.self, forKey: .boundingBox)
    }
}
