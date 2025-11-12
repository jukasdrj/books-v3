import Foundation
import SwiftData

// Import GeminiCSVImportJob for ParsedBook type
// Note: File is in same package, so no additional import needed beyond internal visibility

/// Result of background import operation.
/// Sendable for safe transfer from actor to @MainActor.
public struct ImportResult: Sendable {
    public let successCount: Int
    public let failedCount: Int
    public let skippedCount: Int
    public let newWorkIDs: [PersistentIdentifier]
    public let errors: [ImportServiceError]
    public let duration: TimeInterval

    public var totalProcessed: Int { successCount + failedCount + skippedCount }

    public init(
        successCount: Int,
        failedCount: Int,
        skippedCount: Int,
        newWorkIDs: [PersistentIdentifier],
        errors: [ImportServiceError],
        duration: TimeInterval
    ) {
        self.successCount = successCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.newWorkIDs = newWorkIDs
        self.errors = errors
        self.duration = duration
    }
}

/// Individual import error with book context.
/// Renamed from ImportError to avoid collision with WebSocketMessages.ImportError
public struct ImportServiceError: Sendable, Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

/// Actor-isolated import service for background data insertion.
///
/// Prevents UI blocking during large CSV imports and bookshelf scans by
/// performing SwiftData insertions on a background thread with its own ModelContext.
///
/// # Usage
///
/// ```swift
/// @MainActor
/// func importBooks(_ dtos: [WorkDTO]) async {
///     let service = ImportService(modelContainer: modelContainer)
///
///     do {
///         let result = try await service.importWorks(dtos)
///         print("Imported \(result.successCount) books")
///     } catch {
///         print("Import failed: \(error)")
///     }
/// }
/// ```
///
/// # CloudKit Sync
///
/// Changes made in the actor's background ModelContext are saved to the persistent
/// store. SwiftData automatically notifies the main ModelContext, which then merges
/// the changes, ensuring UI consistency.
///
/// # Performance
///
/// For 100+ book imports:
/// - Main thread: Blocks UI for 30-60 seconds
/// - Background import: UI remains responsive throughout
public actor ImportService {
    private let modelContainer: ModelContainer

    public init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Imports CSV parsed books in background without blocking main thread.
    ///
    /// Simplified import for Gemini CSV parsing results. Each book is inserted
    /// individually with deduplication and error handling per-book.
    ///
    /// - Parameter books: Parsed books from Gemini CSV import
    /// - Returns: Import result with success/failure counts and per-book errors
    /// - Throws: `SwiftDataError` if context save fails
    public func importCSVBooks(
        _ books: [GeminiCSVImportJob.ParsedBook]
    ) async throws -> ImportResult {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.automaticallyMergesChangesFromParent = true // CloudKit sync integrity

        var successCount = 0
        var skippedCount = 0
        var importErrors: [ImportServiceError] = []
        var newWorks: [Work] = []
        let startTime = ContinuousClock.now

        // Fetch existing works for deduplication (in background context)
        let descriptor = FetchDescriptor<Work>()
        let allWorks = try context.fetch(descriptor)

        for book in books {
            do {
                // Check for duplicate by title + author (case-insensitive, exact match)
                let titleLower = book.title.lowercased()
                let authorLower = book.author.lowercased()

                let isDuplicate = allWorks.contains { work in
                    let workTitleLower = work.title.lowercased()
                    let workAuthorLower = work.authorNames.lowercased()
                    return workTitleLower == titleLower && workAuthorLower == authorLower
                }

                if isDuplicate {
                    skippedCount += 1
                    continue
                }

                // Create Author FIRST and insert
                let author = Author(name: book.author)
                context.insert(author)

                // Create Work, insert, then set relationship
                let work = Work(
                    title: book.title,
                    originalLanguage: "Unknown",
                    firstPublicationYear: book.publicationYear
                )
                context.insert(work)
                work.authors = [author]

                // Create UserLibraryEntry so book appears in library
                let libraryEntry = UserLibraryEntry(readingStatus: .toRead)
                context.insert(libraryEntry)
                libraryEntry.work = work

                // Create Edition if ISBN provided
                if let isbn = book.isbn {
                    let edition = Edition(
                        isbn: isbn,
                        publisher: book.publisher,
                        publicationDate: book.publicationYear.map { "\($0)" },
                        pageCount: nil,
                        format: .paperback,
                        coverImageURL: book.coverUrl
                    )
                    context.insert(edition)
                    edition.work = work
                }

                // Collect work for batch save
                newWorks.append(work)
                successCount += 1
            } catch {
                // Per-book error handling: one bad book doesn't crash entire import
                importErrors.append(ImportServiceError(
                    title: book.title,
                    message: "Failed to process: \(error.localizedDescription)"
                ))
            }
        }

        // Single batch save (much faster than saving in loop)
        try context.save()

        // Extract permanent IDs after save
        let newWorkIDs = newWorks.map { $0.persistentModelID }

        let duration = startTime.duration(to: ContinuousClock.now)
        return ImportResult(
            successCount: successCount,
            failedCount: importErrors.count,
            skippedCount: skippedCount,
            newWorkIDs: newWorkIDs,
            errors: importErrors,
            duration: duration.timeInterval
        )
    }

    // NOTE: importWorks() for WorkDTO will be added when bookshelf scanner is refactored
    // For now, only CSV import (importCSVBooks) is implemented
}

// Extension to convert Duration to TimeInterval
private extension ContinuousClock.Duration {
    /// Number of attoseconds in one second (1e18).
    private static let attosecondsPerSecond: Double = 1e18

    var timeInterval: TimeInterval {
        let seconds = self.components.seconds
        let attoseconds = self.components.attoseconds
        return Double(seconds) + (Double(attoseconds) / Self.attosecondsPerSecond)
    }
}
