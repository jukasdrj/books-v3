import Foundation
import SwiftData
import OSLog

/// Repository for managing book data persistence to SwiftData.
///
/// Handles mapping `BookDTO` objects from the API to SwiftData `Work`, `Edition`,
/// and `Author` models, with built-in deduplication and relationship management.
///
/// **Usage:**
/// ```swift
/// let repository = BookRepository(modelContainer: modelContainer, api: booksTrackAPI)
/// let workIDs = try await repository.saveImportResults(jobId: "job_123")
/// print("Saved \(workIDs.count) books to library")
/// ```
public actor BookRepository {
    private let modelContainer: ModelContainer
    private let api: BooksTrackAPI
    private let logger = Logger(subsystem: "com.oooefam.booksV3", category: "BookRepository")

    /// Initializes a new `BookRepository` instance.
    /// - Parameters:
    ///   - modelContainer: The SwiftData `ModelContainer` for creating actor-isolated contexts.
    ///   - api: The `BooksTrackAPI` instance for fetching external data.
    init(modelContainer: ModelContainer, api: BooksTrackAPI) {
        self.modelContainer = modelContainer
        self.api = api
    }

    /// Fetches import results from the API and saves the contained books to SwiftData.
    ///
    /// This method calls `BooksTrackAPI.getImportResults(jobId:)` to retrieve
    /// `ImportResults`, then iterates through the `BookDTO` array, attempting to
    /// save each book. It handles deduplication by ISBN and continues processing
    /// the batch even if individual book saves fail.
    ///
    /// - Parameter jobId: The unique identifier of the import job.
    /// - Returns: Array of `PersistentIdentifier`s for successfully saved books (for enrichment queue).
    /// - Throws: `APIError` if fetching the import results from the API fails.
    public func saveImportResults(jobId: String) async throws -> [PersistentIdentifier] {
        // Create actor-isolated ModelContext
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        logger.debug("Fetching import results for job \(jobId)")

        let importResults: ImportResults
        do {
            importResults = try await api.getImportResults(jobId: jobId)
            logger.info("Successfully fetched import results for job \(jobId). Books to process: \(importResults.books?.count ?? 0)")
        } catch {
            logger.error("Failed to fetch import results for job \(jobId): \(error.localizedDescription)")
            throw error
        }

        guard let bookDTOs = importResults.books, !bookDTOs.isEmpty else {
            logger.info("No books found in import results for job \(jobId)")
            return []
        }

        var savedWorkIDs: [PersistentIdentifier] = []
        for dto in bookDTOs {
            do {
                let work = try await saveBookDTO(dto, in: context)
                // Save after each book to ensure permanent ID
                try context.save()
                savedWorkIDs.append(work.persistentModelID)
            } catch {
                // Continue on individual book save failures (log warning, don't crash entire batch)
                logger.warning("Failed to save book '\(dto.title)' (ISBN: \(dto.isbn ?? "N/A")): \(error.localizedDescription)")
            }
        }

        logger.info("Successfully persisted changes from import job \(jobId). Total books saved: \(savedWorkIDs.count)")
        return savedWorkIDs
    }

    /// Maps a single `BookDTO` to SwiftData `Work`, `Edition`, and `Author` models.
    ///
    /// This helper method implements the core logic for translating a `BookDTO` into
    /// SwiftData entities. It includes:
    /// 1. Deduplication: Checks for existing `Edition` by ISBN. If found, returns its Work.
    /// 2. Entity Creation: Creates minimal `Work`, `Edition`, and `Author` records.
    /// 3. Insert-Before-Relate: Adheres to the SwiftData pattern of inserting all entities
    ///    into the `ModelContext` before establishing relationships between them.
    /// 4. Relationship Linking: Correctly links `Edition` to `Work`, and `Author`s to `Work`.
    ///
    /// - Parameters:
    ///   - dto: The `BookDTO` object to be mapped and saved.
    ///   - context: The actor-isolated `ModelContext` to use for persistence.
    /// - Returns: The `Work` SwiftData model that was either created or retrieved (due to deduplication).
    /// - Throws: Errors if SwiftData operations fail.
    private func saveBookDTO(_ dto: BookDTO, in context: ModelContext) async throws -> Work {
        // CRITICAL CONSTRAINT: Deduplication strategy - check for existing Edition by ISBN
        // Since Work doesn't have ISBN property, we check Edition instead
        if let isbn = dto.isbn, !isbn.isEmpty {
            let predicate = #Predicate<Edition> { edition in
                edition.isbn == isbn
            }
            var descriptor = FetchDescriptor<Edition>(predicate: predicate)
            descriptor.fetchLimit = 1

            do {
                if let existingEdition = try context.fetch(descriptor).first,
                   let existingWork = existingEdition.work {
                    logger.info("Deduplication: Found existing Edition with ISBN \(isbn) linked to Work '\(existingWork.title)'. Skipping duplicate.")
                    return existingWork
                }
            } catch {
                logger.error("Failed to fetch existing Edition by ISBN \(isbn): \(error.localizedDescription). Proceeding as new.")
            }
        }

        // CRITICAL CONSTRAINT: ALWAYS insert entities before setting relationships (insert-before-relate pattern)

        // 1. Create Work entity
        let work = Work(
            title: dto.title,
            originalLanguage: dto.language,
            synthetic: false // Imported books are "real" works
        )
        work.coverImageURL = dto.coverUrl?.absoluteString
        context.insert(work)
        logger.debug("Inserted new Work '\(work.title)'")

        // 2. Create Edition entity
        let edition = Edition(
            isbn: dto.isbn,
            publisher: dto.publisher,
            pageCount: dto.pageCount,
            coverImageURL: dto.coverUrl?.absoluteString,
            editionTitle: dto.title,
            editionDescription: dto.description,
            originalLanguage: dto.language
        )
        if let isbn = dto.isbn {
            edition.isbns.append(isbn)
        }
        context.insert(edition)
        logger.debug("Inserted new Edition for '\(dto.title)' (ISBN: \(dto.isbn ?? "N/A"))")

        // 3. Create/Find Authors and collect them
        var authors: [Author] = []
        if let authorNames = dto.authors {
            for authorName in authorNames where !authorName.isEmpty {
                // Deduplicate Author by name
                let authorPredicate = #Predicate<Author> { $0.name == authorName }
                var authorDescriptor = FetchDescriptor<Author>(predicate: authorPredicate)
                authorDescriptor.fetchLimit = 1

                do {
                    if let existingAuthor = try context.fetch(authorDescriptor).first {
                        authors.append(existingAuthor)
                        logger.debug("Found existing Author: \(authorName)")
                    } else {
                        // Create simple Author record (just name, as requested)
                        let newAuthor = Author(name: authorName)
                        context.insert(newAuthor)
                        authors.append(newAuthor)
                        logger.debug("Created new Author: \(authorName)")
                    }
                } catch {
                    logger.error("Failed to find or create Author '\(authorName)': \(error.localizedDescription)")
                }
            }
        }

        // 4. Set Relationships (after all entities have been inserted)
        // Link Edition to Work
        if work.editions == nil {
            work.editions = []
        }
        work.editions?.append(edition)
        edition.work = work

        // Link Authors to Work
        for author in authors {
            if work.authors == nil {
                work.authors = []
            }
            work.authors?.append(author)

            if author.works == nil {
                author.works = []
            }
            author.works?.append(work)
        }

        logger.info("Successfully processed and linked Work '\(work.title)'")
        return work
    }
}
