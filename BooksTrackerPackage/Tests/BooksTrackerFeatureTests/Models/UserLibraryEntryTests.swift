//
//  UserLibraryEntryTests.swift
//  BooksTrackerFeatureTests
//
//  Comprehensive test suite for UserLibraryEntry model
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Tests for UserLibraryEntry model including reading status and progress tracking.
///
/// **Test Coverage:**
/// - Entry initialization (wishlist and owned)
/// - Reading status transitions
/// - Progress tracking and auto-completion
/// - Wishlist vs owned logic
/// - Reading pace calculations
/// - Estimated finish date
/// - Rating validation
/// - Factory methods (createWishlistEntry, createOwnedEntry)
/// - Relationships with Work and Edition
///
/// **Architecture:**
/// - Uses in-memory SwiftData container (no persistence)
/// - All tests isolated with fresh ModelContext
/// - @MainActor for SwiftData thread safety
///
/// - SeeAlso: `UserLibraryEntry.swift`
@Suite("UserLibraryEntry Model Tests")
@MainActor
struct UserLibraryEntryTests {

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

    @Test("UserLibraryEntry initializes with default reading status")
    func entryInitialization() {
        let entry = UserLibraryEntry()

        #expect(entry.readingStatus == .toRead)
        #expect(entry.currentPage == 0)
        #expect(entry.readingProgress == 0.0)
        #expect(entry.rating == nil)
        #expect(entry.personalRating == nil)
        #expect(entry.notes == nil)
        #expect(entry.tags.isEmpty == true)
    }

    @Test("UserLibraryEntry can initialize with specific status")
    func entryInitializationWithStatus() {
        let entry = UserLibraryEntry(readingStatus: .reading)

        #expect(entry.readingStatus == .reading)
    }

    // MARK: - Factory Method Tests

    @Test("createWishlistEntry creates entry with wishlist status")
    func createWishlistEntry() throws {
        let work = Work(title: "Wishlist Book")
        modelContext.insert(work)
        try modelContext.save()

        let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

        #expect(entry.readingStatus == .wishlist)
        #expect(entry.work === work)
        #expect(entry.edition == nil, "Wishlist entries should not have an edition")
    }

    @Test("createOwnedEntry creates entry with edition and specified status")
    func createOwnedEntry() throws {
        let work = Work(title: "Owned Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .toRead,
            context: modelContext
        )

        #expect(entry.readingStatus == .toRead)
        #expect(entry.work === work)
        #expect(entry.edition === edition)
    }

