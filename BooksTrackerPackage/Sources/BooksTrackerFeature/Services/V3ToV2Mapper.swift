import Foundation
import CryptoKit

/// Maps V3 API responses to V2 DTOs for SwiftData compatibility
///
/// V3 API returns unified Book models with flat author strings.
/// V2 DTOs use separate Work/Edition/Author models with relationships.
/// This mapper bridges the gap while preserving SwiftData architecture.
///
/// Synthetic ID Generation:
/// Uses SHA256 hashing for deterministic, stable IDs across app runs.
/// - Work ID: "OL{hash(isbn)}W"
/// - Edition ID: "OL{hash(isbn)}M"
/// - Author ID: "OL{hash(name)}A"
public struct V3ToV2Mapper: Sendable {

    // MARK: - Public API

    /// Map V3 search response to V2 BookSearchResponse
    ///
    /// Transforms V3 unified book models into separate Work/Edition/Author DTOs
    /// with proper relationships for SwiftData persistence.
    ///
    /// - Parameter v3Response: V3 search response from Alexandria API
    /// - Returns: BookSearchResponse with separated works, editions, and authors
    public static func mapSearchResponse(_ v3Response: V3SearchResponse) -> BookSearchResponse {
        mapBookListToSearchResponse(v3Response.data.books, totalResults: v3Response.data.total)
    }

    /// Map V3 enrich response to V2 BookSearchResponse
    ///
    /// Similar to search mapping, but handles enriched book data.
    /// Ignores vectorization status as V2 DTOs don't track this.
    ///
    /// - Parameter v3Response: V3 enrich response from Alexandria API
    /// - Returns: BookSearchResponse with separated works, editions, and authors
    public static func mapEnrichResponse(_ v3Response: V3EnrichResponse) -> BookSearchResponse {
        let v3Books = v3Response.data.books.map { enrichedBook in
            // Convert V3EnrichedBook to V3Book (same structure, ignore vectorized field)
            V3Book(
                isbn: enrichedBook.isbn,
                isbn10: enrichedBook.isbn10,
                title: enrichedBook.title,
                subtitle: enrichedBook.subtitle,
                authors: enrichedBook.authors,
                publisher: enrichedBook.publisher,
                publishedDate: enrichedBook.publishedDate,
                description: enrichedBook.description,
                pageCount: enrichedBook.pageCount,
                categories: enrichedBook.categories,
                language: enrichedBook.language,
                coverUrl: enrichedBook.coverUrl,
                thumbnailUrl: enrichedBook.thumbnailUrl,
                workKey: enrichedBook.workKey,
                editionKey: enrichedBook.editionKey,
                provider: enrichedBook.provider,
                quality: enrichedBook.quality
            )
        }

        return mapBookListToSearchResponse(v3Books, totalResults: v3Response.data.found)
    }

    // MARK: - Private Helpers

    /// Helper to process a list of V3Books into a BookSearchResponse
    private static func mapBookListToSearchResponse(_ v3Books: [V3Book], totalResults: Int) -> BookSearchResponse {
        var allWorks: [WorkDTO] = []
        var allEditions: [EditionDTO] = []
        var allAuthorsLists: [[AuthorDTO]] = []

        for v3Book in v3Books {
            let (work, edition, authors) = mapBook(v3Book)
            allWorks.append(work)
            allEditions.append(edition)
            allAuthorsLists.append(authors)
        }

        let deduplicatedAuthors = deduplicateAuthors(allAuthorsLists)

        return BookSearchResponse(
            works: allWorks,
            editions: allEditions,
            authors: deduplicatedAuthors,
            resultCount: allWorks.count,
            expiresAt: nil, // V3 doesn't provide cache expiration yet
            totalResults: totalResults
        )
    }

