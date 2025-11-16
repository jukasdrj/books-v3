//
//  EditionTests.swift
//  BooksTrackerFeatureTests
//
//  Comprehensive test suite for Edition model
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Tests for Edition model including ISBN validation and multi-ISBN support.
///
/// **Test Coverage:**
/// - Edition initialization
/// - ISBN management (add, remove, validation, multi-ISBN)
/// - Primary ISBN selection logic (ISBN-13 preferred)
/// - External ID management (Amazon ASINs, Google Books, LibraryThing)
/// - Display helpers (displayTitle, publisherInfo, pageCountString)
/// - Publication date/year extraction
/// - Cover URL conversion
/// - Relationships with Work and UserLibraryEntry
///
/// **Architecture:**
/// - Uses in-memory SwiftData container (no persistence)
/// - All tests isolated with fresh ModelContext
/// - @MainActor for SwiftData thread safety
///
/// - SeeAlso: `Edition.swift`
@Suite("Edition Model Tests")
@MainActor
struct EditionTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!

    init() throws {
        // Create in-memory container for testing
        modelContainer = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
    }

    // MARK: - Initialization Tests

    @Test("Edition initializes with default values")
    func editionInitialization() {
        let edition = Edition()

        #expect(edition.isbn == nil)
        #expect(edition.isbns.isEmpty == true)
        #expect(edition.publisher == nil)
        #expect(edition.publicationDate == nil)
        #expect(edition.pageCount == nil)
        #expect(edition.format == .hardcover)
        #expect(edition.coverImageURL == nil)
        #expect(edition.editionTitle == nil)
    }

    @Test("Edition initializes with all parameters")
    func editionFullInitialization() {
        let edition = Edition(
            isbn: "9781234567890",
            publisher: "Test Publisher",
            publicationDate: "2024-01-15",
            pageCount: 350,
            format: .paperback,
            coverImageURL: "https://example.com/cover.jpg",
            editionTitle: "Deluxe Edition",
            editionDescription: "Special illustrated edition",
            primaryProvider: "google-books"
        )

        #expect(edition.isbn == "9781234567890")
        #expect(edition.publisher == "Test Publisher")
        #expect(edition.publicationDate == "2024-01-15")
        #expect(edition.pageCount == 350)
        #expect(edition.format == .paperback)
        #expect(edition.coverImageURL == "https://example.com/cover.jpg")
        #expect(edition.editionTitle == "Deluxe Edition")
        #expect(edition.editionDescription == "Special illustrated edition")
        #expect(edition.primaryProvider == "google-books")
    }

    // MARK: - ISBN Management Tests

    @Test("addISBN adds new ISBN to collection")
    func addISBNAddsToCollection() {
        let edition = Edition()

        edition.addISBN("9781234567890")

        #expect(edition.isbns.contains("9781234567890"))
        #expect(edition.isbns.count == 1)
    }

    @Test("addISBN prevents duplicates")
    func addISBNPreventsDuplicates() {
        let edition = Edition()

        edition.addISBN("9781234567890")
        edition.addISBN("9781234567890")  // Duplicate

        #expect(edition.isbns.count == 1, "Should not add duplicate ISBN")
    }

    @Test("addISBN trims whitespace")
    func addISBNTrimsWhitespace() {
        let edition = Edition()

        edition.addISBN("  9781234567890  ")

        #expect(edition.isbns.contains("9781234567890"))
        #expect(!edition.isbns.contains("  9781234567890  "))
    }

    @Test("addISBN ignores empty strings")
    func addISBNIgnoresEmpty() {
        let edition = Edition()

        edition.addISBN("")
        edition.addISBN("   ")

        #expect(edition.isbns.isEmpty == true)
    }

    @Test("addISBN sets primary ISBN if none exists")
    func addISBNSetsPrimary() {
        let edition = Edition()

        edition.addISBN("9781234567890")

        #expect(edition.isbn == "9781234567890", "Should set as primary ISBN")
    }

    @Test("addISBN preserves existing primary ISBN")
    func addISBNPreservesPrimary() {
        let edition = Edition(isbn: "1111111111")

        edition.addISBN("9781234567890")

        #expect(edition.isbn == "1111111111", "Should preserve existing primary ISBN")
        #expect(edition.isbns.contains("9781234567890"))
    }

    @Test("removeISBN removes from collection")
    func removeISBNRemovesFromCollection() {
        let edition = Edition()

        edition.addISBN("9781234567890")
        edition.addISBN("9780987654321")

        edition.removeISBN("9781234567890")

        #expect(!edition.isbns.contains("9781234567890"))
        #expect(edition.isbns.contains("9780987654321"))
    }

    @Test("removeISBN updates primary ISBN when removed")
    func removeISBNUpdatesPrimary() {
        let edition = Edition()

        edition.addISBN("9781234567890")  // Becomes primary
        edition.addISBN("9780987654321")

        edition.removeISBN("9781234567890")  // Remove primary

        #expect(edition.isbn == "9780987654321", "Should select new primary ISBN")
    }

    @Test("hasISBN detects ISBN in primary field")
    func hasISBNDetectsPrimary() {
        let edition = Edition(isbn: "9781234567890")

        #expect(edition.hasISBN("9781234567890") == true)
    }

    @Test("hasISBN detects ISBN in collection")
    func hasISBNDetectsCollection() {
        let edition = Edition()

        edition.addISBN("9781234567890")

        #expect(edition.hasISBN("9781234567890") == true)
    }

    @Test("hasISBN trims whitespace before checking")
    func hasISBNTrimsWhitespace() {
        let edition = Edition(isbn: "9781234567890")

        #expect(edition.hasISBN("  9781234567890  ") == true)
    }

    // MARK: - Primary ISBN Selection Tests

    @Test("primaryISBN returns existing primary field")
    func primaryISBNReturnsExisting() {
        let edition = Edition(isbn: "9781234567890")

        #expect(edition.primaryISBN == "9781234567890")
    }

    @Test("primaryISBN prefers ISBN-13 from collection")
    func primaryISBNPrefersISBN13() {
        let edition = Edition()

        edition.addISBN("1234567890")      // ISBN-10
        edition.addISBN("9780987654321")   // ISBN-13

        #expect(edition.primaryISBN == "9780987654321", "Should prefer ISBN-13")
    }

    @Test("primaryISBN falls back to ISBN-10")
    func primaryISBNFallsBackToISBN10() {
        let edition = Edition()

        edition.addISBN("1234567890")  // ISBN-10 only

        #expect(edition.primaryISBN == "1234567890")
    }

    @Test("primaryISBN returns first ISBN if no ISBN-13 or ISBN-10")
    func primaryISBNReturnsFirst() {
        let edition = Edition()

        edition.addISBN("ABC123")  // Non-standard ISBN

        #expect(edition.primaryISBN == "ABC123")
    }

    @Test("primaryISBN returns nil when no ISBNs")
    func primaryISBNNil() {
        let edition = Edition()

        #expect(edition.primaryISBN == nil)
    }

    // MARK: - External ID Management Tests

    @Test("addAmazonASIN adds new ASIN")
    func addAmazonASINAdds() {
        let edition = Edition()

        edition.addAmazonASIN("B08EXAMPLE")

        #expect(edition.amazonASINs.contains("B08EXAMPLE"))
    }

    @Test("addAmazonASIN prevents duplicates")
    func addAmazonASINPreventsDuplicates() {
        let edition = Edition()

        edition.addAmazonASIN("B08EXAMPLE")
        edition.addAmazonASIN("B08EXAMPLE")

        #expect(edition.amazonASINs.count == 1)
    }

    @Test("addAmazonASIN ignores empty strings")
    func addAmazonASINIgnoresEmpty() {
        let edition = Edition()

        edition.addAmazonASIN("")

        #expect(edition.amazonASINs.isEmpty == true)
    }

    @Test("addGoogleBooksVolumeID adds new volume ID")
    func addGoogleBooksVolumeIDAdds() {
        let edition = Edition()

        edition.addGoogleBooksVolumeID("abc123xyz")

        #expect(edition.googleBooksVolumeIDs.contains("abc123xyz"))
    }

    @Test("addGoogleBooksVolumeID prevents duplicates")
    func addGoogleBooksVolumeIDPreventsDuplicates() {
        let edition = Edition()

        edition.addGoogleBooksVolumeID("abc123xyz")
        edition.addGoogleBooksVolumeID("abc123xyz")

        #expect(edition.googleBooksVolumeIDs.count == 1)
    }

    @Test("addLibraryThingID adds new ID")
    func addLibraryThingIDAdds() {
        let edition = Edition()

        edition.addLibraryThingID("12345")

        #expect(edition.librarythingIDs.contains("12345"))
    }

    @Test("mergeExternalIDs merges all ID types")
    func mergeExternalIDsMergesAll() {
        let edition = Edition()

        let crossReferenceIds: [String: Any] = [
            "amazonASINs": ["B08ABC", "B08XYZ"],
            "googleBooksVolumeIds": ["vol1", "vol2"],
            "librarythingIds": ["lt1", "lt2"],
            "openLibraryEditionId": "OL123456M"
        ]

        edition.mergeExternalIDs(from: crossReferenceIds)

        #expect(edition.amazonASINs.count == 2)
        #expect(edition.googleBooksVolumeIDs.count == 2)
        #expect(edition.librarythingIDs.count == 2)
        #expect(edition.openLibraryEditionID == "OL123456M")
    }

    @Test("externalIDsDictionary returns all IDs")
    func externalIDsDictionaryReturnsAll() {
        let edition = Edition()

        edition.addAmazonASIN("B08ABC")
        edition.addGoogleBooksVolumeID("vol1")
        edition.openLibraryEditionID = "OL123456M"

        let dict = edition.externalIDsDictionary

        let asins = dict["amazonASINs"] as? [String]
        let volIds = dict["googleBooksVolumeIds"] as? [String]
        let olId = dict["openLibraryEditionId"] as? String

        #expect(asins?.contains("B08ABC") == true)
        #expect(volIds?.contains("vol1") == true)
        #expect(olId == "OL123456M")
    }

    // MARK: - Display Helper Tests

    @Test("displayTitle shows work title when no edition title")
    func displayTitleWorkOnly() throws {
        let work = Work(title: "The Great Book")
        let edition = Edition(isbn: "9781234567890")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        #expect(edition.displayTitle == "The Great Book")
    }

    @Test("displayTitle includes edition title when available")
    func displayTitleWithEditionTitle() throws {
        let work = Work(title: "The Great Book")
        let edition = Edition(
            isbn: "9781234567890",
            editionTitle: "Deluxe Illustrated Edition"
        )

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        #expect(edition.displayTitle == "The Great Book (Deluxe Illustrated Edition)")
    }

    @Test("displayTitle handles missing work")
    func displayTitleNoWork() {
        let edition = Edition(isbn: "9781234567890")

        #expect(edition.displayTitle == "Unknown")
    }

    @Test("publisherInfo combines publisher and year")
    func publisherInfoCombines() {
        let edition = Edition(
            publisher: "Test Publisher",
            publicationDate: "2024-01-15"
        )

        #expect(edition.publisherInfo == "Test Publisher, 2024")
    }

    @Test("publisherInfo shows publisher only when no date")
    func publisherInfoNoDate() {
        let edition = Edition(publisher: "Test Publisher")

        #expect(edition.publisherInfo == "Test Publisher")
    }

    @Test("publisherInfo shows year only when no publisher")
    func publisherInfoNoPublisher() {
        let edition = Edition(publicationDate: "2024-01-15")

        #expect(edition.publisherInfo == "2024")
    }

    @Test("publisherInfo empty when both missing")
    func publisherInfoEmpty() {
        let edition = Edition()

        #expect(edition.publisherInfo == "")
    }

    @Test("pageCountString formats page count")
    func pageCountStringFormat() {
        let edition = Edition(pageCount: 350)

        #expect(edition.pageCountString == "350 pages")
    }

    @Test("pageCountString returns nil when no page count")
    func pageCountStringNil() {
        let edition = Edition()

        #expect(edition.pageCountString == nil)
    }

    @Test("pageCountString returns nil for zero pages")
    func pageCountStringZero() {
        let edition = Edition(pageCount: 0)

        #expect(edition.pageCountString == nil)
    }

    // MARK: - Publication Year Extraction Tests

    @Test("publicationYear extracts from ISO 8601 date")
    func publicationYearISO8601() {
        let edition = Edition(publicationDate: "2024-01-15")

        #expect(edition.publicationYear == "2024")
    }

    @Test("publicationYear extracts from year-only format")
    func publicationYearOnly() {
        let edition = Edition(publicationDate: "2024")

        #expect(edition.publicationYear == "2024")
    }

    @Test("publicationYear handles various date formats")
    func publicationYearVariousFormats() {
        let edition1 = Edition(publicationDate: "2024-12-31")
        #expect(edition1.publicationYear == "2024")

        let edition2 = Edition(publicationDate: "2024")
        #expect(edition2.publicationYear == "2024")
    }

    @Test("publicationYear returns nil when no date")
    func publicationYearNil() {
        let edition = Edition()

        #expect(edition.publicationYear == nil)
    }

    @Test("publicationYear returns nil for invalid format")
    func publicationYearInvalidFormat() {
        let edition = Edition(publicationDate: "invalid date")

        #expect(edition.publicationYear == nil)
    }

    // MARK: - Cover URL Tests

    @Test("coverURL converts string to URL")
    func coverURLConverts() {
        let edition = Edition(coverImageURL: "https://example.com/cover.jpg")

        #expect(edition.coverURL != nil)
        #expect(edition.coverURL?.absoluteString == "https://example.com/cover.jpg")
    }

    @Test("coverURL returns nil for empty string")
    func coverURLEmptyString() {
        let edition = Edition(coverImageURL: "")

        #expect(edition.coverURL == nil)
    }

    @Test("coverURL returns nil when no URL")
    func coverURLNil() {
        let edition = Edition()

        #expect(edition.coverURL == nil)
    }

    @Test("coverURL returns nil for invalid URL")
    func coverURLInvalid() {
        let edition = Edition(coverImageURL: "not a valid url!!!")

        #expect(edition.coverURL == nil)
    }

    // MARK: - Touch Method Tests

    @Test("touch method updates lastModified timestamp")
    func touchUpdatesTimestamp() async throws {
        let edition = Edition()
        modelContext.insert(edition)
        try modelContext.save()

        let originalTimestamp = edition.lastModified

        // Wait briefly to ensure timestamp difference
        try await Task.sleep(for: .milliseconds(10))

        edition.touch()

        #expect(edition.lastModified > originalTimestamp, "touch() should update lastModified")
    }

    // MARK: - Relationship Tests

    @Test("Edition can reference Work")
    func editionWorkRelationship() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "9781234567890")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        #expect(edition.work === work)
    }

    @Test("Work can have multiple editions")
    func workMultipleEditions() throws {
        let work = Work(title: "Test Book")
        let edition1 = Edition(isbn: "9781111111111")
        let edition2 = Edition(isbn: "9782222222222")

        modelContext.insert(work)
        modelContext.insert(edition1)
        modelContext.insert(edition2)

        edition1.work = work
        edition2.work = work
        try modelContext.save()

        #expect(work.editions?.count == 2)
        #expect(work.editions?.contains(edition1) == true)
        #expect(work.editions?.contains(edition2) == true)
    }

    @Test("Edition can have multiple user library entries")
    func editionMultipleEntries() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "9781234567890")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        // Create multiple entries (e.g., different users or re-reads)
        let entry1 = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        let entry2 = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .read,
            context: modelContext
        )

        #expect(edition.userLibraryEntries?.count == 2)
        #expect(edition.userLibraryEntries?.contains(entry1) == true)
        #expect(edition.userLibraryEntries?.contains(entry2) == true)
    }

    @Test("Nullify delete rule preserves library entries when edition deleted")
    func deleteRuleNullify() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "9781234567890")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            context: modelContext
        )

        // Delete edition
        modelContext.delete(edition)
        try modelContext.save()

        // Entry should still exist (nullify rule)
        let descriptor = FetchDescriptor<UserLibraryEntry>()
        let entries = try modelContext.fetch(descriptor)

        #expect(entries.count == 1, "Entry should still exist after edition deletion")
        #expect(entries.first?.edition == nil, "Entry's edition should be nil")
    }

    // MARK: - Metadata Tests

    @Test("dateCreated is set on initialization")
    func dateCreatedSet() {
        let beforeCreate = Date()
        let edition = Edition()
        let afterCreate = Date()

        #expect(edition.dateCreated >= beforeCreate)
        #expect(edition.dateCreated <= afterCreate)
    }

    @Test("lastModified is set on initialization")
    func lastModifiedSet() {
        let beforeCreate = Date()
        let edition = Edition()
        let afterCreate = Date()

        #expect(edition.lastModified >= beforeCreate)
        #expect(edition.lastModified <= afterCreate)
    }

    // MARK: - ISBNDB Quality Tests

    @Test("isbndbQuality defaults to 0")
    func isbndbQualityDefault() {
        let edition = Edition()

        #expect(edition.isbndbQuality == 0)
    }

    @Test("isbndbQuality can be set and retrieved")
    func isbndbQualitySetAndGet() {
        let edition = Edition()

        edition.isbndbQuality = 85

        #expect(edition.isbndbQuality == 85)
    }

    @Test("lastISBNDBSync can be set and retrieved")
    func lastISBNDBSyncSetAndGet() {
        let edition = Edition()
        let syncDate = Date()

        edition.lastISBNDBSync = syncDate

        #expect(edition.lastISBNDBSync == syncDate)
    }

    // MARK: - Provenance Tests

    @Test("primaryProvider can be set and retrieved")
    func primaryProviderSetAndGet() {
        let edition = Edition(primaryProvider: "google-books")

        #expect(edition.primaryProvider == "google-books")
    }

    @Test("contributors array starts empty")
    func contributorsStartsEmpty() {
        let edition = Edition()

        #expect(edition.contributors.isEmpty == true)
    }

    @Test("contributors can be populated")
    func contributorsPopulated() {
        let edition = Edition()

        edition.contributors = ["google-books", "openlibrary", "isbndb"]

        #expect(edition.contributors.count == 3)
        #expect(edition.contributors.contains("google-books"))
    }
}
