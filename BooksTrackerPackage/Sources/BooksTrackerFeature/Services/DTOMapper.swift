import Foundation
import SwiftData

/// DTOMapper - Converts canonical DTOs to SwiftData models
///
/// Critical Constraints:
/// 1. ALWAYS insert entities before setting relationships (insert-before-relate pattern)
/// 2. Deduplicates Works by googleBooksVolumeIDs
/// 3. Merges synthetic Works (inferred from Editions) with real Works
/// 4. Maps enum types correctly (DTOAuthorGender → AuthorGender, etc.)
///
/// Design: docs/plans/2025-10-29-canonical-data-contracts-design.md
@MainActor
public final class DTOMapper {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Author Mapping

    /// Maps AuthorDTO to Author SwiftData model
    /// Creates new Author and inserts into context
    public func mapToAuthor(_ dto: AuthorDTO) throws -> Author {
        let author = Author(
            name: dto.name,
            nationality: dto.nationality,
            gender: mapGender(dto.gender),
            culturalRegion: mapCulturalRegion(dto.culturalRegion),
            birthYear: dto.birthYear,
            deathYear: dto.deathYear
        )

        // External IDs
        author.openLibraryID = dto.openLibraryID
        author.isbndbID = dto.isbndbID
        author.googleBooksID = dto.googleBooksID
        author.goodreadsID = dto.goodreadsID

        // Statistics
        author.bookCount = dto.bookCount ?? 0

        // CRITICAL: Insert before any relationships
        modelContext.insert(author)

        return author
    }

    // MARK: - Edition Mapping

    /// Maps EditionDTO to Edition SwiftData model
    /// Creates new Edition and inserts into context
    /// Does NOT set Work relationship - caller must handle that
    public func mapToEdition(_ dto: EditionDTO) throws -> Edition {
        let edition = Edition(
            isbn: dto.isbn,
            publisher: dto.publisher,
            publicationDate: dto.publicationDate,
            pageCount: dto.pageCount,
            format: mapEditionFormat(dto.format),
            coverImageURL: dto.coverImageURL,
            editionTitle: dto.editionTitle,
            editionDescription: dto.editionDescription,
            work: nil, // Caller sets this after both entities inserted
            primaryProvider: dto.primaryProvider
        )

        // ISBNs array
        edition.isbns = dto.isbns

        // External IDs
        edition.openLibraryID = dto.openLibraryID
        edition.openLibraryEditionID = dto.openLibraryEditionID
        edition.isbndbID = dto.isbndbID
        edition.googleBooksVolumeID = dto.googleBooksVolumeID
        edition.goodreadsID = dto.goodreadsID

        // External ID arrays
        edition.amazonASINs = dto.amazonASINs
        edition.googleBooksVolumeIDs = dto.googleBooksVolumeIDs
        edition.librarythingIDs = dto.librarythingIDs

        // Quality metrics
        edition.isbndbQuality = dto.isbndbQuality
        if let lastSync = dto.lastISBNDBSync {
            edition.lastISBNDBSync = ISO8601DateFormatter().date(from: lastSync)
        }

        // Provenance
        edition.contributors = dto.contributors ?? []

        // CRITICAL: Insert before any relationships
        modelContext.insert(edition)

        return edition
    }

    // MARK: - Work Mapping

    /// Maps WorkDTO to Work SwiftData model
    /// Handles deduplication by googleBooksVolumeIDs
    /// Merges synthetic Works with real Works
    public func mapToWork(_ dto: WorkDTO) throws -> Work {
        // Check for existing Work by googleBooksVolumeIDs (deduplication)
        if let existingWork = try findExistingWork(by: dto.googleBooksVolumeIDs) {
            // Merge data into existing Work
            mergeWorkData(dto: dto, into: existingWork)
            return existingWork
        }

        // Create new Work
        let work = Work(
            title: dto.title,
            authors: [], // Set after authors are inserted
            originalLanguage: dto.originalLanguage,
            firstPublicationYear: dto.firstPublicationYear,
            subjectTags: dto.subjectTags,
            synthetic: dto.synthetic ?? false,
            primaryProvider: dto.primaryProvider
        )

        // External IDs
        work.openLibraryID = dto.openLibraryID
        work.openLibraryWorkID = dto.openLibraryWorkID
        work.isbndbID = dto.isbndbID
        work.googleBooksVolumeID = dto.googleBooksVolumeID
        work.goodreadsID = dto.goodreadsID

        // External ID arrays
        work.goodreadsWorkIDs = dto.goodreadsWorkIDs
        work.amazonASINs = dto.amazonASINs
        work.librarythingIDs = dto.librarythingIDs
        work.googleBooksVolumeIDs = dto.googleBooksVolumeIDs

        // Quality metrics
        work.isbndbQuality = dto.isbndbQuality
        if let lastSync = dto.lastISBNDBSync {
            work.lastISBNDBSync = ISO8601DateFormatter().date(from: lastSync)
        }

        // Provenance
        work.contributors = dto.contributors ?? []

        // Review metadata
        work.reviewStatus = mapReviewStatus(dto.reviewStatus)
        work.originalImagePath = dto.originalImagePath
        if let bbox = dto.boundingBox {
            work.boundingBoxX = bbox.x
            work.boundingBoxY = bbox.y
            work.boundingBoxWidth = bbox.width
            work.boundingBoxHeight = bbox.height
        }

        // CRITICAL: Insert before any relationships
        modelContext.insert(work)

        return work
    }

