import Foundation
import SwiftData
import OSLog

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
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "DTOMapper")
    private var workCache: [String: PersistentIdentifier] = [:] // volumeID -> PersistentIdentifier
    
    // Cache persistence location
    private let cacheURL: URL = {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            // Fallback to temporary directory if caches directory unavailable
            let tempDir = FileManager.default.temporaryDirectory
            return tempDir.appendingPathComponent("dto_work_cache.json")
        }
        return directory.appendingPathComponent("dto_work_cache.json")
    }()

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.workCache = loadCacheFromDisk()
    }
    
    // MARK: - Cache Persistence
    
    /// Load cache from disk on init
    private func loadCacheFromDisk() -> [String: PersistentIdentifier] {
        guard let data = try? Data(contentsOf: cacheURL) else {
            logger.info("No cached deduplication data found on disk")
            return [:]
        }
        
        let decoder = JSONDecoder()
        guard let cache = try? decoder.decode([String: PersistentIdentifier].self, from: data) else {
            logger.warning("Failed to decode cache from disk, starting fresh")
            return [:]
        }
        
        logger.info("Loaded \(cache.count) cache entries from disk")
        return cache
    }
    
    /// Save cache to disk after modifications
    private func saveCacheToDisk() {
        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(self.workCache) else {
            self.logger.error("Failed to encode cache for persistence")
            return
        }

        do {
            try data.write(to: self.cacheURL, options: .atomic)
            self.logger.debug("Saved \(self.workCache.count) cache entries to disk")
        } catch {
            self.logger.error("Failed to write cache to disk: \(error)")
        }
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
            // work parameter removed - caller sets this after insert
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
        // Note: May skip deduplication if ModelContext is invalid (store torn down)
        if let existingWork = try findExistingWork(by: dto.googleBooksVolumeIDs) {
            // Merge data into existing Work
            mergeWorkData(dto: dto, into: existingWork)
            return existingWork
        }

        // Create new Work
        let work = Work(
            title: dto.title,
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

        // Update cache with PersistentIdentifier
        for volumeID in dto.googleBooksVolumeIDs {
            workCache[volumeID] = work.persistentModelID
        }
        
        // Persist cache to disk
        saveCacheToDisk()

        return work
    }

    // MARK: - Cache Management

    /// Clears the entire deduplication cache.
    /// Call this when performing a full library reset.
    /// Note: Manual cache cleanup is no longer needed - stale entries are
    /// automatically evicted when Works are deleted.
    public func clearCache() {
        workCache.removeAll()
        
        // Delete cache file from disk
        try? FileManager.default.removeItem(at: cacheURL)
        
        logger.info("Deduplication cache cleared (memory and disk).")
    }
    
    /// Proactively prune stale cache entries by validating against current database state.
    /// Call this on app launch to remove PersistentIdentifiers for Works that were deleted
    /// in other sessions (e.g., via CloudKit sync).
    ///
    /// This is critical for persistent caches to prevent unbounded growth and stale references.
    @MainActor
    public func pruneStaleCacheEntries() {
        let allCachedIDs = Array(workCache.values)
        guard !allCachedIDs.isEmpty else {
            logger.info("Cache is empty, no pruning needed")
            return
        }
        
        do {
            // 1. Fetch ALL Works and filter in memory
            // This avoids complex predicate translation and is more reliable
            let descriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(descriptor)
            
            // 2. Build Set of valid IDs from fetched Works
            let cachedIDSet = Set(allCachedIDs)
            let validIDSet = Set(allWorks.map { $0.persistentModelID }.filter { cachedIDSet.contains($0) })
            
            // 3. Filter cache to only valid IDs
            let originalCount = self.workCache.count
            self.workCache = self.workCache.filter { validIDSet.contains($0.value) }
            let prunedCount = originalCount - self.workCache.count

            // 4. Save pruned cache to disk
            if prunedCount > 0 {
                self.saveCacheToDisk()
                self.logger.info("Pruned \(prunedCount) stale cache entries (kept \(self.workCache.count))")
            } else {
                self.logger.info("No stale entries found, cache is healthy (\(self.workCache.count) entries)")
            }
            
        } catch {
            self.logger.error("Failed to prune cache: \(error)")
        }
    }

    // MARK: - Deduplication & Merging

    /// Find existing Work by googleBooksVolumeIDs (for deduplication)
    ///
    /// Uses PersistentIdentifier cache with on-demand fetching for robustness.
    /// Automatically detects and evicts stale cache entries when Work is deleted.
    ///
    /// Issue: https://github.com/jukasdrj/books-tracker-v1/issues/168
    private func findExistingWork(by volumeIDs: [String]) throws -> Work? {
        var didEvict = false
        
        for volumeID in volumeIDs {
            if let persistentID = workCache[volumeID] {
                // Fetch Work from ModelContext (returns nil if deleted)
                if let cachedWork = modelContext.model(for: persistentID) as? Work {
                    logger.info("Deduplication cache hit for volumeID: \(volumeID)")
                    return cachedWork
                } else {
                    // Work was deleted - evict stale entry
                    workCache.removeValue(forKey: volumeID)
                    didEvict = true
                    logger.info("Evicted stale cache entry for deleted Work with volumeID: \(volumeID)")
                }
            }
        }
        
        // Persist cache if we evicted any entries
        if didEvict {
            saveCacheToDisk()
        }
        
        logger.info("Deduplication cache miss for volumeIDs: \(volumeIDs.joined(separator: ", "))")
        return nil
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