    /// Map single V3Book to Work/Edition/Authors
    ///
    /// Creates separate DTOs with proper relationships:
    /// - Edition.workID links to Work.openLibraryID
    /// - Work.authorIDs links to all Author.openLibraryID values
    ///
    /// - Parameter v3Book: V3 book model from API
    /// - Returns: Tuple of (work, edition, authors) with relationships established
    internal static func mapBook(_ v3Book: V3Book) -> (work: WorkDTO, edition: EditionDTO, authors: [AuthorDTO]) {
        // --- Authors first (for relationship tracking) ---
        let authors: [AuthorDTO] = v3Book.authors.map { v3Author in
            AuthorDTO(
                name: v3Author.name,
                gender: mapGender(from: v3Author.gender),
                culturalRegion: nil,  // V3 doesn't provide this yet
                nationality: v3Author.nationality,  // NEW: from V3
                birthYear: v3Author.birthYear,      // NEW: from V3
                deathYear: v3Author.deathYear,      // NEW: from V3
                openLibraryID: v3Author.key ?? generateAuthorID(from: v3Author.name),
                isbndbID: nil,
                googleBooksID: nil,
                goodreadsID: nil,
                bookCount: nil
            )
        }

        // Determine Work ID (prefer workKey, fallback to synthetic)
        let workOpenLibraryID: String
        let workSynthetic: Bool
        if let key = v3Book.workKey, !key.isEmpty {
            workOpenLibraryID = key
            workSynthetic = false
        } else {
            // Use ISBN for synthetic Work ID
            workOpenLibraryID = generateWorkID(from: v3Book.isbn)
            workSynthetic = true
        }

        // --- Work DTO ---
        let work = WorkDTO(
            title: v3Book.title,
            subjectTags: v3Book.categories ?? [],
            originalLanguage: v3Book.language,
            firstPublicationYear: extractYear(from: v3Book.publishedDate),
            description: v3Book.description,
            coverImageURL: v3Book.coverUrl ?? v3Book.thumbnailUrl, // Prefer coverUrl, fallback to thumbnailUrl
            searchLinks: nil, // V3 doesn't provide HATEOAS links yet
            synthetic: workSynthetic,
            primaryProvider: v3Book.provider,
            contributors: nil,
            openLibraryID: workOpenLibraryID,
            openLibraryWorkID: v3Book.workKey,
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            goodreadsWorkIDs: [],
            amazonASINs: [],
            librarythingIDs: [],
            googleBooksVolumeIDs: [],
            lastISBNDBSync: nil,
            isbndbQuality: 0, // V3 doesn't provide quality metrics yet
            reviewStatus: .verified, // V3 books are pre-verified
            originalImagePath: nil,
            boundingBox: nil
        )

        // Determine Edition ID (prefer editionKey, fallback to synthetic)
        let editionOpenLibraryID: String
        if let key = v3Book.editionKey, !key.isEmpty {
            editionOpenLibraryID = key
        } else {
            editionOpenLibraryID = generateEditionID(from: v3Book.isbn)
        }

        // Build ISBNs array
        var isbns: [String] = [v3Book.isbn]
        if let isbn10 = v3Book.isbn10, !isbn10.isEmpty, !isbns.contains(isbn10) {
            isbns.append(isbn10)
        }

        // --- Edition DTO ---
        let edition = EditionDTO(
            isbn: v3Book.isbn,
            isbns: isbns,
            title: v3Book.title,
            publisher: v3Book.publisher,
            publicationDate: v3Book.publishedDate,
            pageCount: v3Book.pageCount,
            format: .paperback, // Default, V3 doesn't specify format
            coverImageURL: v3Book.coverUrl ?? v3Book.thumbnailUrl,
            editionTitle: v3Book.subtitle,
            editionDescription: v3Book.description,
            language: v3Book.language,
            searchLinks: nil,
            primaryProvider: v3Book.provider,
            contributors: nil,
            openLibraryID: editionOpenLibraryID,
            openLibraryEditionID: v3Book.editionKey,
            isbndbID: nil,
            googleBooksVolumeID: nil,
            goodreadsID: nil,
            amazonASINs: [],
            googleBooksVolumeIDs: [],
            librarythingIDs: [],
            lastISBNDBSync: nil,
            isbndbQuality: 0
        )

        return (work: work, edition: edition, authors: authors)
    }