    @Test("createOwnedEntry defaults to toRead status")
    func createOwnedEntryDefaultStatus() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            context: modelContext
        )

        #expect(entry.readingStatus == .toRead)
    }

    // MARK: - Wishlist vs Owned Tests

    @Test("isWishlistItem returns true for wishlist entries without edition")
    func isWishlistItemTrue() throws {
        let work = Work(title: "Wishlist Book")
        modelContext.insert(work)
        try modelContext.save()

        let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

        #expect(entry.isWishlistItem == true)
        #expect(entry.isOwned == false)
    }

    @Test("isWishlistItem returns false for owned entries")
    func isWishlistItemFalse() throws {
        let work = Work(title: "Owned Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            context: modelContext
        )

        #expect(entry.isWishlistItem == false)
        #expect(entry.isOwned == true)
    }

    @Test("acquireEdition converts wishlist to owned")
    func acquireEditionConversion() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

        #expect(entry.isWishlistItem == true)

        // Acquire edition
        entry.acquireEdition(edition, status: .toRead)

        #expect(entry.isWishlistItem == false)
        #expect(entry.isOwned == true)
        #expect(entry.edition === edition)
        #expect(entry.readingStatus == .toRead)
    }

    @Test("acquireEdition does nothing if not wishlist entry")
    func acquireEditionIgnoresNonWishlist() throws {
        let work = Work(title: "Test Book")
        let edition1 = Edition(isbn: "1111111111111")
        let edition2 = Edition(isbn: "2222222222222")

        modelContext.insert(work)
        modelContext.insert(edition1)
        modelContext.insert(edition2)

        edition1.work = work
        edition2.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition1,
            status: .reading,
            context: modelContext
        )

        // Try to acquire different edition (should be ignored)
        entry.acquireEdition(edition2, status: .toRead)

        #expect(entry.edition === edition1, "Edition should not change")
        #expect(entry.readingStatus == .reading, "Status should not change")
    }

    // MARK: - Reading Progress Tests

    @Test("updateReadingProgress calculates progress correctly")
    func updateReadingProgressCalculation() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        entry.currentPage = 150
        entry.updateReadingProgress()

        #expect(entry.readingProgress == 0.5, "Progress should be 50%")
    }

    @Test("updateReadingProgress auto-completes at 100%")
    func updateReadingProgressAutoComplete() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        entry.currentPage = 300
        entry.updateReadingProgress()

        #expect(entry.readingProgress == 1.0)
        #expect(entry.readingStatus == .read, "Should auto-complete to .read")
        #expect(entry.dateCompleted != nil, "Completion date should be set")
    }

    @Test("updateReadingProgress handles wishlist entries gracefully")
    func updateReadingProgressWishlist() throws {
        let work = Work(title: "Wishlist Book")
        modelContext.insert(work)
        try modelContext.save()

        let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

        entry.currentPage = 100
        entry.updateReadingProgress()

        #expect(entry.readingProgress == 0.0, "Wishlist entries should have 0 progress")
    }

    @Test("updateReadingProgress handles missing page count")
    func updateReadingProgressNoPageCount() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")  // No page count

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        entry.currentPage = 100
        entry.updateReadingProgress()

        #expect(entry.readingProgress == 0.0, "Should be 0 when page count unknown")
    }

    @Test("updateReadingProgress caps at 100%")
    func updateReadingProgressCapsAt100() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        entry.currentPage = 400  // More than page count
        entry.updateReadingProgress()

        #expect(entry.readingProgress == 1.0, "Progress should cap at 100%")
    }

    // MARK: - Reading Status Transition Tests

    @Test("startReading transitions from toRead to reading")
    func startReadingTransition() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .toRead,
            context: modelContext
        )

        #expect(entry.dateStarted == nil)

        entry.startReading()

        #expect(entry.readingStatus == .reading)
        #expect(entry.dateStarted != nil, "dateStarted should be set")
    }

    @Test("startReading does nothing for wishlist entries")
    func startReadingIgnoresWishlist() throws {
        let work = Work(title: "Wishlist Book")
        modelContext.insert(work)
        try modelContext.save()

        let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

        entry.startReading()

        #expect(entry.readingStatus == .wishlist, "Status should remain wishlist")
        #expect(entry.dateStarted == nil, "dateStarted should not be set")
    }

    @Test("startReading preserves existing dateStarted")
    func startReadingPreservesDateStarted() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .toRead,
            context: modelContext
        )

        let pastDate = Date(timeIntervalSince1970: 1000000)
        entry.dateStarted = pastDate

        entry.startReading()

        #expect(entry.dateStarted == pastDate, "Existing dateStarted should be preserved")
    }

    @Test("markAsCompleted sets completion status and dates")
    func markAsCompletedSetsDates() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        entry.currentPage = 150
        entry.markAsCompleted()

        #expect(entry.readingStatus == .read)
        #expect(entry.readingProgress == 1.0)
        #expect(entry.dateCompleted != nil)
        #expect(entry.dateStarted != nil)
        #expect(entry.currentPage == 300, "Current page should be set to page count")
    }

    @Test("markAsCompleted preserves existing completion date")
    func markAsCompletedPreservesDate() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        let pastDate = Date(timeIntervalSince1970: 1000000)
        entry.dateCompleted = pastDate

        entry.markAsCompleted()

        #expect(entry.dateCompleted == pastDate, "Existing dateCompleted should be preserved")
    }

    // MARK: - Reading Pace Tests

    @Test("readingPace calculates pages per day correctly")
    func readingPaceCalculation() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        // Started 10 days ago, read 100 pages
        entry.dateStarted = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        entry.currentPage = 100

        let pace = entry.readingPace

        #expect(pace != nil)
        #expect(pace! >= 9.9 && pace! <= 10.1, "Pace should be ~10 pages/day")
    }

    @Test("readingPace returns nil when no dateStarted")
    func readingPaceNoDateStarted() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .toRead,
            context: modelContext
        )

        entry.currentPage = 100

        #expect(entry.readingPace == nil)
    }

    @Test("readingPace returns nil when currentPage is 0")
    func readingPaceNoProgress() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        entry.dateStarted = Date()

        #expect(entry.readingPace == nil)
    }

    // MARK: - Estimated Finish Date Tests

    @Test("calculateEstimatedFinishDate estimates correctly")
    func estimatedFinishDateCalculation() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        // Started 10 days ago, read 100 pages (10 pages/day)
        // 200 pages remaining = 20 days to finish
        entry.dateStarted = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        entry.currentPage = 100

        entry.calculateEstimatedFinishDate()

        #expect(entry.estimatedFinishDate != nil)

        // Should be approximately 20 days in the future
        let daysToFinish = Calendar.current.dateComponents(
            [.day],
            from: Date(),
            to: entry.estimatedFinishDate!
        ).day ?? 0

        #expect(daysToFinish >= 19 && daysToFinish <= 21, "Should estimate ~20 days to finish")
    }

    @Test("calculateEstimatedFinishDate returns nil when no pace")
    func estimatedFinishDateNoPace() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .toRead,
            context: modelContext
        )

        entry.calculateEstimatedFinishDate()

        #expect(entry.estimatedFinishDate == nil)
    }

    @Test("calculateEstimatedFinishDate returns nil when already finished")
    func estimatedFinishDateAlreadyFinished() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123", pageCount: 300)

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        entry.dateStarted = Calendar.current.date(byAdding: .day, value: -10, to: Date())
        entry.currentPage = 300  // Finished

        entry.calculateEstimatedFinishDate()

        #expect(entry.estimatedFinishDate == nil, "Should be nil when book is finished")
    }

    // MARK: - Validation Tests

    @Test("validateRating accepts valid ratings")
    func validateRatingValid() {
        let entry = UserLibraryEntry()

        entry.rating = 1
        #expect(entry.validateRating() == true)

        entry.rating = 3
        #expect(entry.validateRating() == true)

        entry.rating = 5
        #expect(entry.validateRating() == true)
    }

    @Test("validateRating rejects invalid ratings")
    func validateRatingInvalid() {
        let entry = UserLibraryEntry()

        entry.rating = 0
        #expect(entry.validateRating() == false)

        entry.rating = 6
        #expect(entry.validateRating() == false)

        entry.rating = -1
        #expect(entry.validateRating() == false)
    }

    @Test("validateRating accepts nil rating")
    func validateRatingNil() {
        let entry = UserLibraryEntry()

        entry.rating = nil
        #expect(entry.validateRating() == true)
    }

    @Test("validateNotes accepts valid notes")
    func validateNotesValid() {
        let entry = UserLibraryEntry()

        entry.notes = "Great book!"
        #expect(entry.validateNotes() == true)

        entry.notes = String(repeating: "a", count: 2000)  // Max length
        #expect(entry.validateNotes() == true)
    }

    @Test("validateNotes rejects too long notes")
    func validateNotesTooLong() {
        let entry = UserLibraryEntry()

        entry.notes = String(repeating: "a", count: 2001)  // Over max
        #expect(entry.validateNotes() == false)
    }

    @Test("validateNotes accepts nil notes")
    func validateNotesNil() {
        let entry = UserLibraryEntry()

        entry.notes = nil
        #expect(entry.validateNotes() == true)
    }

    // MARK: - AI Confidence Tests

    @Test("AI confidence can be set and retrieved")
    func aiConfidenceSetAndGet() {
        let entry = UserLibraryEntry()

        entry.aiConfidence = 0.85
        entry.aiConfidenceDate = Date()

        #expect(entry.aiConfidence == 0.85)
        #expect(entry.aiConfidenceDate != nil)
    }

    @Test("AI confidence is nil for manually added books")
    func aiConfidenceNilForManual() {
        let entry = UserLibraryEntry()

        #expect(entry.aiConfidence == nil)
        #expect(entry.aiConfidenceDate == nil)
    }

    // MARK: - Touch Method Tests

    @Test("touch method updates lastModified timestamp")
    func touchUpdatesTimestamp() async throws {
        let entry = UserLibraryEntry()
        modelContext.insert(entry)
        try modelContext.save()

        let originalTimestamp = entry.lastModified

        // Wait briefly to ensure timestamp difference
        try await Task.sleep(for: .milliseconds(10))

        entry.touch()

        #expect(entry.lastModified > originalTimestamp, "touch() should update lastModified")
    }

    // MARK: - Relationship Tests

    @Test("Entry can reference work")
    func entryWorkRelationship() throws {
        let work = Work(title: "Test Book")
        modelContext.insert(work)
        try modelContext.save()

        let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

        #expect(entry.work === work)
    }

    @Test("Entry can reference edition")
    func entryEditionRelationship() throws {
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "1234567890123")

        modelContext.insert(work)
        modelContext.insert(edition)

        edition.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            context: modelContext
        )

        #expect(entry.edition === edition)
    }

    @Test("Entry can have preferred edition")
    func entryPreferredEdition() throws {
        let work = Work(title: "Test Book")
        let edition1 = Edition(isbn: "1111111111111")
        let edition2 = Edition(isbn: "2222222222222")

        modelContext.insert(work)
        modelContext.insert(edition1)
        modelContext.insert(edition2)

        edition1.work = work
        edition2.work = work
        try modelContext.save()

        let entry = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition1,
            context: modelContext
        )

        entry.preferredEdition = edition2

        #expect(entry.preferredEdition === edition2)
    }
}