    // MARK: - Deduplication & Merging

    /// Find existing Work by googleBooksVolumeIDs (for deduplication)
    private func findExistingWork(by volumeIDs: [String]) throws -> Work? {
        guard !volumeIDs.isEmpty else { return nil }

        let descriptor = FetchDescriptor<Work>()
        let allWorks = try modelContext.fetch(descriptor)

        // Find Work with any matching googleBooksVolumeID
        return allWorks.first { existingWork in
            !Set(existingWork.googleBooksVolumeIDs).isDisjoint(with: volumeIDs)
        }
    }

    /// Merge WorkDTO data into existing Work
    /// Handles synthetic → real Work upgrade
    private func mergeWorkData(dto: WorkDTO, into work: Work) {
        // If existing Work is synthetic and new data is real, upgrade it
        if work.synthetic && dto.synthetic == false {
            work.synthetic = false
            work.title = dto.title
            work.originalLanguage = dto.originalLanguage
            work.firstPublicationYear = dto.firstPublicationYear
            work.subjectTags = dto.subjectTags
            work.reviewStatus = mapReviewStatus(dto.reviewStatus)

            // Update external IDs
            work.openLibraryWorkID = dto.openLibraryWorkID
            work.isbndbID = dto.isbndbID

            // Merge external ID arrays
            dto.goodreadsWorkIDs.forEach { work.addGoodreadsWorkID($0) }
            dto.amazonASINs.forEach { work.addAmazonASIN($0) }
            dto.librarythingIDs.forEach { work.addLibraryThingID($0) }

            // Update quality metrics
            if dto.isbndbQuality > work.isbndbQuality {
                work.isbndbQuality = dto.isbndbQuality
            }
        }

        // Always merge googleBooksVolumeIDs (for deduplication tracking)
        dto.googleBooksVolumeIDs.forEach { work.addGoogleBooksVolumeID($0) }

        // Merge contributors (union)
        if let newContributors = dto.contributors {
            let merged = Set(work.contributors).union(newContributors)
            work.contributors = Array(merged)
        }

        // Update primary provider if better quality
        if let newProvider = dto.primaryProvider, work.primaryProvider == nil {
            work.primaryProvider = newProvider
        }

        work.touch()
    }

    // MARK: - Enum Mapping

    /// Map DTOAuthorGender to AuthorGender
    private func mapGender(_ dto: DTOAuthorGender) -> AuthorGender {
        switch dto {
        case .female: return .female
        case .male: return .male
        case .nonBinary: return .nonBinary
        case .other: return .other
        case .unknown: return .unknown
        }
    }

    /// Map DTOCulturalRegion to CulturalRegion
    private func mapCulturalRegion(_ dto: DTOCulturalRegion?) -> CulturalRegion? {
        guard let dto = dto else { return nil }

        switch dto {
        case .africa: return .africa
        case .asia: return .asia
        case .europe: return .europe
        case .northAmerica: return .northAmerica
        case .southAmerica: return .southAmerica
        case .oceania: return .oceania
        case .middleEast: return .middleEast
        case .caribbean: return .caribbean
        case .centralAsia: return .centralAsia
        case .indigenous: return .indigenous
        case .international: return .international
        }
    }

    /// Map DTOEditionFormat to EditionFormat
    private func mapEditionFormat(_ dto: DTOEditionFormat) -> EditionFormat {
        switch dto {
        case .hardcover: return .hardcover
        case .paperback: return .paperback
        case .ebook: return .ebook
        case .audiobook: return .audiobook
        case .massMarket: return .massMarket
        }
    }

    /// Map DTOReviewStatus to ReviewStatus
    private func mapReviewStatus(_ dto: DTOReviewStatus) -> ReviewStatus {
        switch dto {
        case .verified: return .verified
        case .needsReview: return .needsReview
        case .userEdited: return .userEdited
        }
    }
}
