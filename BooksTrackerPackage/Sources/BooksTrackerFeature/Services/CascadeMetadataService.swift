import SwiftData
import Foundation
import OSLog

/// Errors specific to the CascadeMetadataService.
public enum CascadeMetadataServiceError: Error, LocalizedError {
    case authorMetadataNotFound
    case workNotFound
    case bookEnrichmentNotFound
    case invalidFieldForOverride(String)
    case authorNotFoundForWork(String)
    case workHasNoPrimaryAuthor

    public var errorDescription: String? {
        switch self {
        case .authorMetadataNotFound:
            return "Author metadata not found for the given author ID."
        case .workNotFound:
            return "Work not found in the database."
        case .bookEnrichmentNotFound:
            return "Book enrichment data not found."
        case .invalidFieldForOverride(let field):
            return "Invalid field '\(field)' specified for metadata override."
        case .authorNotFoundForWork(let workId):
            return "Author not found for work with ID: \(workId)."
        case .workHasNoPrimaryAuthor:
            return "The work does not have a primary author to apply metadata to."
        }
    }
}

/// Service responsible for managing metadata cascading from authors to works and handling work-specific overrides.
@MainActor
public final class CascadeMetadataService {
    private let modelContext: ModelContext
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "CascadeMetadata")

    /// Initializes the service with the required ModelContext for persistence.
    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Core Cascade Operations

    /// Updates or creates AuthorMetadata for a given author and triggers cascading to associated works.
    /// - Parameters:
    ///   - authorId: The unique identifier for the author.
    ///   - culturalBackground: Optional array of cultural background strings.
    ///   - genderIdentity: Optional gender identity string.
    ///   - nationality: Optional array of nationality strings.
    ///   - languages: Optional array of language strings.
    ///   - marginalizedIdentities: Optional array of marginalized identity strings.
    ///   - userId: The ID of the user contributing this metadata.
    /// - Throws: `CascadeMetadataServiceError` if an operation fails.
    public func updateAuthorMetadata(
        authorId: String,
        culturalBackground: [String]? = nil,
        genderIdentity: String? = nil,
        nationality: [String]? = nil,
        languages: [String]? = nil,
        marginalizedIdentities: [String]? = nil,
        userId: String
    ) async throws {
        logger.info("Updating author metadata for author ID: \(authorId)")
        let authorMetadata = try fetchOrCreateAuthorMetadata(authorId: authorId, userId: userId)

        // Update fields if provided
        if let culturalBackground {
            authorMetadata.culturalBackground = culturalBackground
        }
        if let genderIdentity {
            authorMetadata.genderIdentity = genderIdentity
        }
        if let nationality {
            authorMetadata.nationality = nationality
        }
        if let languages {
            authorMetadata.languages = languages
        }
        if let marginalizedIdentities {
            authorMetadata.marginalizedIdentities = marginalizedIdentities
        }

        authorMetadata.lastUpdated = Date()

        try modelContext.save()
        logger.info("Author metadata updated for author ID: \(authorId). Initiating cascade.")

        // Trigger cascade to all associated works
        try await cascadeToWorks(authorId: authorId, metadata: authorMetadata)
    }

    /// Cascades the provided AuthorMetadata to all works associated with the author.
    /// This involves finding all works by the author and updating their BookEnrichment.
    /// - Parameters:
    ///   - authorId: The unique identifier for the author.
    ///   - metadata: The AuthorMetadata object to cascade.
    /// - Throws: `CascadeMetadataServiceError` if works cannot be fetched or enrichment fails.
    public func cascadeToWorks(authorId: String, metadata: AuthorMetadata) async throws {
        logger.info("Cascading metadata from author ID: \(authorId) to associated works.")

        // Fetch all Works that have this author
        let descriptor = FetchDescriptor<Work>()
        let allWorks = try modelContext.fetch(descriptor)

        var updatedWorkIDs: Set<String> = []

        for work in allWorks {
            // Check if this work is associated with the authorId
            // Work.authors is [Author]? - compare stable UUID
            guard let authors = work.authors else { continue }
            let isAuthorOfWork = authors.contains(where: { $0.uuid.uuidString == authorId })

            if isAuthorOfWork {
                let workId = work.uuid.uuidString
                logger.debug("Updating enrichment for work ID: \(workId) due to author cascade.")
                try await updateWorkEnrichment(work: work, metadata: metadata)
                updatedWorkIDs.insert(workId)
            }
        }

        // Update cascadedToWorkIds in AuthorMetadata
        metadata.cascadedToWorkIds = Array(updatedWorkIDs)
        try modelContext.save()
        logger.info("Metadata cascaded to \(updatedWorkIDs.count) works for author ID: \(authorId).")
    }

    /// Updates the BookEnrichment for a specific work based on cascaded AuthorMetadata,
    /// respecting any existing WorkOverrides.
    /// - Parameters:
    ///   - work: The Work model to update enrichment for.
    ///   - metadata: The AuthorMetadata to apply.
    /// - Throws: `CascadeMetadataServiceError` if enrichment cannot be fetched or updated.
    public func updateWorkEnrichment(work: Work, metadata: AuthorMetadata) async throws {
        let workId = work.uuid.uuidString
        let bookEnrichment = try fetchOrCreateEnrichment(workId: workId)

        // Fetch overrides for this specific work and author
        let targetAuthorId = metadata.authorId
        let targetWorkId = workId
        let overrideDescriptor = FetchDescriptor<WorkOverride>(
            predicate: #Predicate<WorkOverride> { override in
                override.workId == targetWorkId
            }
        )
        let allOverrides = try modelContext.fetch(overrideDescriptor)
        let overrides = allOverrides.filter { $0.authorMetadata?.authorId == targetAuthorId }
        let overrideMap: [String: String] = Dictionary(uniqueKeysWithValues: overrides.map { ($0.field, $0.customValue) })

        // Apply cascaded metadata, respecting overrides
        bookEnrichment.authorCulturalBackground = overrideMap["culturalBackground"] ?? metadata.culturalBackground.first
        bookEnrichment.authorGenderIdentity = overrideMap["genderIdentity"] ?? metadata.genderIdentity

        bookEnrichment.isCascaded = true
        bookEnrichment.lastEnriched = Date()

        try modelContext.save()
        logger.debug("Book enrichment updated for work ID: \(workId) based on cascaded metadata.")
    }

    // MARK: - Override Management

    /// Creates a work-specific override for cascaded author metadata.
    /// - Parameters:
    ///   - authorId: The ID of the author whose metadata is being overridden.
    ///   - workId: The ID of the work for which the override applies.
    ///   - field: The specific field being overridden (e.g., "culturalBackground", "genderIdentity").
    ///   - customValue: The custom value for the field.
    ///   - reason: An optional reason for the override.
    /// - Throws: `CascadeMetadataServiceError.authorMetadataNotFound` if author metadata doesn't exist,
    ///           `CascadeMetadataServiceError.invalidFieldForOverride` for an unrecognized field.
    public func createOverride(
        authorId: String,
        workId: String,
        field: String,
        customValue: String,
        reason: String?
    ) throws {
        logger.info("Creating override for author ID: \(authorId), work ID: \(workId), field: \(field).")

        guard let authorMetadata = try? fetchOrCreateAuthorMetadata(authorId: authorId, userId: "system") else {
            throw CascadeMetadataServiceError.authorMetadataNotFound
        }

        // Validate field
        let validFields = ["culturalBackground", "genderIdentity"]
        guard validFields.contains(field) else {
            throw CascadeMetadataServiceError.invalidFieldForOverride(field)
        }

        // Check if an override for this field already exists, update if so.
        let targetWorkId = workId
        let targetField = field
        let existingOverrideDescriptor = FetchDescriptor<WorkOverride>(
            predicate: #Predicate<WorkOverride> { override in
                override.workId == targetWorkId && override.field == targetField
            }
        )
        let candidateOverrides = try modelContext.fetch(existingOverrideDescriptor)
        if let existingOverride = candidateOverrides.first(where: { $0.authorMetadata?.authorId == authorId }) {
            existingOverride.customValue = customValue
            existingOverride.reason = reason
            existingOverride.createdAt = Date()
            logger.debug("Updated existing override for field: \(field).")
        } else {
            let newOverride = WorkOverride(
                workId: workId,
                field: field,
                customValue: customValue,
                reason: reason,
                createdAt: Date(),
                authorMetadata: authorMetadata
            )
            modelContext.insert(newOverride)
            logger.debug("Created new override for field: \(field).")
        }

        try modelContext.save()
        logger.info("Override saved for author ID: \(authorId), work ID: \(workId).")
    }

    /// Removes a specific work-level override for author metadata.
    /// - Parameters:
    ///   - authorId: The ID of the author whose override is being removed.
    ///   - workId: The ID of the work from which the override is removed.
    ///   - field: The field for which the override is removed.
    /// - Throws: `CascadeMetadataServiceError.authorMetadataNotFound` if author metadata doesn't exist.
    public func removeOverride(authorId: String, workId: String, field: String) async throws {
        logger.info("Removing override for author ID: \(authorId), work ID: \(workId), field: \(field).")

        guard let authorMetadata = try? fetchOrCreateAuthorMetadata(authorId: authorId, userId: "system") else {
            throw CascadeMetadataServiceError.authorMetadataNotFound
        }

        let targetWorkId = workId
        let targetField = field
        let overrideDescriptor = FetchDescriptor<WorkOverride>(
            predicate: #Predicate<WorkOverride> { override in
                override.workId == targetWorkId && override.field == targetField
            }
        )
        let candidateOverrides = try modelContext.fetch(overrideDescriptor)
        if let overrideToDelete = candidateOverrides.first(where: { $0.authorMetadata?.authorId == authorId }) {
            modelContext.delete(overrideToDelete)
            try modelContext.save()
            logger.debug("Override for field '\(field)' removed.")

            // Re-apply enrichment for this specific work to revert to cascaded data
            let allWorksDescriptor = FetchDescriptor<Work>()
            let allWorks = try modelContext.fetch(allWorksDescriptor)
            if let work = allWorks.first(where: { $0.uuid.uuidString == workId }) {
                try await updateWorkEnrichment(work: work, metadata: authorMetadata)
            } else {
                logger.warning("Could not find Work for workId \(workId) to re-apply enrichment after override removal.")
            }
        } else {
            logger.info("No override found for author ID: \(authorId), work ID: \(workId), field: \(field). No action taken.")
        }
    }

    // MARK: - Helper Methods

    /// Fetches an existing AuthorMetadata object or creates a new one if not found.
    /// - Parameters:
    ///   - authorId: The unique identifier for the author.
    ///   - userId: The ID of the user contributing this metadata (used for new creation).
    /// - Returns: The existing or newly created AuthorMetadata object.
    /// - Throws: `Error` if fetching or saving fails.
    public func fetchOrCreateAuthorMetadata(authorId: String, userId: String) throws -> AuthorMetadata {
        let descriptor = FetchDescriptor<AuthorMetadata>(
            predicate: #Predicate { $0.authorId == authorId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        } else {
            logger.info("Creating new AuthorMetadata for author ID: \(authorId).")
            let newMetadata = AuthorMetadata(authorId: authorId, contributedBy: userId)
            modelContext.insert(newMetadata)
            return newMetadata
        }
    }

    /// Fetches an existing BookEnrichment object for a work or creates a new one if not found.
    /// - Parameter workId: The unique identifier for the work.
    /// - Returns: The existing or newly created BookEnrichment object.
    /// - Throws: `Error` if fetching or saving fails.
    public func fetchOrCreateEnrichment(workId: String) throws -> BookEnrichment {
        let descriptor = FetchDescriptor<BookEnrichment>(
            predicate: #Predicate { $0.workId == workId }
        )

        if let existing = try modelContext.fetch(descriptor).first {
            return existing
        } else {
            logger.info("Creating new BookEnrichment for work ID: \(workId).")
            let newEnrichment = BookEnrichment(workId: workId)
            modelContext.insert(newEnrichment)
            return newEnrichment
        }
    }
}
