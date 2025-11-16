import Foundation

/// AuthorDTO - Creator of works
///
/// Mirrors TypeScript AuthorDTO in cloudflare-workers/api-worker/src/types/canonical.ts exactly.
/// Corresponds to SwiftData Author model.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md
///
/// **DEFENSIVE DECODING:** Backend sometimes violates contract by omitting required fields.
/// Custom `init(from decoder:)` provides defaults to prevent decoding failures.
public struct AuthorDTO: Codable, Sendable, Equatable {
    // MARK: - Required Fields

    /// Author name
    public let name: String

    /// Author gender
    public let gender: DTOAuthorGender

    // MARK: - Optional Metadata

    /// Cultural region
    public let culturalRegion: DTOCulturalRegion?

    /// Nationality
    public let nationality: String?

    /// Birth year
    public let birthYear: Int?

    /// Death year (nil if living)
    public let deathYear: Int?

    // MARK: - External IDs

    public let openLibraryID: String?
    public let isbndbID: String?
    public let googleBooksID: String?
    public let goodreadsID: String?

    // MARK: - Statistics

    /// Number of books by this author
    public let bookCount: Int?

    // MARK: - Memberwise Initializer

    public init(
        name: String,
        gender: DTOAuthorGender,
        culturalRegion: DTOCulturalRegion? = nil,
        nationality: String? = nil,
        birthYear: Int? = nil,
        deathYear: Int? = nil,
        openLibraryID: String? = nil,
        isbndbID: String? = nil,
        googleBooksID: String? = nil,
        goodreadsID: String? = nil,
        bookCount: Int? = nil
    ) {
        self.name = name
        self.gender = gender
        self.culturalRegion = culturalRegion
        self.nationality = nationality
        self.birthYear = birthYear
        self.deathYear = deathYear
        self.openLibraryID = openLibraryID
        self.isbndbID = isbndbID
        self.googleBooksID = googleBooksID
        self.goodreadsID = goodreadsID
        self.bookCount = bookCount
    }

    // MARK: - Coding Keys

    private enum CodingKeys: String, CodingKey {
        case name, gender, culturalRegion, nationality, birthYear, deathYear
        case openLibraryID, isbndbID, googleBooksID, goodreadsID
        case bookCount
    }

    // MARK: - Custom Decoding with Defaults

    /// Custom decoder to handle backend contract violations
    /// Provides sensible defaults for required fields that backend sometimes omits
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required fields
        name = try container.decode(String.self, forKey: .name)
        gender = try container.decodeIfPresent(DTOAuthorGender.self, forKey: .gender) ?? .unknown

        // Optional metadata
        culturalRegion = try container.decodeIfPresent(DTOCulturalRegion.self, forKey: .culturalRegion)
        nationality = try container.decodeIfPresent(String.self, forKey: .nationality)
        birthYear = try container.decodeIfPresent(Int.self, forKey: .birthYear)
        deathYear = try container.decodeIfPresent(Int.self, forKey: .deathYear)

        // External IDs
        openLibraryID = try container.decodeIfPresent(String.self, forKey: .openLibraryID)
        isbndbID = try container.decodeIfPresent(String.self, forKey: .isbndbID)
        googleBooksID = try container.decodeIfPresent(String.self, forKey: .googleBooksID)
        goodreadsID = try container.decodeIfPresent(String.self, forKey: .goodreadsID)

        // Statistics
        bookCount = try container.decodeIfPresent(Int.self, forKey: .bookCount)
    }
}
