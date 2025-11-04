import Foundation

/// AuthorDTO - Creator of works
///
/// Mirrors TypeScript AuthorDTO in cloudflare-workers/api-worker/src/types/canonical.ts exactly.
/// Corresponds to SwiftData Author model.
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md
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
}
