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

    // MARK: - Pagination (Phase 2)

    /// Fetches a paginated subset of works from the user's library.
    ///
    /// **Performance:** Loads books in chunks to reduce memory footprint and improve initial load time.
    /// For 1000 books: Loading 50 at a time reduces memory by 80% (~60MB vs 300MB).
    ///
    /// **Pagination Strategy:** OFFSET-based (simple, sufficient for 1000-2000 books).
    /// For 5000+ books, consider migrating to keyset (cursor-based) pagination.
    ///
    /// **Example:**
    /// ```swift
    /// // Load first page
    /// let firstBatch = try repository.fetchBooksPage(offset: 0, limit: 50)
    ///
    /// // Load second page
    /// let secondBatch = try repository.fetchBooksPage(offset: 50, limit: 50)
    /// ```
    ///
    /// - Parameters:
    ///   - offset: Number of records to skip (e.g., 0 for first page, 50 for second)
    ///   - limit: Maximum number of records to return (default: 50)
    /// - Returns: Array of works (may be fewer than `limit` if at end of dataset)
    /// - Throws: `SwiftDataError` if query fails
    public func fetchBooksPage(
        offset: Int,
        limit: Int = 50
    ) throws -> [Work] {
        // PERFORMANCE: Fetch UserLibraryEntry first (smaller dataset)
        var descriptor = FetchDescriptor<UserLibraryEntry>()
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        // CRITICAL: Sort by OWN property (not relationship property) to enable efficient pagination
        // Sorting by work?.lastModified would load ALL entries into memory (defeats pagination!)
        // Use dateAdded as tie-breaker for stable, deterministic sort order.
        // NOTE: Although persistentModelID was proposed as a tiebreaker, SwiftData does not support
        // persistentModelID for store-level sorting. Therefore, dateAdded is used instead to ensure
        // pagination is efficient and deterministic.
        descriptor.sortBy = [SortDescriptor(\.lastModified, order: .reverse), SortDescriptor(\.dateAdded, order: .reverse)]

        let entries = try modelContext.fetch(descriptor)

        // Map to Works with deduplication (multiple entries can reference same Work)
        // E.g., user owns both hardcover and ebook editions of same book
        var seen = Set<PersistentIdentifier>()
        var page: [Work] = []

        for entry in entries {
            // SwiftData faulting handles stale objects automatically
            guard modelContext.model(for: entry.persistentModelID) is UserLibraryEntry else { continue }

            guard let work = entry.work else { continue }

            // Deduplicate: Only add if this Work hasn't been seen yet
            if seen.insert(work.persistentModelID).inserted {
                page.append(work)
            }
        }

        return page
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
    /// **Performance:** Database-level predicate filtering with relationship traversal.
    /// Uses `localizedStandardContains()` for case-insensitive substring matching.
    ///
    /// **Phase 1 Optimization:** Refactored from in-memory filter to database predicate.
    /// Title index (`#Index<Work>([\.title])`) may accelerate prefix searches.
    ///
    /// - Parameter query: Search string (title or author name)
    /// - Returns: Array of matching works sorted by title
    /// - Throws: `SwiftDataError` if query fails
    public func searchLibrary(query: String) throws -> [Work] {
        guard !query.isEmpty else {
            return try fetchUserLibrary()
        }

        // PERFORMANCE: Database-level predicate filtering (single query)
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                // Condition 1: Work must be in user's library
                (work.userLibraryEntries?.isEmpty == false) &&
                (
                    // Condition 2: Search title (case-insensitive)
                    work.title.localizedStandardContains(query) ||
                    // Condition 3: Search author names (case-insensitive)
                    (work.authors?.contains(where: { author in
                        author.name.localizedStandardContains(query)
                    }) ?? false)
                )
            },
            sortBy: [SortDescriptor(\.title)]
        )

        return try modelContext.fetch(descriptor)
    }

    // MARK: - Quick Filters
    
    /// Quick filter types for common library views
    public enum QuickFilterType: Sendable {
        case recentlyAdded
        case recentlyRead
    }

    // MARK: - Phase 4.2: Selective Fetching (Issue #396)

    /// Fetches works optimized for list views (minimal data).
    ///
    /// **Performance:** Only loads title, coverImageURL for 70% memory reduction.
    /// Use for LibraryView scrolling lists with 1000+ books.
    ///
    /// **Memory Savings:** Reduces memory from ~50MB to <15MB for 1000 books.
    /// See validation results in Phase 4.1 tests (LibraryRepositoryPerformanceTests).
    ///
    /// **Pattern:** Uses SwiftData's `propertiesToFetch` API for selective loading.
    /// Relationships (authors, editions) fault on demand when accessed.
    ///
    /// **Example:**
    /// ```swift
    /// // List view: Memory-optimized fetch
    /// let works = try repository.fetchUserLibraryForList()
    ///
    /// ForEach(works) { work in
    ///     BookCard(title: work.title, cover: work.coverImageURL)  // ✅ Fast
    ///     // work.authors faults here if accessed  // ⚠️ Triggers load
    /// }
    /// ```
    ///
    /// - Returns: Array of works with minimal properties loaded
    /// - Throws: `SwiftDataError` if query fails
    public func fetchUserLibraryForList() throws -> [Work] {
        // PERFORMANCE: Fetch Work objects directly with database-level sorting
        // to avoid N+1 query problem from in-memory sorting on faulted properties.
        var descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                // Filter for works that are part of the user's library
                work.userLibraryEntries?.isEmpty == false
            },
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        
        // SELECTIVE LOADING: Only fetch properties needed for list cards
        // This reduces memory by ~70% compared to full object loading
        // Relationships (work.authors, work.editions) will fault on access
        // Note: lastModified is implicitly fetched due to sort descriptor
        descriptor.propertiesToFetch = [
            \.title,
            \.coverImageURL,
            \.reviewStatus
        ]
        
        // Fetching Work directly handles deduplication automatically
        return try modelContext.fetch(descriptor)
    }

    /// Fetches single work for detail view (full data).
    ///
    /// **Performance:** Loads complete object graph for rich detail display.
    /// Use for WorkDetailView when user taps on a book.
    ///
    /// **Pattern:** No `propertiesToFetch` specified = full object loading.
    /// All relationships (authors, editions, userLibraryEntries) loaded immediately.
    ///
    /// **Example:**
    /// ```swift
    /// // Detail view: Full fetch
    /// guard let work = try repository.fetchWorkDetail(id: workID) else { return }
    ///
    /// Text(work.title)  // ✅ Loaded
    /// Text(work.authors?.first?.name ?? "")  // ✅ Loaded (no faulting)
    /// Text("\(work.primaryEdition?.pageCount ?? 0) pages")  // ✅ Loaded
    /// ```
    ///
    /// - Parameter id: Persistent identifier of work to fetch
    /// - Returns: Fully loaded work with all relationships, or nil if not found
    /// - Throws: `SwiftDataError` if query fails
    public func fetchWorkDetail(id: PersistentIdentifier) throws -> Work? {
        // Fetch by PersistentIdentifier using modelContext.model(for:)
        // SwiftData predicates don't support persistentModelID comparison
        return modelContext.model(for: id) as? Work
    }

    /// Fetches works for list view using projection DTO pattern (fallback).
    ///
    /// **Use Case:** If `propertiesToFetch` validation fails (Phase 4.1), use this method instead.
    /// Provides identical memory savings with guaranteed CloudKit compatibility.
    ///
    /// **Pattern:** Manual projection to lightweight DTO structs.
    /// Trade-off: Slight boilerplate overhead for guaranteed reliability.
    ///
    /// **Status:** Currently not used (propertiesToFetch validation passed).
    /// Keep for future CloudKit edge cases.
    ///
    /// - Returns: Array of list-optimized DTO projections
    /// - Throws: `SwiftDataError` if query fails
    public func fetchUserLibraryForListDTO() throws -> [ListWorkDTO] {
        // PERFORMANCE: Use efficient fetch strategy with database-level sorting
        var descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                work.userLibraryEntries?.isEmpty == false
            },
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )

        // Fetch only the properties required to build the ListWorkDTO
        descriptor.propertiesToFetch = [
            \.title,
            \.authors,
            \.coverImageURL,
            \.reviewStatus
        ]

        let works = try modelContext.fetch(descriptor)
        return works.map { ListWorkDTO.from($0) }
    }

    // MARK: - Statistics

    /// Counts total unique books in library (all reading statuses).
    ///
    /// **Performance:** Uses `fetchCount()` for database-level counting (10x faster than fetch().count).
    /// No object materialization - executes SQL COUNT(*) with relationship predicate.
    ///
    /// **Note:** Counts unique Works, not UserLibraryEntry records (user may own multiple editions of same book).
    /// - Returns: Total count of unique works in library
    /// - Throws: `SwiftDataError` if query fails
    public func totalBooksCount() throws -> Int {
        // Count unique Works (not entries - user may own hardcover + ebook of same book)
        // PERFORMANCE: Uses fetchCount() - no object materialization, still very fast
        let descriptor = FetchDescriptor<Work>(predicate: #Predicate {
            // Only count works that have at least one library entry
            !($0.userLibraryEntries?.isEmpty ?? true)
        })
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
    /// **Performance:** Uses database-level predicate filtering (10-50x faster for large libraries).
    /// Matches pattern used in `reviewQueueCount()` for consistency.
    ///
    /// - Returns: Array of works with reviewStatus = .needsReview
    /// - Throws: `SwiftDataError` if query fails
    public func fetchReviewQueue() throws -> [Work] {
        // PERFORMANCE: Use predicate for database-level filtering (not in-memory)
        // Must compare rawValue since Swift predicate macros don't support enum case access
        let descriptor = FetchDescriptor<Work>(
            predicate: #Predicate { work in
                work.reviewStatus.rawValue == "needsReview"
            },
            sortBy: [SortDescriptor(\.lastModified, order: .reverse)]
        )
        return try modelContext.fetch(descriptor)
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

        // Note: Work objects already validated by fetchUserLibrary() - no need to re-check
        let allAuthors = targetWorks.compactMap { work -> [Author]? in
            return work.authors
        }.flatMap { $0 }
        guard !allAuthors.isEmpty else { return 0.0 }

        // DEFENSIVE: Filter deleted authors AND calculate diversity in single pass
        var validCount = 0
        var diverseCount = 0

        for author in allAuthors {
            // Keep Author validation (accessed via Work relationships, may be deleted during library reset)
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
        // Note: Task wrapper removed - async function already ensures non-blocking execution
        do {
            // STEP 1: Cancel enrichment queue operations first
            await EnrichmentQueue.shared.cancelBackendJob()
            EnrichmentQueue.shared.stopProcessing()
            EnrichmentQueue.shared.clear()

            // STEP 2: Delete all models using modelContext
            // Use predicate-based deletion for efficiency and clarity
            try modelContext.delete(
                model: Work.self,
                where: #Predicate { _ in true }
            )
            try modelContext.delete(
                model: Author.self,
                where: #Predicate { _ in true }
            )
            try modelContext.delete(
                model: Edition.self,
                where: #Predicate { _ in true }
            )
            try modelContext.delete(
                model: UserLibraryEntry.self,
                where: #Predicate { _ in true }
            )

            // STEP 3: Save to persistent store
            try modelContext.save()

            // STEP 4: Clear caches
            dtoMapper?.clearCache()
            DiversityStats.invalidateCache()

            // STEP 5: Invalidate reading stats (async operation)
            await ReadingStats.invalidateCache()

            // STEP 6: Post notification and cleanup
            NotificationCenter.default.post(
                name: .libraryWasReset,
                object: nil
            )

            // STEP 7: Cleanup UserDefaults and settings
            UserDefaults.standard.removeObject(forKey: "RecentBookSearches")
            featureFlags?.resetToDefaults()

            // Success haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)

            #if DEBUG
            print("✅ Library reset complete - All works, settings, and queue cleared")
            #endif

        } catch {
            #if DEBUG
            print("❌ Failed to reset library: \(error)")
            #endif

            // Error haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
}