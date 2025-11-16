import Foundation

/// EditionDTO - Physical/digital manifestation of a Work
///
/// Mirrors TypeScript EditionDTO in cloudflare-workers/api-worker/src/types/canonical.ts exactly.
/// Corresponds to SwiftData Edition model.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md
///
/// **DEFENSIVE DECODING:** Backend sometimes violates contract by omitting required fields.
/// Custom `init(from decoder:)` provides defaults to prevent decoding failures.
public struct EditionDTO: Codable, Sendable, Equatable {
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

    /// ISBNDB quality score 0-100 (defaults to 0 if backend omits)
    public let isbndbQuality: Int

    // MARK: - Public Initializer

    /// Public memberwise initializer for tests and manual construction
    public init(
        isbn: String? = nil,
        isbns: [String],
        title: String? = nil,
        publisher: String? = nil,
        publicationDate: String? = nil,
        pageCount: Int? = nil,
        format: DTOEditionFormat,
        coverImageURL: String? = nil,
        editionTitle: String? = nil,
        editionDescription: String? = nil,
        language: String? = nil,
        primaryProvider: String? = nil,
        contributors: [String]? = nil,
        openLibraryID: String? = nil,
        openLibraryEditionID: String? = nil,
        isbndbID: String? = nil,
        googleBooksVolumeID: String? = nil,
        goodreadsID: String? = nil,
        amazonASINs: [String],
        googleBooksVolumeIDs: [String],
        librarythingIDs: [String],
        lastISBNDBSync: String? = nil,
        isbndbQuality: Int
    ) {
        self.isbn = isbn
        self.isbns = isbns
        self.title = title
        self.publisher = publisher
        self.publicationDate = publicationDate
        self.pageCount = pageCount
        self.format = format
        self.coverImageURL = coverImageURL
        self.editionTitle = editionTitle
        self.editionDescription = editionDescription
        self.language = language
        self.primaryProvider = primaryProvider
        self.contributors = contributors
        self.openLibraryID = openLibraryID
        self.openLibraryEditionID = openLibraryEditionID
        self.isbndbID = isbndbID
        self.googleBooksVolumeID = googleBooksVolumeID
        self.goodreadsID = goodreadsID
        self.amazonASINs = amazonASINs
        self.googleBooksVolumeIDs = googleBooksVolumeIDs
        self.librarythingIDs = librarythingIDs
        self.lastISBNDBSync = lastISBNDBSync
        self.isbndbQuality = isbndbQuality
    }

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case isbn, isbns, title, publisher, publicationDate, pageCount, format
        case coverImageURL, editionTitle, editionDescription, language
        case primaryProvider, contributors
        case openLibraryID, openLibraryEditionID, isbndbID, googleBooksVolumeID, goodreadsID
        case amazonASINs, googleBooksVolumeIDs, librarythingIDs
        case lastISBNDBSync, isbndbQuality
    }

    // MARK: - Custom Decoding with Defaults

    /// Custom decoder to handle backend contract violations
    /// Provides sensible defaults for required fields that backend sometimes omits
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Identifiers
        isbn = try container.decodeIfPresent(String.self, forKey: .isbn)
        isbns = try container.decodeIfPresent([String].self, forKey: .isbns) ?? {
            #if DEBUG
            print("⚠️ Backend violation: Missing isbns for edition - defaulting to []")
            #endif
            return []
        }()

        // Core metadata
        title = try container.decodeIfPresent(String.self, forKey: .title)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        publicationDate = try container.decodeIfPresent(String.self, forKey: .publicationDate)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        format = try container.decodeIfPresent(DTOEditionFormat.self, forKey: .format) ?? {
            #if DEBUG
            print("⚠️ Backend violation: Missing format for edition '\(title ?? "N/A")' - defaulting to .paperback")
            #endif
            return .paperback
        }()
        coverImageURL = try container.decodeIfPresent(String.self, forKey: .coverImageURL)
        editionTitle = try container.decodeIfPresent(String.self, forKey: .editionTitle)
        editionDescription = try container.decodeIfPresent(String.self, forKey: .editionDescription)
        language = try container.decodeIfPresent(String.self, forKey: .language)

        // Provenance
        primaryProvider = try container.decodeIfPresent(String.self, forKey: .primaryProvider)
        contributors = try container.decodeIfPresent([String].self, forKey: .contributors)

        // External IDs - Legacy
        openLibraryID = try container.decodeIfPresent(String.self, forKey: .openLibraryID)
        openLibraryEditionID = try container.decodeIfPresent(String.self, forKey: .openLibraryEditionID)
        isbndbID = try container.decodeIfPresent(String.self, forKey: .isbndbID)
        googleBooksVolumeID = try container.decodeIfPresent(String.self, forKey: .googleBooksVolumeID)
        goodreadsID = try container.decodeIfPresent(String.self, forKey: .goodreadsID)

        // External IDs - Modern (arrays default to empty)
        amazonASINs = try container.decodeIfPresent([String].self, forKey: .amazonASINs) ?? {
            #if DEBUG
            print("⚠️ Backend violation: Missing amazonASINs for edition '\(title ?? "N/A")' - defaulting to []")
            #endif
            return []
        }()
        googleBooksVolumeIDs = try container.decodeIfPresent([String].self, forKey: .googleBooksVolumeIDs) ?? {
            #if DEBUG
            print("⚠️ Backend violation: Missing googleBooksVolumeIDs for edition '\(title ?? "N/A")' - defaulting to []")
            #endif
            return []
        }()
        librarythingIDs = try container.decodeIfPresent([String].self, forKey: .librarythingIDs) ?? {
            #if DEBUG
            print("⚠️ Backend violation: Missing librarythingIDs for edition '\(title ?? "N/A")' - defaulting to []")
            #endif
            return []
        }()

        // Quality metrics
        lastISBNDBSync = try container.decodeIfPresent(String.self, forKey: .lastISBNDBSync)
        isbndbQuality = try container.decodeIfPresent(Int.self, forKey: .isbndbQuality) ?? {
            #if DEBUG
            print("⚠️ Backend violation: Missing isbndbQuality for edition '\(title ?? "N/A")' - defaulting to 0")
            #endif
            return 0
        }()
    }
}
