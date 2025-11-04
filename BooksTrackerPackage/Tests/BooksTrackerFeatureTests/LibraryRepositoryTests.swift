import Testing
import SwiftData
import Foundation
@testable import BooksTrackerFeature

/// Comprehensive test suite for LibraryRepository
///
/// **Test Coverage:**
/// - Library queries (fetch, search, filter)
/// - Reading status filtering
/// - Statistics calculations (completion rate, diversity score)
/// - Review queue management
/// - Edge cases (empty library, invalid data)
///
/// **Architecture:**
/// - Uses in-memory SwiftData container (no persistence between tests)
/// - All tests isolated with fresh ModelContext
/// - @MainActor for SwiftData thread safety
///
/// - SeeAlso: `docs/plans/2025-11-04-security-audit-implementation.md` Task 3.2
@Suite("LibraryRepository Tests")
@MainActor
struct LibraryRepositoryTests {

    var modelContainer: ModelContainer!
    var modelContext: ModelContext!
    var repository: LibraryRepository!

    init() throws {
        // Create in-memory container for testing
        modelContainer = try ModelContainer(
            for: Work.self, Edition.self, Author.self, UserLibraryEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        modelContext = ModelContext(modelContainer)
        repository = LibraryRepository(modelContext: modelContext)
    }

    // MARK: - Library Queries Tests

    @Test("Fetch user library returns only owned books")
    func fetchUserLibrary() throws {
        // Create works
        let ownedWork = Work(title: "Owned Book")
        let notOwnedWork = Work(title: "Not Owned")
        modelContext.insert(ownedWork)
        modelContext.insert(notOwnedWork)

        // Add library entry for ownedWork only
        _ = UserLibraryEntry.createWishlistEntry(for: ownedWork, context: modelContext)

        // Fetch library
        let library = try repository.fetchUserLibrary()

        #expect(library.count == 1, "Library should contain only owned books")
        #expect(library.first?.title == "Owned Book", "Should return the owned book")
    }

    @Test("Fetch user library with empty library returns empty array")
    func fetchEmptyLibrary() throws {
        // Create works but don't add library entries
        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")
        modelContext.insert(work1)
        modelContext.insert(work2)

        let library = try repository.fetchUserLibrary()

        #expect(library.isEmpty, "Empty library should return empty array")
    }

    @Test("Fetch user library sorts by last modified (newest first)")
    func fetchLibrarySortedByLastModified() throws {
        // Create works with different modification dates
        let oldWork = Work(title: "Old Book")
        oldWork.lastModified = Date(timeIntervalSince1970: 1000)
        let newWork = Work(title: "New Book")
        newWork.lastModified = Date(timeIntervalSince1970: 2000)

        modelContext.insert(oldWork)
        modelContext.insert(newWork)

        // Add library entries
        _ = UserLibraryEntry.createWishlistEntry(for: oldWork, context: modelContext)
        _ = UserLibraryEntry.createWishlistEntry(for: newWork, context: modelContext)

        let library = try repository.fetchUserLibrary()

        #expect(library.count == 2)
        #expect(library[0].title == "New Book", "Newest book should be first")
        #expect(library[1].title == "Old Book", "Older book should be second")
    }

    // MARK: - Reading Status Filter Tests

    @Test("Fetch by reading status filters correctly")
    func fetchByReadingStatus() throws {
        // Create works with different statuses
        let wishlistWork = Work(title: "Wishlist Book")
        let readingWork = Work(title: "Reading Book")
        let readWork = Work(title: "Read Book")

        modelContext.insert(wishlistWork)
        modelContext.insert(readingWork)
        modelContext.insert(readWork)

        // Create library entries with different statuses
        let entry1 = UserLibraryEntry.createWishlistEntry(for: wishlistWork, context: modelContext)
        entry1.readingStatus = .wishlist

        let entry2 = UserLibraryEntry.createWishlistEntry(for: readingWork, context: modelContext)
        entry2.readingStatus = .reading

        let entry3 = UserLibraryEntry.createWishlistEntry(for: readWork, context: modelContext)
        entry3.readingStatus = .read

        // Test each status filter
        let wishlist = try repository.fetchByReadingStatus(.wishlist)
        let reading = try repository.fetchByReadingStatus(.reading)
        let read = try repository.fetchByReadingStatus(.read)

        #expect(wishlist.count == 1)
        #expect(wishlist.first?.title == "Wishlist Book")

        #expect(reading.count == 1)
        #expect(reading.first?.title == "Reading Book")

        #expect(read.count == 1)
        #expect(read.first?.title == "Read Book")
    }

    @Test("Fetch currently reading convenience method")
    func fetchCurrentlyReading() throws {
        // Create works
        let reading1 = Work(title: "Reading 1")
        let reading2 = Work(title: "Reading 2")
        let readWork = Work(title: "Finished Book")

        modelContext.insert(reading1)
        modelContext.insert(reading2)
        modelContext.insert(readWork)

        // Set statuses
        let entry1 = UserLibraryEntry.createWishlistEntry(for: reading1, context: modelContext)
        entry1.readingStatus = .reading

        let entry2 = UserLibraryEntry.createWishlistEntry(for: reading2, context: modelContext)
        entry2.readingStatus = .reading

        let entry3 = UserLibraryEntry.createWishlistEntry(for: readWork, context: modelContext)
        entry3.readingStatus = .read

        // Fetch currently reading
        let currentlyReading = try repository.fetchCurrentlyReading()

        #expect(currentlyReading.count == 2, "Should return only books being read")
        #expect(currentlyReading.contains { $0.title == "Reading 1" })
        #expect(currentlyReading.contains { $0.title == "Reading 2" })
    }

    // MARK: - Search Tests

    @Test("Search library by title")
    func searchLibraryByTitle() throws {
        // Create works
        let gatsby = Work(title: "The Great Gatsby")
        let mockingbird = Work(title: "To Kill a Mockingbird")
        let pride = Work(title: "Pride and Prejudice")

        modelContext.insert(gatsby)
        modelContext.insert(mockingbird)
        modelContext.insert(pride)

        // Add to library
        let _ = UserLibraryEntry.createWishlistEntry(for: gatsby, context: modelContext)
        let _ = UserLibraryEntry.createWishlistEntry(for: mockingbird, context: modelContext)
        let _ = UserLibraryEntry.createWishlistEntry(for: pride, context: modelContext)

        // Search for "great"
        let results = try repository.searchLibrary(query: "great")

        #expect(results.count == 1)
        #expect(results.first?.title == "The Great Gatsby")
    }

    @Test("Search library by author name")
    func searchLibraryByAuthor() throws {
        // Create authors
        let fitzgerald = Author(name: "F. Scott Fitzgerald")
        let austen = Author(name: "Jane Austen")

        modelContext.insert(fitzgerald)
        modelContext.insert(austen)

        // Create works
        let gatsby = Work(title: "The Great Gatsby")
        let pride = Work(title: "Pride and Prejudice")

        modelContext.insert(gatsby)
        modelContext.insert(pride)

        // Set relationships after insert
        gatsby.authors = [fitzgerald]
        pride.authors = [austen]

        // Add to library
        let _ = UserLibraryEntry.createWishlistEntry(for: gatsby, context: modelContext)
        let _ = UserLibraryEntry.createWishlistEntry(for: pride, context: modelContext)

        // Search for "Fitzgerald"
        let results = try repository.searchLibrary(query: "Fitzgerald")

        #expect(results.count == 1)
        #expect(results.first?.title == "The Great Gatsby")
    }

    @Test("Search library is case insensitive")
    func searchLibraryCaseInsensitive() throws {
        let work = Work(title: "The Great Gatsby")
        modelContext.insert(work)

        let _ = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

        // Search with different cases
        let lowercase = try repository.searchLibrary(query: "great gatsby")
        let uppercase = try repository.searchLibrary(query: "GREAT GATSBY")
        let mixedCase = try repository.searchLibrary(query: "GrEaT gAtSbY")

        #expect(lowercase.count == 1)
        #expect(uppercase.count == 1)
        #expect(mixedCase.count == 1)
    }

    @Test("Search library with empty query returns all books")
    func searchLibraryEmptyQuery() throws {
        // Create multiple works
        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")

        modelContext.insert(work1)
        modelContext.insert(work2)

        let _ = UserLibraryEntry.createWishlistEntry(for: work1, context: modelContext)
        let _ = UserLibraryEntry.createWishlistEntry(for: work2, context: modelContext)

        let results = try repository.searchLibrary(query: "")

        #expect(results.count == 2, "Empty query should return all books")
    }

    // MARK: - Statistics Tests

    @Test("Total books count")
    func totalBooksCount() throws {
        // Create 3 works in library
        for i in 1...3 {
            let work = Work(title: "Book \(i)")
            modelContext.insert(work)

            let _ = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)
        }

        let count = try repository.totalBooksCount()

        #expect(count == 3, "Should count all library books")
    }

