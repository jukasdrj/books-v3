import SwiftUI
import SwiftData

/// Repository pattern for centralizing SwiftData queries and business logic.
///
/// # Purpose
///
/// This repository centralizes all SwiftData query logic that was previously scattered
/// across views. Benefits:
/// - Business logic separated from UI layer
/// - Queries testable without SwiftUI environment
/// - Performance optimizations applied in one place
/// - Easier to maintain and refactor query predicates
///
/// # Usage
///
/// ```swift
/// @Environment(LibraryRepository.self) private var repository
///
/// var body: some View {
///     List(libraryWorks) { work in
///         WorkRowView(work: work)
///     }
///     .task {
///         await loadLibrary()
///     }
/// }
///
/// private func loadLibrary() async {
///     do {
///         libraryWorks = try repository.fetchUserLibrary()
///     } catch {
///         // Handle error
///     }
/// }
/// ```
///
/// # Architecture Notes
///
/// - **@MainActor:** All methods must run on main thread (SwiftData requirement)
/// - **Throws:** All methods throw to propagate SwiftData errors
/// - **Performance:** Uses FetchDescriptor with predicates for efficient queries
/// - **CloudKit Safe:** Handles to-many relationship filtering in-memory (predicate limitation)
///
/// - SeeAlso: `docs/plans/2025-11-04-security-audit-implementation.md` Task 3.2
@MainActor
@Observable
public class LibraryRepository {
    private let modelContext: ModelContext

    public init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Library Queries