    /// Generate stable synthetic Work ID from ISBN
    ///
    /// Uses SHA256 hashing for deterministic IDs across app runs.
    /// Same ISBN always produces the same Work ID.
    ///
    /// - Parameter isbn: ISBN-13 or ISBN-10
    /// - Returns: Synthetic OpenLibrary-style Work ID (e.g., "OL123456789W")
    internal static func generateWorkID(from isbn: String) -> String {
        let hash = stableHash(isbn)
        return "OL\(hash)W"
    }

    /// Generate stable synthetic Edition ID from ISBN
    ///
    /// Uses SHA256 hashing for deterministic IDs across app runs.
    /// Same ISBN always produces the same Edition ID.
    ///
    /// - Parameter isbn: ISBN-13 or ISBN-10
    /// - Returns: Synthetic OpenLibrary-style Edition ID (e.g., "OL123456789M")
    internal static func generateEditionID(from isbn: String) -> String {
        let hash = stableHash(isbn)
        return "OL\(hash)M"
    }

    /// Generate stable synthetic Author ID from name
    ///
    /// Uses SHA256 hashing for deterministic IDs across app runs.
    /// Same author name always produces the same Author ID.
    ///
    /// - Parameter name: Author name
    /// - Returns: Synthetic OpenLibrary-style Author ID (e.g., "OL123456789A")
    internal static func generateAuthorID(from name: String) -> String {
        let hash = stableHash(name)
        return "OL\(hash)A"
    }

    /// Map V3 API gender string to DTOAuthorGender enum
    ///
    /// - Parameter gender: Optional gender string from V3 API ("Male", "Female", "Other", etc.)
    /// - Returns: Mapped DTOAuthorGender enum value
    private static func mapGender(from gender: String?) -> DTOAuthorGender {
        guard let gender = gender else { return .unknown }

        switch gender.lowercased() {
        case "male":
            return .male
        case "female":
            return .female
        case "nonbinary", "non-binary", "other":
            return .nonBinary
        default:
            return .unknown
        }
    }

    /// Create stable hash from string using SHA256
    ///
    /// CRITICAL: Uses SHA256 for deterministic hashing.
    /// String.hashValue is NOT stable across app runs or Swift versions.
    ///
    /// Platform-independent implementation using fixed byte order (big-endian)
    /// to ensure consistent hashes across all platforms.
    ///
    /// - Parameter input: String to hash
    /// - Returns: Positive integer hash (truncated SHA256)
    private static func stableHash(_ input: String) -> UInt64 {
        let hash = SHA256.hash(data: Data(input.utf8))
        // Use the first 8 bytes of the hash to create a UInt64.
        // This approach is endian-agnostic, ensuring the hash is stable across all platforms.
        let truncatedData = hash.prefix(8)
        let value = truncatedData.reduce(0) { soFar, byte in
            (soFar << 8) | UInt64(byte)
        }
        return value
    }

    /// Deduplicate authors by name
    ///
    /// Multiple books can reference the same author.
    /// This ensures only one AuthorDTO per unique name.
    ///
    /// - Parameter authors: Nested arrays of authors from multiple books
    /// - Returns: Deduplicated author array (one per unique name)
    private static func deduplicateAuthors(_ authors: [[AuthorDTO]]) -> [AuthorDTO] {
        var authorCache: [String: AuthorDTO] = [:]
        for authorList in authors {
            for author in authorList {
                // generateAuthorID is deterministic, so same name = same ID
                if authorCache[author.name] == nil {
                    authorCache[author.name] = author
                }
            }
        }
        return Array(authorCache.values)
    }

    /// Extract year from publication date string
    ///
    /// Handles formats: "YYYY", "YYYY-MM-DD", "YYYY-MM"
    ///
    /// - Parameter dateString: Publication date (optional)
    /// - Returns: Four-digit year if parseable, nil otherwise
    private static func extractYear(from dateString: String?) -> Int? {
        guard let dateString = dateString, dateString.count >= 4 else {
            return nil
        }

        let yearPrefix = String(dateString.prefix(4))
        return Int(yearPrefix)
    }
}
