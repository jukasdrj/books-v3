import Foundation
import SwiftData
import SwiftUI

/// Represents a physical or digital manifestation of a work.
///
/// # SwiftUI Reactive Updates
///
/// Use `@Bindable` when observing ISBN array or format changes:
///
/// ```swift
/// struct EditionDetailView: View {
///     @Bindable var edition: Edition
///
///     var body: some View {
///         ForEach(edition.isbns, id: \.self) { isbn in  // ← Observes array changes
///             Text(isbn)
///         }
///     }
/// }
/// ```
///
/// **Why:** `@Bindable` enables SwiftData to track changes to collection properties
/// like `isbns` array and trigger view updates when items are added/removed.
@Model
public final class Edition {
    // ISBN support - now supports multiple ISBNs per edition
    var isbn: String?           // Primary ISBN (for backward compatibility)

    // For large arrays, externalStorage optimizes CloudKit sync performance
    @Attribute(.externalStorage)
    var isbns: [String] = []    // All ISBNs (ISBN-10, ISBN-13, etc.)

    var publisher: String?
    var publicationDate: String?
    var pageCount: Int?
    var format: EditionFormat = EditionFormat.hardcover
    var coverImageURL: String?
    var editionTitle: String? // "Deluxe Edition", "Abridged", etc.
    var originalLanguage: String?

    // External API identifiers for syncing and deduplication
    var openLibraryID: String?      // e.g., "OL123456M" (legacy, prefer openLibraryEditionID)
    var openLibraryEditionID: String?  // OpenLibrary Edition ID
    var isbndbID: String?          // ISBNDB edition identifier
    var googleBooksVolumeID: String? // e.g., "beSP5CCpiGUC" (same as Work for Google Books)
    var goodreadsID: String?       // Goodreads edition ID (legacy, prefer arrays)

    // Enhanced cross-reference identifiers (arrays for multiple IDs)
    @Attribute(.externalStorage)
    var amazonASINs: [String] = []           // Amazon ASINs for this specific edition

    @Attribute(.externalStorage)
    var googleBooksVolumeIDs: [String] = []  // Google Books volume IDs for this edition

    @Attribute(.externalStorage)
    var librarythingIDs: [String] = []       // LibraryThing edition identifiers

    // Cache optimization for ISBNDB integration
    var lastISBNDBSync: Date?       // When this edition was last synced with ISBNDB
    var isbndbQuality: Int = 0      // Data quality score from ISBNDB (0-100)

    // Edition-specific description (may differ from Work description)
    // Note: Can't use 'description' name (reserved by @Model macro)
    var editionDescription: String?

    // Provenance tracking for debugging and observability
    var primaryProvider: String?    // Which provider contributed this Edition

    @Attribute(.externalStorage)
    var contributors: [String] = [] // All providers that enriched this Edition

    // Metadata
    var dateCreated: Date = Date()
    var lastModified: Date = Date()

    // Relationship back to Work (inverse defined on Work side at line 37)
    var work: Work?

    // Relationship to UserLibraryEntry (CloudKit: must have inverse)
    // This is the "to-many" side of the one-to-many relationship
    @Relationship(deleteRule: .nullify, inverse: \UserLibraryEntry.edition)
    var userLibraryEntries: [UserLibraryEntry]?

    // Inverse for UserLibraryEntry.preferredEdition (CloudKit requirement)
    // Users who prefer this edition (e.g., when they own multiple editions of same work)
    @Relationship(deleteRule: .nullify, inverse: \UserLibraryEntry.preferredEdition)
    var preferringUsers: [UserLibraryEntry]?

    public init(
        isbn: String? = nil,
        publisher: String? = nil,
        publicationDate: String? = nil,
        pageCount: Int? = nil,
        format: EditionFormat = EditionFormat.hardcover,
        coverImageURL: String? = nil,
        editionTitle: String? = nil,
        editionDescription: String? = nil,
        primaryProvider: String? = nil
    ) {
        self.isbn = isbn
        self.publisher = publisher
        self.publicationDate = publicationDate
        self.pageCount = pageCount
        self.format = format
        self.coverImageURL = coverImageURL
        self.editionTitle = editionTitle
        self.editionDescription = editionDescription
        // CRITICAL: work MUST be set AFTER insert
        // Usage: let edition = Edition(); context.insert(edition); edition.work = work
        self.primaryProvider = primaryProvider
        self.contributors = []
        self.dateCreated = Date()
        self.lastModified = Date()
    }

    // MARK: - Helper Methods

    /// Display name for this edition
    var displayTitle: String {
        if let editionTitle = editionTitle, !editionTitle.isEmpty {
            return "\(work?.title ?? "Unknown") (\(editionTitle))"
        }
        return work?.title ?? "Unknown"
    }

    /// Display string for publisher info
    var publisherInfo: String {
        var info: [String] = []

        if let publisher = publisher, !publisher.isEmpty {
            info.append(publisher)
        }

        if let year = publicationDate?.prefix(4) {
            info.append(String(year))
        }

        return info.joined(separator: ", ")
    }