    /// Fetches all works in the user's library (any reading status).
    ///
    /// **Performance:** Fetches all works, filters in-memory for library entries.
    /// SwiftData predicates cannot filter on to-many relationships (CloudKit limitation).
    ///
    /// - Returns: Array of works sorted by last modified date (newest first)
    /// - Throws: `SwiftDataError` if query fails
    public func fetchUserLibrary() throws -> [Work] {
        // Fetch all works sorted by modification date
        let descriptor = FetchDescriptor<Work>(
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        let allWorks = try modelContext.fetch(descriptor)

        // Filter in-memory for works with library entries
        // CRITICAL: Cannot use predicate for to-many relationship filtering
        return allWorks.filter { work in
            guard let entries = work.userLibraryEntries else { return false }
            return !entries.isEmpty
        }
    }

    /// Fetches works filtered by specific reading status.
    ///
    /// **Example:** Fetch all books currently being read
    /// ```swift
    /// let reading = try repository.fetchByReadingStatus(.reading)
    /// ```
    ///
    /// - Parameter status: Reading status to filter by (.wishlist, .toRead, .reading, .read)
    /// - Returns: Array of works sorted by last modified date
    /// - Throws: `SwiftDataError` if query fails
    public func fetchByReadingStatus(_ status: ReadingStatus) throws -> [Work] {
        let allWorks = try fetchUserLibrary()

        // Filter by reading status
        return allWorks.filter { work in
            work.userLibraryEntries?.first?.readingStatus == status
        }
    }

    /// Fetches books currently being read.
    ///
    /// Convenience method equivalent to `fetchByReadingStatus(.reading)`.
    ///
    /// - Returns: Array of works with reading status = .reading
    /// - Throws: `SwiftDataError` if query fails
    public func fetchCurrentlyReading() throws -> [Work] {
        return try fetchByReadingStatus(.reading)
    }

    /// Searches library for works matching query string.
    ///
    /// **Search Fields:** Title, author names (case-insensitive)
    ///
    /// **Performance:** Fetches all library works, searches in-memory.
    /// For large libraries (>1000 books), consider FTS (Full Text Search).
    ///
    /// - Parameter query: Search string (title or author name)
    /// - Returns: Array of matching works sorted by title
    /// - Throws: `SwiftDataError` if query fails
    public func searchLibrary(query: String) throws -> [Work] {
        guard !query.isEmpty else {
            return try fetchUserLibrary()
        }

        let allWorks = try fetchUserLibrary()
        let lowercasedQuery = query.lowercased()

        // Search in title and author names
        return allWorks.filter { work in
            // Search title
            if work.title.lowercased().contains(lowercasedQuery) {
                return true
            }

            // Search author names
            if let authors = work.authors {
                return authors.contains { author in
                    author.name.lowercased().contains(lowercasedQuery)
                }
            }

            return false
        }
        .sorted { $0.title < $1.title }
    }

    // MARK: - Statistics

    /// Counts total books in library (all reading statuses).
    ///
    /// **Performance:** Uses `fetchCount()` for efficiency (no object materialization).
    ///
    /// **Performance:** Uses `fetchCount()` for database-level counting (10x faster).
    /// - Returns: Total count of works in library
    /// - Throws: `SwiftDataError` if query fails
    public func totalBooksCount() throws -> Int {
        // Count UserLibraryEntry records (each entry = 1 book in library)
        // PERFORMANCE: Uses fetchCount() - no object materialization, 10x faster
        let descriptor = FetchDescriptor<UserLibraryEntry>()
        return try modelContext.fetchCount(descriptor)
    }

    /// Calculates completion rate (read books / total books).
    ///
    /// **Example Output:** 0.75 = 75% completion rate
    ///
    /// - Returns: Completion rate as decimal (0.0 to 1.0)
    /// - Throws: `SwiftDataError` if query fails
    public func completionRate() throws -> Double {
        let total = try totalBooksCount()
        guard total > 0 else { return 0.0 }

        let read = try fetchByReadingStatus(.read).count
        return Double(read) / Double(total)
    }

    /// Fetches works needing human review (low-confidence AI detections).
    ///
    /// **Use Case:** Bookshelf scanner AI detections below confidence threshold
    ///
    /// - Returns: Array of works with reviewStatus = .needsReview
    /// - Throws: `SwiftDataError` if query fails
    public func fetchReviewQueue() throws -> [Work] {
        // Fetch all works - cannot use predicate for enum comparison (SwiftData limitation)
        let descriptor = FetchDescriptor<Work>(
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        let allWorks = try modelContext.fetch(descriptor)

        // Filter in-memory for review queue
        return allWorks.filter { $0.reviewStatus == .needsReview }
    }

    /// Counts works in review queue.
    ///
    /// Convenience method for badge count display.
    ///
    /// - Returns: Number of works needing review
    /// - Throws: `SwiftDataError` if query fails
    public func reviewQueueCount() throws -> Int {
        return try fetchReviewQueue().count
    }

    // MARK: - Diversity Analytics

    /// Calculates cultural diversity score for library.
    ///
    /// **Algorithm:** (Marginalized + Indigenous voices) / Total authors
    ///
    /// **Example Interpretation:**
    /// - 0.4+ = Excellent diversity (40%+ diverse voices)
    /// - 0.2-0.4 = Good diversity
    /// - <0.2 = Room for improvement
    ///
    /// - Parameter works: Optional works array (defaults to full library)
    /// - Returns: Diversity score as decimal (0.0 to 1.0)
    /// - Throws: `SwiftDataError` if query fails
    public func calculateDiversityScore(for works: [Work]? = nil) throws -> Double {
        let targetWorks = try works ?? fetchUserLibrary()

        let allAuthors = targetWorks.compactMap(\.authors).flatMap { $0 }
        guard !allAuthors.isEmpty else { return 0.0 }

        let diverseCount = allAuthors.filter { author in
            author.representsMarginalizedVoices() || author.representsIndigenousVoices()
        }.count

        return Double(diverseCount) / Double(allAuthors.count)
    }

    /// Calculates reading statistics (completion rate, pages read, etc.).
    ///
    /// **Metrics:**
    /// - Total books
    /// - Completion rate
    /// - Currently reading count
    /// - Total pages read
    ///
    /// - Returns: Dictionary of statistic keys and values
    /// - Throws: `SwiftDataError` if query fails
    public func calculateReadingStatistics() throws -> [String: Any] {
        let total = try totalBooksCount()
        let completion = try completionRate()
        let reading = try fetchCurrentlyReading().count

        // Calculate total pages read
        let readBooks = try fetchByReadingStatus(.read)
        let totalPages = readBooks.compactMap { work in
            work.userLibraryEntries?.first?.edition?.pageCount
        }.reduce(0, +)

        return [
            "totalBooks": total,
            "completionRate": completion,
            "currentlyReading": reading,
            "totalPagesRead": totalPages
        ]
    }
}