    @Test("Total books count with empty library returns zero")
    func totalBooksCountEmpty() throws {
        let count = try repository.totalBooksCount()

        #expect(count == 0, "Empty library should return 0")
    }

    @Test("Completion rate calculation")
    func completionRate() throws {
        // Create 10 books: 7 read, 3 unread
        for i in 1...10 {
            let work = Work(title: "Book \(i)")
            modelContext.insert(work)

            let entry = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)
            entry.readingStatus = i <= 7 ? .read : .reading
        }

        let rate = try repository.completionRate()

        #expect(rate == 0.7, "7 out of 10 read = 70% completion")
    }

    @Test("Completion rate with empty library returns zero")
    func completionRateEmpty() throws {
        let rate = try repository.completionRate()

        #expect(rate == 0.0, "Empty library should return 0% completion")
    }

    // MARK: - Review Queue Tests

    @Test("Fetch review queue returns only works needing review")
    func fetchReviewQueue() throws {
        // Create works
        let needsReview1 = Work(title: "Needs Review 1")
        needsReview1.reviewStatus = .needsReview

        let needsReview2 = Work(title: "Needs Review 2")
        needsReview2.reviewStatus = .needsReview

        let approved = Work(title: "Approved")
        approved.reviewStatus = .verified

        modelContext.insert(needsReview1)
        modelContext.insert(needsReview2)
        modelContext.insert(approved)

        let queue = try repository.fetchReviewQueue()

        #expect(queue.count == 2, "Should return only works needing review")
        #expect(queue.contains { $0.title == "Needs Review 1" })
        #expect(queue.contains { $0.title == "Needs Review 2" })
    }

    @Test("Review queue count convenience method")
    func reviewQueueCount() throws {
        // Create 3 works needing review
        for i in 1...3 {
            let work = Work(title: "Review \(i)")
            work.reviewStatus = .needsReview
            modelContext.insert(work)
        }

        let count = try repository.reviewQueueCount()

        #expect(count == 3, "Should count works needing review")
    }

    // MARK: - Diversity Analytics Tests

    @Test("Calculate diversity score")
    func calculateDiversityScore() throws {
        // Create diverse authors (2 marginalized, 2 non-marginalized)
        let marginalizedAuthor1 = Author(name: "Author 1", gender: .female, culturalRegion: .africa)
        let marginalizedAuthor2 = Author(name: "Author 2", gender: .nonBinary, culturalRegion: .asia)
        let regularAuthor1 = Author(name: "Author 3", gender: .male, culturalRegion: .northAmerica)
        let regularAuthor2 = Author(name: "Author 4", gender: .male, culturalRegion: .europe)

        modelContext.insert(marginalizedAuthor1)
        modelContext.insert(marginalizedAuthor2)
        modelContext.insert(regularAuthor1)
        modelContext.insert(regularAuthor2)

        // Create works
        let work1 = Work(title: "Book 1")
        let work2 = Work(title: "Book 2")
        let work3 = Work(title: "Book 3")
        let work4 = Work(title: "Book 4")

        modelContext.insert(work1)
        modelContext.insert(work2)
        modelContext.insert(work3)
        modelContext.insert(work4)

        // Set relationships after insert
        work1.authors = [marginalizedAuthor1]
        work2.authors = [marginalizedAuthor2]
        work3.authors = [regularAuthor1]
        work4.authors = [regularAuthor2]

        // Add to library
        let _ = UserLibraryEntry.createWishlistEntry(for: work1, context: modelContext)
        let _ = UserLibraryEntry.createWishlistEntry(for: work2, context: modelContext)
        let _ = UserLibraryEntry.createWishlistEntry(for: work3, context: modelContext)
        let _ = UserLibraryEntry.createWishlistEntry(for: work4, context: modelContext)

        let score = try repository.calculateDiversityScore()

        // 2 diverse out of 4 total = 0.5 (50%)
        #expect(score == 0.5, "Should calculate 50% diversity score")
    }

    @Test("Calculate diversity score with empty library returns zero")
    func calculateDiversityScoreEmpty() throws {
        let score = try repository.calculateDiversityScore()

        #expect(score == 0.0, "Empty library should return 0% diversity")
    }

    @Test("Calculate diversity score for specific works subset")
    func calculateDiversityScoreSubset() throws {
        // Create diverse author
        let diverseAuthor = Author(name: "Diverse Author", gender: .female, culturalRegion: .africa)

        modelContext.insert(diverseAuthor)

        // Create 2 works (only 1 diverse)
        let diverseWork = Work(title: "Diverse Book")
        let regularWork = Work(title: "Regular Book")

        modelContext.insert(diverseWork)
        modelContext.insert(regularWork)

        // Set relationships
        diverseWork.authors = [diverseAuthor]

        // Calculate diversity for specific subset
        let score = try repository.calculateDiversityScore(for: [diverseWork, regularWork])

        // 1 diverse out of 1 total author = 1.0 (100%)
        // (regularWork has no authors, so only counts diverseWork's author)
        #expect(score == 1.0, "Should calculate diversity for provided works only")
    }

    // MARK: - Reading Statistics Tests

    @Test("Calculate reading statistics")
    func calculateReadingStatistics() throws {
        // Create works with different statuses
        let reading1 = Work(title: "Reading 1")
        let reading2 = Work(title: "Reading 2")
        let read1 = Work(title: "Read 1")

        // Create editions with page counts
        let edition1 = Edition(pageCount: 300)

        modelContext.insert(edition1)
        modelContext.insert(reading1)
        modelContext.insert(reading2)
        modelContext.insert(read1)

        // Create library entries
        let entry1 = UserLibraryEntry.createWishlistEntry(for: reading1, context: modelContext)
        entry1.readingStatus = .reading

        let entry2 = UserLibraryEntry.createWishlistEntry(for: reading2, context: modelContext)
        entry2.readingStatus = .reading

        let entry3 = UserLibraryEntry.createWishlistEntry(for: read1, context: modelContext)
        entry3.readingStatus = .read
        entry3.edition = edition1  // 300 pages

        let stats = try repository.calculateReadingStatistics()

        #expect(stats["totalBooks"] as? Int == 3)
        #expect(stats["currentlyReading"] as? Int == 2)
        #expect(stats["completionRate"] as? Double == (1.0 / 3.0))  // 1 read out of 3 total
        #expect(stats["totalPagesRead"] as? Int == 300)  // Only read1 has pages
    }

    // MARK: - Edge Case Tests

    @Test("Handle work with nil user library entries gracefully")
    func handleNilUserLibraryEntries() throws {
        // Create work without library entry
        let work = Work(title: "No Entry")
        modelContext.insert(work)

        let library = try repository.fetchUserLibrary()

        #expect(library.isEmpty, "Work without library entry should not appear")
    }

    @Test("Handle work with empty authors array")
    func handleEmptyAuthorsArray() throws {
        let work = Work(title: "No Authors")
        modelContext.insert(work)

        let _ = UserLibraryEntry.createWishlistEntry(for: work, context: modelContext)

        let library = try repository.fetchUserLibrary()

        #expect(library.count == 1, "Work with empty authors should still be fetchable")
    }
}