    /// Formatted page count string
    var pageCountString: String? {
        guard let pageCount = pageCount, pageCount > 0 else { return nil }
        return "\(pageCount) pages"
    }

    // MARK: - ISBN Management

    /// Get the primary ISBN (preferring ISBN-13, then ISBN-10, then any ISBN)
    var primaryISBN: String? {
        // Return existing primary ISBN if set
        if let isbn = isbn, !isbn.isEmpty {
            return isbn
        }

        // Find best ISBN from collection
        return bestISBN
    }

    /// Get the best ISBN from the collection (ISBN-13 preferred)
    private var bestISBN: String? {
        // Prefer ISBN-13 (13 digits)
        let isbn13 = isbns.first { $0.count == 13 && $0.allSatisfy(\.isNumber) }
        if let isbn13 = isbn13 {
            return isbn13
        }

        // Fallback to ISBN-10 (10 characters)
        let isbn10 = isbns.first { $0.count == 10 }
        if let isbn10 = isbn10 {
            return isbn10
        }

        // Return any ISBN
        return isbns.first
    }

    /// Add an ISBN to the collection (prevents duplicates)
    func addISBN(_ newISBN: String) {
        let cleanISBN = newISBN.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanISBN.isEmpty, !isbns.contains(cleanISBN) else { return }

        isbns.append(cleanISBN)

        // Set as primary ISBN if none exists
        if isbn == nil || isbn?.isEmpty == true {
            isbn = cleanISBN
        }

        touch()
    }

    /// Remove an ISBN from the collection
    func removeISBN(_ targetISBN: String) {
        isbns.removeAll { $0 == targetISBN }

        // Update primary ISBN if it was removed
        if isbn == targetISBN {
            isbn = bestISBN
        }

        touch()
    }

    /// Check if this edition has a specific ISBN
    func hasISBN(_ searchISBN: String) -> Bool {
        let cleanSearch = searchISBN.trimmingCharacters(in: .whitespacesAndNewlines)
        return isbn == cleanSearch || isbns.contains(cleanSearch)
    }

    // MARK: - External ID Management

    /// Add an Amazon ASIN if not already present
    func addAmazonASIN(_ asin: String) {
        guard !asin.isEmpty && !amazonASINs.contains(asin) else { return }
        amazonASINs.append(asin)
        touch()
    }

    /// Add a Google Books Volume ID if not already present
    func addGoogleBooksVolumeID(_ id: String) {
        guard !id.isEmpty && !googleBooksVolumeIDs.contains(id) else { return }
        googleBooksVolumeIDs.append(id)
        touch()
    }

    /// Add a LibraryThing ID if not already present
    func addLibraryThingID(_ id: String) {
        guard !id.isEmpty && !librarythingIDs.contains(id) else { return }
        librarythingIDs.append(id)
        touch()
    }

    /// Merge external IDs from API response
    func mergeExternalIDs(from crossReferenceIds: [String: Any]) {
        if let asins = crossReferenceIds["amazonASINs"] as? [String] {
            asins.forEach { addAmazonASIN($0) }
        }

        if let gbIDs = crossReferenceIds["googleBooksVolumeIds"] as? [String] {
            gbIDs.forEach { addGoogleBooksVolumeID($0) }
        }

        if let ltIDs = crossReferenceIds["librarythingIds"] as? [String] {
            ltIDs.forEach { addLibraryThingID($0) }
        }

        // Handle OpenLibrary Edition ID
        if let olEditionId = crossReferenceIds["openLibraryEditionId"] as? String, !olEditionId.isEmpty {
            self.openLibraryEditionID = olEditionId
            touch()
        }
    }

    /// Get all external IDs as a dictionary for API integration
    var externalIDsDictionary: [String: Any] {
        return [
            "openLibraryEditionId": openLibraryEditionID ?? "",
            "amazonASINs": amazonASINs,
            "googleBooksVolumeIds": googleBooksVolumeIDs,
            "librarythingIds": librarythingIDs,
            "isbndbId": isbndbID ?? ""
        ]
    }

    /// Update last modified timestamp
    func touch() {
        lastModified = Date()
    }
    
    /// Extract publication year using Calendar API when possible
    /// Falls back to string extraction if date parsing fails
    var publicationYear: String? {
        guard let dateString = publicationDate else { return nil }
        
        // Try ISO 8601 date parsing first (YYYY-MM-DD format)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withFullDate]
        
        if let date = isoFormatter.date(from: dateString) {
            let year = Calendar.current.component(.year, from: date)
            return String(year)
        }
        
        // Fallback: Extract first 4 digits (year) from string
        // Handles formats like "2020", "2020-01-01", "January 2020", etc.
        let digits = dateString.prefix(4)
        if digits.count == 4, Int(digits) != nil {
            return String(digits)
        }
        
        return nil
    }
}

// MARK: - URL Extension for Cover Images

extension Edition {
    /// Convert coverImageURL string to URL for AsyncImage
    var coverURL: URL? {
        guard let urlString = coverImageURL, !urlString.isEmpty else { return nil }
        return URL(string: urlString)
    }
}

// EditionFormat is now defined in ModelTypes.swift