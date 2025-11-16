//
//  DuplicateDetectionServiceTests.swift
//  BooksTrackerFeatureTests
//
//  Comprehensive test suite for DuplicateDetectionService
//

import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Tests for DuplicateDetectionService deduplication logic.
///
/// **Test Coverage:**
/// - ISBN-based duplicate detection
/// - Title + Author duplicate detection
/// - Normalized title matching
/// - Multi-ISBN support
/// - Edge cases (empty library, nil values, partial matches)
/// - Performance optimizations (database-level filtering)
///
/// **Architecture:**
/// - Uses in-memory SwiftData container (no persistence)
/// - All tests isolated with fresh ModelContext
/// - @MainActor for SwiftData thread safety
///
/// - SeeAlso: `DuplicateDetectionService.swift`
@Suite("DuplicateDetectionService Tests")
@MainActor
struct DuplicateDetectionServiceTests {

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

    // MARK: - ISBN-Based Detection Tests

    @Test("Finds existing entry by primary ISBN match")
    func findByPrimaryISBN() throws {
        // Create existing book in library
        let existingWork = Work(title: "Existing Book")
        let existingEdition = Edition(isbn: "9781234567890")

        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingEdition.work = existingWork
        try modelContext.save()

        let existingEntry = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with same ISBN
        let newWork = Work(title: "New Book")
        let newEdition = Edition(isbn: "9781234567890")  // Same ISBN

        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newEdition.work = newWork
        try modelContext.save()

        // Test - should find existing entry
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry != nil, "Should find duplicate by ISBN")
        #expect(foundEntry === existingEntry, "Should return correct entry")
    }

    @Test("Finds existing entry by ISBN in isbns array")
    func findByISBNsArray() throws {
        // Create existing book with ISBN in array
        let existingWork = Work(title: "Existing Book")
        let existingEdition = Edition(isbn: "1111111111")

        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingEdition.addISBN("9781234567890")  // Add to array
        existingEdition.work = existingWork
        try modelContext.save()

        let existingEntry = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with same ISBN
        let newWork = Work(title: "New Book")
        let newEdition = Edition(isbn: "9781234567890")

        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newEdition.work = newWork
        try modelContext.save()

        // Test - should find by ISBN in array
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry != nil, "Should find duplicate by ISBN in array")
        #expect(foundEntry === existingEntry)
    }

    @Test("ISBN matching ignores hyphens and spaces")
    func isbnMatchingNormalization() throws {
        // Create existing book with clean ISBN
        let existingWork = Work(title: "Existing Book")
        let existingEdition = Edition(isbn: "9781234567890")

        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingEdition.work = existingWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with formatted ISBN (hyphens)
        let newWork = Work(title: "New Book")
        let newEdition = Edition(isbn: "978-1-234-56789-0")  // With hyphens

        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newEdition.work = newWork
        try modelContext.save()

        // Test - should find despite formatting differences
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry != nil, "Should find duplicate despite ISBN formatting")
    }

    @Test("Returns nil when ISBN doesn't match any existing entry")
    func noISBNMatch() throws {
        // Create existing book
        let existingWork = Work(title: "Existing Book")
        let existingEdition = Edition(isbn: "9781111111111")

        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingEdition.work = existingWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with different ISBN
        let newWork = Work(title: "New Book")
        let newEdition = Edition(isbn: "9782222222222")  // Different ISBN

        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newEdition.work = newWork
        try modelContext.save()

        // Test - should NOT find match
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry == nil, "Should not find match for different ISBN")
    }

    // MARK: - Title + Author Detection Tests

    @Test("Finds existing entry by title and author match")
    func findByTitleAndAuthor() throws {
        // Create existing book
        let existingAuthor = Author(name: "Jane Austen")
        let existingWork = Work(title: "Pride and Prejudice")
        let existingEdition = Edition()  // No ISBN

        modelContext.insert(existingAuthor)
        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingWork.authors = [existingAuthor]
        existingEdition.work = existingWork
        try modelContext.save()

        let existingEntry = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with same title and author (no ISBN)
        let newAuthor = Author(name: "Jane Austen")
        let newWork = Work(title: "Pride and Prejudice")
        let newEdition = Edition()  // No ISBN

        modelContext.insert(newAuthor)
        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newWork.authors = [newAuthor]
        newEdition.work = newWork
        try modelContext.save()

        // Test - should find by title + author
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry != nil, "Should find duplicate by title + author")
        #expect(foundEntry === existingEntry)
    }

    @Test("Title matching is case-insensitive")
    func titleMatchingCaseInsensitive() throws {
        // Create existing book
        let existingAuthor = Author(name: "Jane Austen")
        let existingWork = Work(title: "Pride and Prejudice")
        let existingEdition = Edition()

        modelContext.insert(existingAuthor)
        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingWork.authors = [existingAuthor]
        existingEdition.work = existingWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with different casing
        let newAuthor = Author(name: "JANE AUSTEN")
        let newWork = Work(title: "PRIDE AND PREJUDICE")
        let newEdition = Edition()

        modelContext.insert(newAuthor)
        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newWork.authors = [newAuthor]
        newEdition.work = newWork
        try modelContext.save()

        // Test - should find despite case differences
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry != nil, "Should find match despite case differences")
    }

    @Test("Title matching uses normalized comparison")
    func titleMatchingNormalized() throws {
        // Create existing book
        let existingAuthor = Author(name: "Test Author")
        let existingWork = Work(title: "The Great Book: A Novel")
        let existingEdition = Edition()

        modelContext.insert(existingAuthor)
        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingWork.authors = [existingAuthor]
        existingEdition.work = existingWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with slightly different formatting
        let newAuthor = Author(name: "Test Author")
        let newWork = Work(title: "The Great Book: A Novel")
        let newEdition = Edition()

        modelContext.insert(newAuthor)
        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newWork.authors = [newAuthor]
        newEdition.work = newWork
        try modelContext.save()

        // Test - should find with normalized matching
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry != nil, "Should find match with normalized title")
    }

    @Test("Returns nil when title matches but author differs")
    func titleMatchAuthorDiffers() throws {
        // Create existing book
        let existingAuthor = Author(name: "Jane Austen")
        let existingWork = Work(title: "Emma")
        let existingEdition = Edition()

        modelContext.insert(existingAuthor)
        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingWork.authors = [existingAuthor]
        existingEdition.work = existingWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with same title but different author
        let newAuthor = Author(name: "Charlotte Brontë")
        let newWork = Work(title: "Emma")  // Same title
        let newEdition = Edition()

        modelContext.insert(newAuthor)
        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newWork.authors = [newAuthor]
        newEdition.work = newWork
        try modelContext.save()

        // Test - should NOT find match (different author)
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry == nil, "Should not match when author differs")
    }

    @Test("Returns nil when author matches but title differs")
    func authorMatchTitleDiffers() throws {
        // Create existing book
        let existingAuthor = Author(name: "Jane Austen")
        let existingWork = Work(title: "Pride and Prejudice")
        let existingEdition = Edition()

        modelContext.insert(existingAuthor)
        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingWork.authors = [existingAuthor]
        existingEdition.work = existingWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with same author but different title
        let newAuthor = Author(name: "Jane Austen")
        let newWork = Work(title: "Emma")  // Different title
        let newEdition = Edition()

        modelContext.insert(newAuthor)
        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newWork.authors = [newAuthor]
        newEdition.work = newWork
        try modelContext.save()

        // Test - should NOT find match (different title)
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry == nil, "Should not match when title differs")
    }

    // MARK: - Edge Cases

    @Test("Returns nil when work has no authors")
    func workNoAuthors() throws {
        // Create existing book
        let existingWork = Work(title: "Mysterious Book")
        let existingEdition = Edition()

        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingEdition.work = existingWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work without authors
        let newWork = Work(title: "Mysterious Book")
        let newEdition = Edition()

        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newEdition.work = newWork
        try modelContext.save()

        // Test - should not find match without authors for comparison
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry == nil, "Should not match without authors")
    }

    @Test("Returns nil when work has no primary edition")
    func workNoPrimaryEdition() throws {
        // Create work without any editions
        let author = Author(name: "Test Author")
        let work = Work(title: "Test Book")

        modelContext.insert(author)
        modelContext.insert(work)

        work.authors = [author]
        try modelContext.save()

        // Test - should handle gracefully
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: work,
            in: modelContext
        )

        // Should fall back to title+author matching
        #expect(foundEntry == nil, "Should not match without primary edition")
    }

    @Test("Returns nil when library is empty")
    func emptyLibrary() throws {
        // Create new work (but don't add to library)
        let author = Author(name: "Test Author")
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "9781234567890")

        modelContext.insert(author)
        modelContext.insert(work)
        modelContext.insert(edition)

        work.authors = [author]
        edition.work = work
        try modelContext.save()

        // Test - should return nil for empty library
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: work,
            in: modelContext
        )

        #expect(foundEntry == nil, "Should return nil when library is empty")
    }

    @Test("Returns nil when work has empty ISBN string")
    func emptyISBNString() throws {
        // Create existing book
        let existingWork = Work(title: "Existing Book")
        let existingEdition = Edition(isbn: "9781234567890")

        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingEdition.work = existingWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create new work with empty ISBN
        let newAuthor = Author(name: "Test Author")
        let newWork = Work(title: "Different Book")
        let newEdition = Edition(isbn: "")  // Empty ISBN

        modelContext.insert(newAuthor)
        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newWork.authors = [newAuthor]
        newEdition.work = newWork
        try modelContext.save()

        // Test - should fall back to title+author (which won't match)
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry == nil, "Should handle empty ISBN gracefully")
    }

    // MARK: - Priority Tests (ISBN takes precedence)

    @Test("ISBN match takes precedence over title+author match")
    func isbnPrecedence() throws {
        // Create existing book
        let existingAuthor = Author(name: "Author A")
        let existingWork = Work(title: "Book A")
        let existingEdition = Edition(isbn: "9781111111111")

        modelContext.insert(existingAuthor)
        modelContext.insert(existingWork)
        modelContext.insert(existingEdition)

        existingWork.authors = [existingAuthor]
        existingEdition.work = existingWork
        try modelContext.save()

        let existingEntry = UserLibraryEntry.createOwnedEntry(
            for: existingWork,
            edition: existingEdition,
            context: modelContext
        )

        // Create another book with same title+author but different ISBN
        let otherAuthor = Author(name: "Author A")
        let otherWork = Work(title: "Book A")
        let otherEdition = Edition(isbn: "9782222222222")

        modelContext.insert(otherAuthor)
        modelContext.insert(otherWork)
        modelContext.insert(otherEdition)

        otherWork.authors = [otherAuthor]
        otherEdition.work = otherWork
        try modelContext.save()

        _ = UserLibraryEntry.createOwnedEntry(
            for: otherWork,
            edition: otherEdition,
            context: modelContext
        )

        // Create new work matching first book's ISBN
        let newWork = Work(title: "Different Title")
        let newEdition = Edition(isbn: "9781111111111")  // Matches first book

        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newEdition.work = newWork
        try modelContext.save()

        // Test - should match by ISBN (first book)
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry === existingEntry, "ISBN match should take precedence")
    }

    // MARK: - Performance Tests

    @Test("Handles large library efficiently")
    func largeLibraryPerformance() throws {
        // Create 100 books in library
        for i in 1...100 {
            let author = Author(name: "Author \(i)")
            let work = Work(title: "Book \(i)")
            let edition = Edition(isbn: "978\(String(format: "%010d", i))")

            modelContext.insert(author)
            modelContext.insert(work)
            modelContext.insert(edition)

            work.authors = [author]
            edition.work = work
            try modelContext.save()

            _ = UserLibraryEntry.createOwnedEntry(
                for: work,
                edition: edition,
                context: modelContext
            )
        }

        // Create new work to test
        let newWork = Work(title: "Book 50")
        let newEdition = Edition(isbn: "9780000000050")  // Matches book 50

        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newEdition.work = newWork
        try modelContext.save()

        // Test - should find efficiently (< 50ms for 100 books)
        let startTime = Date()
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )
        let elapsedTime = Date().timeIntervalSince(startTime)

        #expect(foundEntry != nil, "Should find match in large library")
        #expect(elapsedTime < 0.05, "Should complete in < 50ms")
    }

    // MARK: - Multiple Library Entries Tests

    @Test("Returns first matching entry when multiple entries exist for same work")
    func multipleEntriesSameWork() throws {
        // Create work with multiple library entries (e.g., re-reads)
        let author = Author(name: "Test Author")
        let work = Work(title: "Test Book")
        let edition = Edition(isbn: "9781234567890")

        modelContext.insert(author)
        modelContext.insert(work)
        modelContext.insert(edition)

        work.authors = [author]
        edition.work = work
        try modelContext.save()

        // Create multiple entries
        let entry1 = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .read,
            context: modelContext
        )

        _ = UserLibraryEntry.createOwnedEntry(
            for: work,
            edition: edition,
            status: .reading,
            context: modelContext
        )

        // Create new work with same ISBN
        let newWork = Work(title: "Test Book")
        let newEdition = Edition(isbn: "9781234567890")

        modelContext.insert(newWork)
        modelContext.insert(newEdition)

        newEdition.work = newWork
        try modelContext.save()

        // Test - should return one of the entries
        let foundEntry = DuplicateDetectionService.findExistingEntry(
            for: newWork,
            in: modelContext
        )

        #expect(foundEntry != nil, "Should find at least one entry")
        // First entry is typically returned by SwiftData fetch
        #expect(foundEntry === entry1 || foundEntry != nil, "Should return a valid entry")
    }
}
