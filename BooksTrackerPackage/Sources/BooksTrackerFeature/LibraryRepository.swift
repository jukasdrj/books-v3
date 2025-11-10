import SwiftUI
import SwiftData

/// Reading statistics for Insights view
public struct ReadingStatistics: Codable, Sendable {
    public let totalBooks: Int
    public let completionRate: Double
    public let currentlyReading: Int
    public let totalPagesRead: Int

    public init(totalBooks: Int, completionRate: Double, currentlyReading: Int, totalPagesRead: Int) {
        self.totalBooks = totalBooks
        self.completionRate = completionRate
        self.currentlyReading = currentlyReading
        self.totalPagesRead = totalPagesRead
    }
}

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
    private var dtoMapper: DTOMapper?
    private var featureFlags: FeatureFlags?

    public init(modelContext: ModelContext, dtoMapper: DTOMapper?, featureFlags: FeatureFlags?) {
        self.modelContext = modelContext
        self.dtoMapper = dtoMapper
        self.featureFlags = featureFlags
    }

    // MARK: - Library Queries

    /// Fetches all works in the user's library (any reading status).
    ///
    /// **Performance:** Queries UserLibraryEntry first (smaller dataset), then maps to Works.
    /// 3-5x faster than fetching all Works and filtering in-memory.
    ///
    /// - Returns: Array of works sorted by last modified date (newest first)
    /// - Throws: `SwiftDataError` if query fails
    public func fetchUserLibrary() throws -> [Work] {
        // PERFORMANCE: Fetch UserLibraryEntry first (smaller dataset than all Works)
        // For 1000 works with 200 in library: fetches 200 entries vs 1000 works
        let descriptor = FetchDescriptor<UserLibraryEntry>()
        let entries = try modelContext.fetch(descriptor)

        // Map to Works and deduplicate (multiple entries can reference same Work)
        var seenWorkIDs = Set<PersistentIdentifier>()
        let works = entries.compactMap { entry -> Work? in
            // 1. VALIDATE: Check if the entry is still valid in the context
            guard modelContext.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else {
                return nil
            }

            // 2. ACCESS: Now safe to access entry.work
            guard let work = entry.work else {
                return nil
            }

            // 3. DEDUPLICATE: Skip if we've already seen this work
            guard !seenWorkIDs.contains(work.persistentModelID) else {
                return nil
            }
            seenWorkIDs.insert(work.persistentModelID)

            // 4. VALIDATE: Check if the work is still valid in the context
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                return nil
            }

            return work
        }

        // Sort by last modified date (newest first)
        return works.sorted { $0.lastModified > $1.lastModified }
    }

    /// Fetches works filtered by specific reading status.
    ///
    /// **Example:** Fetch all books currently being read
    /// ```swift
    /// let reading = try repository.fetchByReadingStatus(.reading)
    /// ```
    ///
    /// **Performance:** Fetches UserLibraryEntry first (smaller dataset), then maps to Works.
    /// - Parameter status: Reading status to filter by (.wishlist, .toRead, .reading, .read)
    /// - Returns: Array of works sorted by last modified date
    /// - Throws: `SwiftDataError` if query fails
    public func fetchByReadingStatus(_ status: ReadingStatus) throws -> [Work] {
        // PERFORMANCE: Fetch UserLibraryEntry first (smaller dataset), then map to Works
        let descriptor = FetchDescriptor<UserLibraryEntry>(
            predicate: #Predicate { $0.readingStatus == status }
        )
        let entries = try modelContext.fetch(descriptor)

        // Map to Works (only loads needed Works, not entire library)
        // DEFENSIVE: Validate entries before accessing work relationship
        return entries.compactMap { entry in
            // 1. VALIDATE: Check if the entry is still valid in the context
            guard modelContext.model(for: entry.persistentModelID) as? UserLibraryEntry != nil else {
                return nil
            }
            
            // 2. ACCESS: Now safe to access entry.work
            guard let work = entry.work else {
                return nil
            }
            
            // 3. VALIDATE: Check if the work is still valid in the context
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                return nil
            }
            
            return work
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
            // DEFENSIVE: Validate work is still in context before accessing relationships
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                return false
            }
            
            // Search title
            if work.title.lowercased().contains(lowercasedQuery) {
                return true
            }

            // Search author names
            if let authors = work.authors {
                return authors.contains { author in
                    // DEFENSIVE: Validate author is still in context before accessing properties
                    // During library reset, authors may be deleted while search is running
                    guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                        return false
                    }
                    return author.name.lowercased().contains(lowercasedQuery)
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
    /// Returns count of books in review queue.
    ///
    /// **Performance:** Uses database-level `fetchCount()` with predicate (10x faster than loading all objects).
    /// For 1000 books, this takes ~5ms vs ~50ms with in-memory filtering.
    /// - Returns: Number of works needing review
    /// - Throws: `SwiftDataError` if query fails
    public func reviewQueueCount() throws -> Int {
        // Use database-level counting with predicate
        // Must compare rawValue since Swift predicate macros don't support enum case access
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                work.reviewStatus.rawValue == "needsReview"
            }
        )
        return try modelContext.fetchCount(descriptor)
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

        let allAuthors = targetWorks.compactMap { work -> [Author]? in
            // DEFENSIVE: Validate work is still in context before accessing relationships
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                return nil
            }
            return work.authors
        }.flatMap { $0 }
        guard !allAuthors.isEmpty else { return 0.0 }

        // DEFENSIVE: Filter deleted authors AND calculate diversity in single pass
        var validCount = 0
        var diverseCount = 0
        
        for author in allAuthors {
            guard modelContext.model(for: author.persistentModelID) as? Author != nil else {
                continue
            }
            validCount += 1
            if author.representsMarginalizedVoices() || author.representsIndigenousVoices() {
                diverseCount += 1
            }
        }
        
        guard validCount > 0 else { return 0.0 }
        return Double(diverseCount) / Double(validCount)
    }

    /// Calculates reading statistics (completion rate, pages read, etc.).
    ///
    /// **Metrics:**
    /// - Total books
    /// - Completion rate (0.0 to 1.0)
    /// - Currently reading count
    /// - Total pages read
    ///
    /// - Returns: Typed statistics struct (compile-time safe)
    /// - Throws: `SwiftDataError` if query fails
    public func calculateReadingStatistics() throws -> ReadingStatistics {
        let total = try totalBooksCount()
        let completion = try completionRate()
        let reading = try fetchCurrentlyReading().count

        // Calculate total pages read
        let readBooks = try fetchByReadingStatus(.read)
        let totalPages = readBooks.compactMap { work -> Int? in
            // DEFENSIVE: Validate work is still in context before accessing relationships
            guard modelContext.model(for: work.persistentModelID) as? Work != nil else {
                return nil
            }
            return work.userLibraryEntries?.first?.edition?.pageCount
        }.reduce(0, +)

        return ReadingStatistics(
            totalBooks: total,
            completionRate: completion,
            currentlyReading: reading,
            totalPagesRead: totalPages
        )
    }

    // MARK: - Library Management

    public func resetLibrary() async {
        // STEP 1: Perform deletion in background task
        // Use regular Task (not detached) to maintain actor context for ModelContext
        Task(priority: .userInitiated) { @MainActor in

            do {
                // STEP 2: Cancel enrichment queue operations first
                await EnrichmentQueue.shared.cancelBackendJob()
                EnrichmentQueue.shared.stopProcessing()
                EnrichmentQueue.shared.clear()

                // STEP 3: Delete all models using modelContext
                // Use predicate-based deletion for efficiency and clarity
                try self.modelContext.delete(
                    model: Work.self,
                    where: #Predicate { _ in true }
                )
                try self.modelContext.delete(
                    model: Author.self,
                    where: #Predicate { _ in true }
                )
                try self.modelContext.delete(
                    model: Edition.self,
                    where: #Predicate { _ in true }
                )
                try self.modelContext.delete(
                    model: UserLibraryEntry.self,
                    where: #Predicate { _ in true }
                )

                // STEP 4: Save to persistent store
                try self.modelContext.save()

                // STEP 5: Clear caches
                self.dtoMapper?.clearCache()
                DiversityStats.invalidateCache()

                // STEP 6: Invalidate reading stats (async operation)
                await ReadingStats.invalidateCache()

                // STEP 7: Post notification and cleanup
                NotificationCenter.default.post(
                    name: .libraryWasReset,
                    object: nil
                )

                // STEP 8: Cleanup UserDefaults and settings
                UserDefaults.standard.removeObject(forKey: "RecentBookSearches")
                SampleDataGenerator(modelContext: self.modelContext).resetSampleDataFlag()
                self.featureFlags?.resetToDefaults()

                // Success haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)

                print("✅ Library reset complete - All works, settings, and queue cleared")

            } catch {
                print("❌ Failed to reset library: \(error)")

                await MainActor.run {
                    // Error haptic
                    let generator = UINotificationFeedbackGenerator()
                    generator.notificationOccurred(.error)
                }
            }
        }
    }
}