// MARK: - ReadingStatus Enum Tests

@Suite("ReadingStatus Enum Tests")
struct ReadingStatusTests {

    @Test("All reading statuses have correct raw values")
    func readingStatusRawValues() {
        #expect(ReadingStatus.wishlist.rawValue == "Wishlist")
        #expect(ReadingStatus.toRead.rawValue == "TBR")
        #expect(ReadingStatus.reading.rawValue == "Reading")
        #expect(ReadingStatus.read.rawValue == "Read")
        #expect(ReadingStatus.onHold.rawValue == "On Hold")
        #expect(ReadingStatus.dnf.rawValue == "DNF")
    }

    @Test("All reading statuses have display names")
    func readingStatusDisplayNames() {
        #expect(ReadingStatus.wishlist.displayName == "Wishlist")
        #expect(ReadingStatus.toRead.displayName == "To Read")
        #expect(ReadingStatus.reading.displayName == "Reading")
        #expect(ReadingStatus.read.displayName == "Read")
        #expect(ReadingStatus.onHold.displayName == "On Hold")
        #expect(ReadingStatus.dnf.displayName == "Did Not Finish")
    }

    @Test("All reading statuses have descriptions")
    func readingStatusDescriptions() {
        #expect(ReadingStatus.wishlist.description == "Want to have or read, but don't have")
        #expect(ReadingStatus.toRead.description == "Have it and want to read in the future")
        #expect(ReadingStatus.reading.description == "Currently reading")
        #expect(ReadingStatus.read.description == "Finished reading")
    }

    @Test("All reading statuses have SF Symbol icons")
    func readingStatusIcons() {
        #expect(ReadingStatus.wishlist.systemImage == "heart")
        #expect(ReadingStatus.toRead.systemImage == "book")
        #expect(ReadingStatus.reading.systemImage == "book.pages")
        #expect(ReadingStatus.read.systemImage == "checkmark.circle.fill")
        #expect(ReadingStatus.onHold.systemImage == "pause.circle")
        #expect(ReadingStatus.dnf.systemImage == "xmark.circle")
    }

    @Test("Reading status from string parsing delegates to parser")
    func readingStatusFromString() {
        // This tests the delegation to ReadingStatusParser
        // ReadingStatusParser has its own comprehensive test suite

        let result1 = ReadingStatus.from(string: "wishlist")
        #expect(result1 == .wishlist)

        let result2 = ReadingStatus.from(string: "currently reading")
        #expect(result2 == .reading)

        let result3 = ReadingStatus.from(string: nil)
        #expect(result3 == nil)
    }

    @Test("Reading status conforms to Identifiable")
    func readingStatusIdentifiable() {
        #expect(ReadingStatus.reading.id == ReadingStatus.reading)
        #expect(ReadingStatus.read.id == ReadingStatus.read)
    }
}
